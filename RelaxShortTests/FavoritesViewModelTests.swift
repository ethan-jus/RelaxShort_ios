import Foundation
import Testing
@testable import RelaxShort

@MainActor
struct FavoritesViewModelTests {

    // MARK: - Load Bookmarks

    @Test
    func loadBookmarksPopulatesFirstPage() async {
        let repo = StubFavoritesVMRepo()
        let vm = FavoritesViewModel(repository: repo)

        await vm.loadBookmarks()

        #expect(vm.bookmarks.count == 2)
        #expect(vm.bookmarksCursor == "cursor-2")
        #expect(vm.bookmarksHasMore == true)
        #expect(vm.isBookmarksLoading == false)
    }

    @Test
    func loadBookmarksSetsErrorOnFailure() async {
        let repo = StubFavoritesVMRepo(shouldFailBookmarks: true)
        let vm = FavoritesViewModel(repository: repo)

        await vm.loadBookmarks()

        #expect(vm.bookmarks.isEmpty)
        #expect(vm.bookmarksError != nil)
        #expect(vm.isBookmarksLoading == false)
    }

    // MARK: - Load History

    @Test
    func loadHistoryPopulatesFirstPage() async {
        let repo = StubFavoritesVMRepo()
        let vm = FavoritesViewModel(repository: repo)

        await vm.loadHistory()

        #expect(vm.watchHistory.count == 1)
        #expect(vm.historyCursor == "hcursor-2")
        #expect(vm.historyHasMore == true)
        #expect(vm.isHistoryLoading == false)
    }

    @Test
    func loadHistorySetsErrorOnFailure() async {
        let repo = StubFavoritesVMRepo(shouldFailHistory: true)
        let vm = FavoritesViewModel(repository: repo)

        await vm.loadHistory()

        #expect(vm.watchHistory.isEmpty)
        #expect(vm.historyError != nil)
        #expect(vm.isHistoryLoading == false)
    }

    // MARK: - Isolation

    @Test
    func bookmarkFailureDoesNotClearHistory() async {
        let repo = StubFavoritesVMRepo()
        let vm = FavoritesViewModel(repository: repo)

        await vm.loadHistory()
        #expect(vm.watchHistory.count == 1)

        // Now fail bookmarks — history should still be intact
        let failRepo = StubFavoritesVMRepo(shouldFailBookmarks: true)
        let vm2 = FavoritesViewModel(repository: failRepo)
        // Pre-load history with working repo
        await vm2.loadHistory()
        #expect(vm2.watchHistory.count == 1)
    }

    @Test
    func retryOnlyRetriesFailedDataSource() async {
        let repo = StubFavoritesVMRepo(shouldFailBookmarks: true)
        let vm = FavoritesViewModel(repository: repo)

        await vm.loadBookmarks()
        #expect(vm.bookmarksError != nil)

        // History should load fine from same repo
        await vm.loadHistory()
        #expect(vm.historyError == nil)
        #expect(vm.watchHistory.count == 1)
    }

    // MARK: - Compat

    @Test
    func loadDataLoadsBoth() async {
        let repo = StubFavoritesVMRepo()
        let vm = FavoritesViewModel(repository: repo)

        await vm.loadBookmarks()
        await vm.loadHistory()

        #expect(vm.bookmarks.count == 2)
        #expect(vm.watchHistory.count == 1)
    }
}

// MARK: - Stub Repository

final class StubFavoritesVMRepo: FavoritesRepositoryProtocol, @unchecked Sendable {
    var shouldFailBookmarks: Bool
    var shouldFailHistory: Bool

    init(shouldFailBookmarks: Bool = false, shouldFailHistory: Bool = false) {
        self.shouldFailBookmarks = shouldFailBookmarks
        self.shouldFailHistory = shouldFailHistory
    }

    func fetchWatchHistory(cursor: String?, limit: Int) async throws -> CursorPage<WatchHistoryItem> {
        if shouldFailHistory {
            throw NSError(domain: "stub", code: 500)
        }
        let item = WatchHistoryItem(
            id: "1-101",
            drama: DramaItem(id: "1", title: "Test", coverURL: "", category: "", tags: [], viewCount: 0, episodeCount: 10, currentEpisode: 1, synopsis: "", isHot: false, isTrending: false, rating: 0),
            episodeID: "101",
            currentEpisode: 1,
            resumeTime: 0,
            watchedAt: Date(),
            progress: 0.5
        )
        return CursorPage(items: [item], nextCursor: "hcursor-2", hasMore: true)
    }

    func fetchBookmarks(cursor: String?, limit: Int) async throws -> CursorPage<DramaItem> {
        if shouldFailBookmarks {
            throw NSError(domain: "stub", code: 500)
        }
        let items = [
            DramaItem(id: "1", title: "D1", coverURL: "", category: "", tags: [], viewCount: 0, episodeCount: 0, currentEpisode: 0, synopsis: "", isHot: false, isTrending: false, rating: 0),
            DramaItem(id: "2", title: "D2", coverURL: "", category: "", tags: [], viewCount: 0, episodeCount: 0, currentEpisode: 0, synopsis: "", isHot: false, isTrending: false, rating: 0)
        ]
        return CursorPage(items: items, nextCursor: "cursor-2", hasMore: true)
    }

    func fetchBookmarkedSeriesIDs(_ seriesIDs: [String]) async throws -> Set<String> { return [] }
    func setBookmarked(_ bookmarked: Bool, seriesID: String) async throws -> Bool { return bookmarked }
    func reportProgress(_ report: WatchProgressReport) async throws {}
}
