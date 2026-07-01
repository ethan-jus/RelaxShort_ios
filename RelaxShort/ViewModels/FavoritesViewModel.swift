import SwiftUI
import Combine

// MARK: - Favorites ViewModel

/// My List 页面状态机：管理 bookmarks/history 独立分页、trending、编辑和多选删除。
@MainActor
final class FavoritesViewModel: ObservableObject {

    // MARK: - Segment

    enum Segment: CaseIterable { case following, history }
    @Published var selectedSegment: Segment = .following

    // MARK: - Bookmarks

    @Published var bookmarks: [DramaItem] = []
    @Published private(set) var bookmarksCursor: String?
    @Published private(set) var bookmarksHasMore: Bool = false
    @Published private(set) var isBookmarksLoading: Bool = false
    @Published var bookmarksError: String?

    // MARK: - History

    @Published var watchHistory: [WatchHistoryItem] = []
    @Published private(set) var historyCursor: String?
    @Published private(set) var historyHasMore: Bool = false
    @Published private(set) var isHistoryLoading: Bool = false
    @Published var historyError: String?

    // MARK: - Trending

    @Published var trendingEntries: [RankingEntry] = []
    @Published private(set) var isTrendingLoading: Bool = false
    @Published var trendingError: String?

    // MARK: - Editing (Following only)

    @Published var isEditing: Bool = false
    @Published var selectedBookmarkIDs: Set<String> = []
    @Published var isRemoving: Bool = false

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

    // MARK: - Bookmarks

    func loadBookmarks() async {
        guard !isBookmarksLoading else { return }
        isBookmarksLoading = true; bookmarksError = nil
        do {
            let page = try await repository.fetchBookmarks(cursor: nil, limit: 20)
            bookmarks = page.items; bookmarksCursor = page.nextCursor; bookmarksHasMore = page.hasMore
        } catch {
            bookmarksError = error.localizedDescription
        }
        isBookmarksLoading = false
    }

    func loadMoreBookmarks() async {
        guard !isBookmarksLoading, bookmarksHasMore else { return }
        isBookmarksLoading = true
        do {
            let page = try await repository.fetchBookmarks(cursor: bookmarksCursor, limit: 20)
            let existing = Set(bookmarks.map(\.id))
            bookmarks.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            bookmarksCursor = page.nextCursor; bookmarksHasMore = page.hasMore
        } catch { bookmarksError = error.localizedDescription }
        isBookmarksLoading = false
    }

    // MARK: - History

    func loadHistory() async {
        guard !isHistoryLoading else { return }
        isHistoryLoading = true; historyError = nil
        do {
            let page = try await repository.fetchWatchHistory(cursor: nil, limit: 20)
            watchHistory = page.items; historyCursor = page.nextCursor; historyHasMore = page.hasMore
        } catch { historyError = error.localizedDescription }
        isHistoryLoading = false
    }

    func loadMoreHistory() async {
        guard !isHistoryLoading, historyHasMore else { return }
        isHistoryLoading = true
        do {
            let page = try await repository.fetchWatchHistory(cursor: historyCursor, limit: 20)
            let existing = Set(watchHistory.map(\.id))
            watchHistory.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            historyCursor = page.nextCursor; historyHasMore = page.hasMore
        } catch { historyError = error.localizedDescription }
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

    var canEdit: Bool { selectedSegment == .following && !bookmarks.isEmpty }

    func enterEditing() {
        guard canEdit else { return }
        isEditing = true; selectedBookmarkIDs.removeAll()
    }

    func cancelEditing() {
        isEditing = false; selectedBookmarkIDs.removeAll()
    }

    func toggleSelection(id: String) {
        if selectedBookmarkIDs.contains(id) { selectedBookmarkIDs.remove(id) }
        else { selectedBookmarkIDs.insert(id) }
    }

    func removeSelectedBookmarks() async {
        guard !isRemoving, !selectedBookmarkIDs.isEmpty else { return }
        isRemoving = true
        var failed: Set<String> = []
        for id in selectedBookmarkIDs {
            do {
                let ok = try await repository.setBookmarked(false, seriesID: id)
                if ok {
                    bookmarks.removeAll { $0.id == id }
                    bookmarkStore?.applyServerState(false, seriesID: id)
                } else { failed.insert(id) }
            } catch { failed.insert(id) }
        }
        selectedBookmarkIDs = failed
        isRemoving = false
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
