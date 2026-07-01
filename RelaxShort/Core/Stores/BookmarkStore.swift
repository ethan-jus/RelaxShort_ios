import Foundation

// MARK: - BookmarkStore

/// App 会话内收藏状态的单一来源。
/// For You、Series、My List 共享同一实例，由 DependencyContainer 持有。
@MainActor
final class BookmarkStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var bookmarkedIDs: Set<String> = []
    @Published private(set) var pendingIDs: Set<String> = []
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let repository: FavoritesRepositoryProtocol
    private let analytics: DiscoveryAnalyticsTracking

    // MARK: - Internal State

    /// Per-series version counter，用于防止迟到 loadStatus 覆盖 toggle 结果。
    /// 每次 toggle 成功 +1；loadStatus 返回时检查版本是否一致。
    private var seriesVersions: [String: Int] = [:]

    // MARK: - Init

    init(repository: FavoritesRepositoryProtocol, analytics: any DiscoveryAnalyticsTracking) {
        self.repository = repository
        self.analytics = analytics
    }

    // MARK: - Query

    /// 是否已收藏（仅由乐观更新后的 bookmarkedIDs 决定；
    /// pendingIDs 只用于禁止重复点击）。
    func isBookmarked(_ seriesID: String) -> Bool {
        bookmarkedIDs.contains(seriesID)
    }

    /// 是否正在请求中
    func isPending(_ seriesID: String) -> Bool {
        pendingIDs.contains(seriesID)
    }

    /// 批量查询收藏状态。去重、过滤空值、每批最多 50 个。
    /// 查询结果会替换被查询 ID 的本地状态（先移除，再合并返回结果），
    /// 避免服务端已取消的陈旧状态残留。
    ///
    /// - 单批失败不清除该批已有本地状态。
    /// - 迟到响应不会覆盖查询开始后发生的 toggle（通过版本号保护）。
    func loadStatus(seriesIDs: [String]) async {
        let deduped = Array(Set(seriesIDs.filter { !$0.isEmpty }))
        guard !deduped.isEmpty else { return }

        // 快照当前版本，用于检测并发 toggle
        let requestVersions = Dictionary(
            uniqueKeysWithValues: deduped.map { ($0, seriesVersions[$0] ?? 0) }
        )

        let batchSize = 50
        for chunk in stride(from: 0, to: deduped.count, by: batchSize) {
            let batch = Array(deduped[chunk..<min(chunk + batchSize, deduped.count)])
            do {
                let result = try await repository.fetchBookmarkedSeriesIDs(batch)
                // 逐 ID 更新，跳过被并发 toggle 修改的 series
                for id in batch {
                    guard seriesVersions[id] == requestVersions[id] else { continue }
                    if result.contains(id) {
                        bookmarkedIDs.insert(id)
                    } else {
                        bookmarkedIDs.remove(id)
                    }
                }
            } catch {
                // 单批失败保留该批已有本地状态，不清理
                Logger.viewModel.warning("BookmarkStore: loadStatus batch failed: \(error)")
            }
        }
    }

    // MARK: - Toggle

    /// 切换收藏状态。同一 series pending 时忽略重复点击。
    func toggle(seriesID: String, sourceScene: String) async {
        guard !pendingIDs.contains(seriesID) else { return }

        let wasBookmarked = bookmarkedIDs.contains(seriesID)
        let targetState = !wasBookmarked

        // 乐观更新
        pendingIDs.insert(seriesID)
        if targetState {
            bookmarkedIDs.insert(seriesID)
        } else {
            bookmarkedIDs.remove(seriesID)
        }

        do {
            let serverState = try await repository.setBookmarked(targetState, seriesID: seriesID)
            pendingIDs.remove(seriesID)
            // 以服务端返回为准
            if serverState {
                bookmarkedIDs.insert(seriesID)
            } else {
                bookmarkedIDs.remove(seriesID)
            }
            // bump version 以防护迟到 loadStatus 覆盖
            seriesVersions[seriesID] = (seriesVersions[seriesID] ?? 0) + 1
            // 只有新增收藏成功才发 analytics
            if targetState, serverState {
                analytics.trackBookmark(seriesID: seriesID, sourceScene: sourceScene)
            }
        } catch {
            // 回滚
            pendingIDs.remove(seriesID)
            if wasBookmarked {
                bookmarkedIDs.insert(seriesID)
            } else {
                bookmarkedIDs.remove(seriesID)
            }
            errorMessage = error.localizedDescription
            Logger.viewModel.error("BookmarkStore: toggle failed for \(seriesID): \(error)")
        }
    }

    // MARK: - External Sync

    /// My List 删除成功后使用的显式同步方法，不重复发网络。
    func applyServerState(_ bookmarked: Bool, seriesID: String) {
        if bookmarked {
            bookmarkedIDs.insert(seriesID)
        } else {
            bookmarkedIDs.remove(seriesID)
        }
        pendingIDs.remove(seriesID)
        seriesVersions[seriesID] = (seriesVersions[seriesID] ?? 0) + 1
    }
}
