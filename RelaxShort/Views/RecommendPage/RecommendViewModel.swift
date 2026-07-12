import SwiftUI

// MARK: - Recommend ViewModel

/// 推荐页沉浸式视频流 ViewModel — DramaBox 标准
/// Task36A: 支持 seed 扰动 + 游标分页，避免每次进入第一屏固定同一批视频。
/// TASK-0001-D: 增加 feed generation 机制，区分 replace/append，丢弃过期分页回调。
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
    /// 当前页面会话已经展示过的 seriesId，用于 seed 耗尽后换 seed 续流时去重。
    private var displayedSeriesIDs = Set<String>()

    /// TASK-0001-D: 关联的 RecommendSession，用于 generation 同步
    weak var session: RecommendSession?

    /// TASK-0001-D: feed mutation 回调 — replace 完成后通知 View 层
    var onReplaceCompleted: (@MainActor ([DramaItem]) -> Void)?
    /// TASK-0001-D: append 完成后通知 View 层
    var onAppendCompleted: (@MainActor ([DramaItem], Int) -> Void)?

    init(repository: HomeRepositoryProtocol) {
        self.repository = repository
    }

    /// 首次加载（或下拉刷新）→ 生成新种子，清空旧数据。
    /// TASK-0001-D: replace 创建新 generation，旧分页回调被 generation 门禁丢弃。
    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        feedSessionId = nil
        nextCursor = nil
        hasMore = true
        isLoadingMore = false
        displayedSeriesIDs.removeAll()

        do {
            let result = try await loadFirstPage()
            let unique = rememberUnique(result)
            dramas = unique
            onReplaceCompleted?(unique)
        } catch {
            errorMessage = L10n.recommendLoadFailed
            #if DEBUG
            Logger.viewModel.error("RecommendViewModel.loadData failed: \(error)")
            #endif
            dramas = []
        }
    }

    /// 加载下一页（接近末尾时自动触发）。
    /// 当前 seed 耗尽后自动生成新 seed 续流，并过滤已展示剧集，避免用户滑到末尾卡死。
    /// TASK-0001-D: append 绑定发起时 generation，过期自动丢弃。
    func loadNextPageIfNeeded(currentIndex: Int) async {
        guard !isLoadingMore, !dramas.isEmpty else { return }
        // 当距离末尾剩余 3 个以内时触发预加载
        let threshold = max(0, dramas.count - 3)
        guard currentIndex >= threshold else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let appendGen = session?.feedGeneration
        let appendStartIndex = dramas.count

        do {
            let newItems = try await loadNextPage()
            guard !newItems.isEmpty else { return }

            // generation 门禁：请求期间若发生 replace，丢弃结果
            if let ag = appendGen, let currentGen = session?.feedGeneration, ag != currentGen {
                #if DEBUG
                print("[RecommendVM] loadNextPage 被丢弃 gen=\(ag) 当前gen=\(currentGen) — feed 已被 replace")
                #endif
                return
            }

            dramas.append(contentsOf: newItems)
            onAppendCompleted?(newItems, appendStartIndex)
        } catch {
            #if DEBUG
            Logger.viewModel.error("RecommendViewModel.loadNextPage failed: \(error)")
            #endif
            // 静默失败，不覆盖已有数据
        }
    }

    // MARK: - Private

    /// 生成种子并请求首页。
    /// For You 页面直接使用 /api/v2/feed/for-you（不优先走 Home），确保 seed 真正生效。
    private func loadFirstPage() async throws -> [DramaItem] {
        let seed = UUID().uuidString
        feedSessionId = seed

        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")

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

    /// 加载下一页；当前 seed 耗尽后自动开启新 seed。
    private func loadNextPage() async throws -> [DramaItem] {
        guard let realRepo = repository as? RealHomeRepository else {
            return []
        }
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")

        // 最多连续探测 3 页：如果新 seed 首页全是已看内容，继续翻一页找新内容。
        for _ in 0..<3 {
            if feedSessionId == nil || (!hasMore && nextCursor == nil) {
                feedSessionId = UUID().uuidString
                nextCursor = nil
                hasMore = true
            }

            let result = try await realRepo.fetchForYouPaginated(
                contentLang: contentLang, country: country,
                cursor: nextCursor, limit: pageSize,
                feedSeed: feedSessionId
            )
            nextCursor = result.nextCursor
            hasMore = result.hasMore

            let uniqueItems = rememberUnique(result.items)
            if !uniqueItems.isEmpty {
                return uniqueItems
            }

            if !hasMore {
                // 当前 seed 没有更多内容且本页也没有新内容，下一轮换 seed 再试。
                feedSessionId = nil
                nextCursor = nil
            }
        }

        return []
    }

    /// 记录并返回本页面会话尚未展示过的剧集。
    private func rememberUnique(_ items: [DramaItem]) -> [DramaItem] {
        var result: [DramaItem] = []
        for item in items where !displayedSeriesIDs.contains(item.id) {
            displayedSeriesIDs.insert(item.id)
            result.append(item)
        }
        return result
    }
}
