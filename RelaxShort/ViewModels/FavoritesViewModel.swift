import SwiftUI
import Combine

// MARK: - Favorites ViewModel

/// My List 页面状态机：管理 bookmarks/history 独立分页、trending、编辑和多选删除。
@MainActor
final class FavoritesViewModel: ObservableObject {
    private enum LoadFailureStage { case firstPage, nextPage }

    // MARK: - Segment

    enum Segment: CaseIterable { case following, history }
    @Published var selectedSegment: Segment = .following

    // MARK: - Bookmarks

    @Published var bookmarks: [DramaItem] = []
    @Published private(set) var bookmarksCursor: String?
    @Published private(set) var bookmarksHasMore: Bool = false
    @Published private(set) var isBookmarksLoading: Bool = false
    @Published var bookmarksError: String?
    private var bookmarksFailureStage: LoadFailureStage?

    // MARK: - History

    @Published var watchHistory: [WatchHistoryItem] = []
    @Published private(set) var historyCursor: String?
    @Published private(set) var historyHasMore: Bool = false
    @Published private(set) var isHistoryLoading: Bool = false
    @Published var historyError: String?
    private var historyFailureStage: LoadFailureStage?

    // MARK: - Trending

    @Published var trendingEntries: [RankingEntry] = []
    @Published private(set) var isTrendingLoading: Bool = false
    @Published var trendingError: String?

    // MARK: - Editing

    @Published var isEditing: Bool = false
    @Published var selectedItemIDs: Set<String> = []
    @Published var isRemoving: Bool = false
    @Published var removalError: String?

    // MARK: - Login

    @Published var showLoginModal: Bool = false

    // MARK: - Dependencies

    private let repository: FavoritesRepositoryProtocol
    private let bookmarkStore: BookmarkStore?
    private let homeRepository: HomeRepositoryProtocol?

    // MARK: - Init

    init(repository: FavoritesRepositoryProtocol,
         bookmarkStore: BookmarkStore? = nil,
         homeRepository: HomeRepositoryProtocol? = nil) {
        self.repository = repository
        self.bookmarkStore = bookmarkStore
        self.homeRepository = homeRepository
    }

    // MARK: - Load All

    func loadAll() async {
        async let _b: () = loadBookmarks()
        async let _h: () = loadHistory()
        async let _t: () = loadTrending()
        _ = await (_b, _h, _t)
    }

    /// Tab 激活/登录后刷新用户数据，不清空已有数据
    func refreshUserData() async {
        async let _b: () = loadBookmarks()
        async let _h: () = loadHistory()
        _ = await (_b, _h)
    }

    func retryBookmarks() async {
        switch bookmarksFailureStage {
        case .nextPage: await loadMoreBookmarks()
        case .firstPage, .none: await loadBookmarks()
        }
    }

    func retryHistory() async {
        switch historyFailureStage {
        case .nextPage: await loadMoreHistory()
        case .firstPage, .none: await loadHistory()
        }
    }

    var topTrendingEntries: [RankingEntry] {
        Array(trendingEntries.sorted { $0.rankPosition < $1.rankPosition }.prefix(6))
    }

    // MARK: - Bookmarks

    func loadBookmarks() async {
        guard !isBookmarksLoading else { return }
        isBookmarksLoading = true; bookmarksError = nil
        do {
            let page = try await repository.fetchBookmarks(cursor: nil, limit: 20)
            bookmarks = page.items; bookmarksCursor = page.nextCursor; bookmarksHasMore = page.hasMore
            bookmarksFailureStage = nil
        } catch {
            bookmarksError = error.localizedDescription
            bookmarksFailureStage = .firstPage
        }
        isBookmarksLoading = false
    }

    func loadMoreBookmarks() async {
        guard !isBookmarksLoading, bookmarksHasMore else { return }
        isBookmarksLoading = true
        bookmarksError = nil
        do {
            let page = try await repository.fetchBookmarks(cursor: bookmarksCursor, limit: 20)
            let existing = Set(bookmarks.map(\.id))
            bookmarks.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            bookmarksCursor = page.nextCursor; bookmarksHasMore = page.hasMore
            bookmarksFailureStage = nil
        } catch {
            bookmarksError = error.localizedDescription
            bookmarksFailureStage = .nextPage
        }
        isBookmarksLoading = false
    }

    // MARK: - History

    func loadHistory() async {
        guard !isHistoryLoading else { return }
        isHistoryLoading = true; historyError = nil
        do {
            let page = try await repository.fetchWatchHistory(cursor: nil, limit: 20)
            watchHistory = page.items; historyCursor = page.nextCursor; historyHasMore = page.hasMore
            historyFailureStage = nil
        } catch {
            historyError = error.localizedDescription
            historyFailureStage = .firstPage
        }
        isHistoryLoading = false
    }

    func loadMoreHistory() async {
        guard !isHistoryLoading, historyHasMore else { return }
        isHistoryLoading = true
        historyError = nil
        do {
            let page = try await repository.fetchWatchHistory(cursor: historyCursor, limit: 20)
            let existing = Set(watchHistory.map(\.id))
            watchHistory.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            historyCursor = page.nextCursor; historyHasMore = page.hasMore
            historyFailureStage = nil
        } catch {
            historyError = error.localizedDescription
            historyFailureStage = .nextPage
        }
        isHistoryLoading = false
    }

    // MARK: - Trending

    func loadTrending() async {
        guard !isTrendingLoading, let repo = homeRepository else { return }
        isTrendingLoading = true; trendingError = nil
        do {
            trendingEntries = try await repo.fetchRankingEntries(type: "trending")
        } catch { trendingError = error.localizedDescription }
        isTrendingLoading = false
    }

    // MARK: - Editing

    var canEdit: Bool {
        switch selectedSegment {
        case .following: !bookmarks.isEmpty
        case .history: !watchHistory.isEmpty
        }
    }

    func enterEditing() {
        guard canEdit else { return }
        isEditing = true; selectedItemIDs.removeAll()
    }

    func cancelEditing() {
        isEditing = false; selectedItemIDs.removeAll(); removalError = nil
    }

    func toggleSelection(id: String) {
        if selectedItemIDs.contains(id) { selectedItemIDs.remove(id) }
        else { selectedItemIDs.insert(id) }
    }

    func removeSelectedItems() async {
        guard !isRemoving, !selectedItemIDs.isEmpty else { return }
        isRemoving = true; removalError = nil
        var failed: Set<String> = []
        let segment = selectedSegment
        for id in selectedItemIDs {
            do {
                switch segment {
                case .following:
                    let ok = try await repository.setBookmarked(false, seriesID: id)
                    if !ok {
                        failed.insert(id)
                        continue
                    }
                    bookmarks.removeAll { $0.id == id }
                    bookmarkStore?.applyServerState(false, seriesID: id)
                case .history:
                    try await repository.deleteWatchHistory(seriesID: id)
                    watchHistory.removeAll { $0.drama.id == id }
                }
            } catch { failed.insert(id) }
        }

        // DELETE 可能已在服务端成功，但客户端因响应中断误判失败。
        // Following 可通过状态接口精确对账，避免退出重进后项目消失却仍提示删除失败。
        if segment == .following, !failed.isEmpty {
            do {
                let stillBookmarked = try await repository.fetchBookmarkedSeriesIDs(Array(failed))
                let confirmedRemoved = failed.subtracting(stillBookmarked)
                for id in confirmedRemoved {
                    bookmarks.removeAll { $0.id == id }
                    bookmarkStore?.applyServerState(false, seriesID: id)
                }
                failed = stillBookmarked
            } catch {
                // 对账失败时保留原失败集合，避免错误地从本地移除仍在服务端的收藏。
            }
        }

        selectedItemIDs = failed
        isRemoving = false
        if !failed.isEmpty { removalError = L10n.myListPartialRemoveFailed }
        if failed.isEmpty { cancelEditing() }
    }

    // MARK: - Derived

    /// 构建 history 查找表（by drama.id）
    func historyItem(for dramaID: String) -> WatchHistoryItem? {
        watchHistory.first { $0.drama.id == dramaID }
    }

    // MARK: - Login

    func presentLoginModal() { showLoginModal = true }
    func dismissLoginModal() { showLoginModal = false }
}
