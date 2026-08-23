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
    /// replace 与 append 共用同一 latest-wins 门禁，语言/国家切换会立即使全部旧响应失效。
    private var requestGate = LatestRequestGate()

    private struct PendingPage {
        let items: [DramaItem]
        let sessionID: String?
        let nextCursor: String?
        let hasMore: Bool
    }

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
        let requestGeneration = requestGate.begin()
        let contentLanguage = ContentLanguagePreference.effectiveLanguage
        let country = ContentLanguagePreference.countryCode
        let seed = UUID().uuidString
        isLoading = true
        errorMessage = nil
        defer {
            if requestGate.accepts(requestGeneration) {
                isLoading = false
            }
        }

        feedSessionId = seed
        nextCursor = nil
        hasMore = true
        isLoadingMore = false
        displayedSeriesIDs.removeAll()

        do {
            let result = try await repository.fetchForYouPaginated(
                contentLang: contentLanguage,
                country: country,
                cursor: nil,
                limit: pageSize,
                feedSeed: seed
            )
            guard requestGate.accepts(requestGeneration) else { return }
            feedSessionId = seed
            nextCursor = result.nextCursor
            hasMore = result.hasMore
            let unique = rememberUnique(result.items)
            dramas = unique
            onReplaceCompleted?(unique)
        } catch {
            guard requestGate.accepts(requestGeneration), !Task.isCancelled else { return }
            errorMessage = L10n.recommendLoadFailed
            #if DEBUG
            Logger.viewModel.error("RecommendViewModel.loadData failed: \(error)")
            #endif
            dramas = []
        }
    }

    /// 内容语言切换时立即清除旧语言播放列表，再请求新的严格语言 Feed。
    func reloadForContentLanguageChange() async {
        await reloadForDiscoveryContextChange()
    }

    /// 国家变化与内容语言变化使用相同 replace 语义：先清旧播放列表，再加载最新发现上下文。
    func reloadForDiscoveryCountryChange() async {
        await reloadForDiscoveryContextChange()
    }

    private func reloadForDiscoveryContextChange() async {
        dramas = []
        onReplaceCompleted?([])
        await loadData()
    }

    /// 加载下一页（接近末尾时自动触发）。
    /// 当前 seed 耗尽后自动生成新 seed 续流，并过滤已展示剧集，避免用户滑到末尾卡死。
    /// TASK-0001-D: append 绑定发起时 generation，过期自动丢弃。
    func loadNextPageIfNeeded(currentIndex: Int) async {
        guard !isLoading, !isLoadingMore, !dramas.isEmpty else { return }
        // 当距离末尾剩余 3 个以内时触发预加载
        let threshold = max(0, dramas.count - 3)
        guard currentIndex >= threshold else { return }

        let appendGeneration = requestGate.generation
        let appendSessionGeneration = session?.feedGeneration
        let appendStartIndex = dramas.count
        let contentLanguage = ContentLanguagePreference.effectiveLanguage
        let country = ContentLanguagePreference.countryCode
        let startingSessionID = feedSessionId
        let startingCursor = nextCursor
        let startingHasMore = hasMore
        isLoadingMore = true
        defer {
            if requestGate.accepts(appendGeneration) {
                isLoadingMore = false
            }
        }

        do {
            let page = try await loadNextPage(
                contentLanguage: contentLanguage,
                country: country,
                sessionID: startingSessionID,
                cursor: startingCursor,
                hasMore: startingHasMore,
                requestGeneration: appendGeneration
            )

            // ViewModel replace 与播放器 Session replace 任一发生，都丢弃旧分页响应及游标。
            guard requestGate.accepts(appendGeneration) else { return }
            if let appendSessionGeneration,
               let currentGeneration = session?.feedGeneration,
               appendSessionGeneration != currentGeneration {
                #if DEBUG
                print("[RecommendVM] loadNextPage 被丢弃 gen=\(appendSessionGeneration) 当前gen=\(currentGeneration) — feed 已被 replace")
                #endif
                return
            }

            feedSessionId = page.sessionID
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            let newItems = rememberUnique(page.items)
            guard !newItems.isEmpty else { return }
            dramas.append(contentsOf: newItems)
            onAppendCompleted?(newItems, appendStartIndex)
        } catch {
            guard requestGate.accepts(appendGeneration), !Task.isCancelled else { return }
            #if DEBUG
            Logger.viewModel.error("RecommendViewModel.loadNextPage failed: \(error)")
            #endif
            // 静默失败，不覆盖已有数据
        }
    }

    // MARK: - Private

    /// 加载下一页；所有游标先在局部推进，通过 generation 门禁后才提交到页面状态。
    private func loadNextPage(
        contentLanguage: String,
        country: String?,
        sessionID: String?,
        cursor: String?,
        hasMore: Bool,
        requestGeneration: Int
    ) async throws -> PendingPage {
        var workingSessionID = sessionID
        var workingCursor = cursor
        var workingHasMore = hasMore

        // 最多连续探测 3 页：如果新 seed 首页全是已看内容，继续翻一页找新内容。
        for _ in 0..<3 {
            guard requestGate.accepts(requestGeneration) else {
                return PendingPage(
                    items: [],
                    sessionID: workingSessionID,
                    nextCursor: workingCursor,
                    hasMore: workingHasMore
                )
            }
            if workingSessionID == nil || (!workingHasMore && workingCursor == nil) {
                workingSessionID = UUID().uuidString
                workingCursor = nil
                workingHasMore = true
            }

            let result = try await repository.fetchForYouPaginated(
                contentLang: contentLanguage,
                country: country,
                cursor: workingCursor,
                limit: pageSize,
                feedSeed: workingSessionID
            )
            guard requestGate.accepts(requestGeneration) else {
                return PendingPage(
                    items: [],
                    sessionID: workingSessionID,
                    nextCursor: workingCursor,
                    hasMore: workingHasMore
                )
            }
            workingCursor = result.nextCursor
            workingHasMore = result.hasMore

            let uniqueItems = result.items.filter {
                $0.toPlayerMediaItem() != nil && !displayedSeriesIDs.contains($0.id)
            }
            if !uniqueItems.isEmpty {
                return PendingPage(
                    items: uniqueItems,
                    sessionID: workingSessionID,
                    nextCursor: workingCursor,
                    hasMore: workingHasMore
                )
            }

            if !workingHasMore {
                // 当前 seed 没有更多内容且本页也没有新内容，下一轮换 seed 再试。
                workingSessionID = nil
                workingCursor = nil
            }
        }

        return PendingPage(
            items: [],
            sessionID: workingSessionID,
            nextCursor: workingCursor,
            hasMore: workingHasMore
        )
    }

    /// 记录并返回本页面会话尚未展示过的剧集。
    private func rememberUnique(_ items: [DramaItem]) -> [DramaItem] {
        var result: [DramaItem] = []
        // For You 只保留拥有预览播放源的卡片。锁集权益只属于 Series，
        // 不可播放卡片若留在 UI 数组中会与 RecommendSession 的播放索引错位并锁住上滑。
        for item in items where item.toPlayerMediaItem() != nil && !displayedSeriesIDs.contains(item.id) {
            displayedSeriesIDs.insert(item.id)
            result.append(item)
        }
        return result
    }
}
