import SwiftUI

// MARK: - Recommend ViewModel

/// 推荐页沉浸式视频流 ViewModel — DramaBox 标准
/// Task36A: 支持 seed 扰动 + 游标分页，避免每次进入第一屏固定同一批视频。
@MainActor
final class RecommendViewModel: ObservableObject {
    @Published var dramas: [DramaItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasMore: Bool = true

    private let repository: HomeRepositoryProtocol
    private let pageSize: Int = 10

    /// 本次推荐会话的唯一种子，初次进入时生成。
    /// 同一 session 内翻页复用此种子，保证分页稳定；刷新/重新进入生成新种子。
    private var feedSessionId: String?
    /// 后端游标，用于翻页。格式取决于后端行为（无种子时 score:id，有种子时 s:seedHash:position）。
    private var nextCursor: String?
    /// 正在加载中标记，防止重复触发
    private var isLoadingMore: Bool = false

    init(repository: HomeRepositoryProtocol) {
        self.repository = repository
    }

    /// 首次加载（或下拉刷新）→ 生成新种子，清空旧数据。
    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        feedSessionId = nil
        nextCursor = nil
        hasMore = true
        isLoadingMore = false

        do {
            let result = try await loadFirstPage()
            dramas = result
        } catch {
            errorMessage = L10n.recommendLoadFailed
            #if DEBUG
            Logger.viewModel.error("RecommendViewModel.loadData failed: \(error)")
            #endif
            dramas = []
        }
    }

    /// 加载下一页（接近末尾时自动触发）。
    /// 只在 hasMore=true 且未在加载中时执行。
    func loadNextPageIfNeeded(currentIndex: Int) async {
        guard hasMore, !isLoadingMore, !dramas.isEmpty else { return }
        // 当距离末尾剩余 3 个以内时触发预加载
        let threshold = max(0, dramas.count - 3)
        guard currentIndex >= threshold else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let newItems = try await loadNextPage()
            guard !newItems.isEmpty else { return }
            dramas.append(contentsOf: newItems)
        } catch {
            #if DEBUG
            Logger.viewModel.error("RecommendViewModel.loadNextPage failed: \(error)")
            #endif
            // 静默失败，不覆盖已有数据
        }
    }

    // MARK: - Private

    /// 生成种子并请求首页
    private func loadFirstPage() async throws -> [DramaItem] {
        let seed = UUID().uuidString
        feedSessionId = seed

        // Home 首页优先，不可用时走 For You
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")

        if let homeItems = try? await fetchHomeFirstPage(contentLang: contentLang, country: country),
           !homeItems.isEmpty {
            return homeItems
        }

        return try await fetchForYouFirstPage(contentLang: contentLang, country: country, seed: seed)
    }

    /// 请求 For You 首页（带 seed）
    private func fetchForYouFirstPage(contentLang: String?, country: String?, seed: String) async throws -> [DramaItem] {
        // 需要访问 RealHomeRepository 的 paginated 方法
        guard let realRepo = repository as? RealHomeRepository else {
            return try await repository.fetchDramas(category: .all)
        }
        let result = try await realRepo.fetchForYouPaginated(
            contentLang: contentLang, country: country,
            cursor: nil, limit: pageSize, feedSeed: seed
        )
        nextCursor = result.nextCursor
        hasMore = result.hasMore
        return result.items
    }

    /// 请求 Home 首页
    private func fetchHomeFirstPage(contentLang: String?, country: String?) async throws -> [DramaItem]? {
        guard let realRepo = repository as? RealHomeRepository else { return nil }
        let tabs = try await realRepo.fetchHomeTabs(contentLang: contentLang, country: country)
        for tab in tabs {
            for section in tab.sections {
                if !section.items.isEmpty {
                    return section.items
                }
            }
        }
        return nil
    }

    /// 加载下一页（复用已生成的 seed 和 nextCursor）
    private func loadNextPage() async throws -> [DramaItem] {
        guard let realRepo = repository as? RealHomeRepository else {
            return []
        }
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")
        let result = try await realRepo.fetchForYouPaginated(
            contentLang: contentLang, country: country,
            cursor: nextCursor, limit: pageSize,
            feedSeed: feedSessionId
        )
        nextCursor = result.nextCursor
        hasMore = result.hasMore
        return result.items
    }
}
