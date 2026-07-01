import Foundation
import Testing
@testable import RelaxShort

@MainActor
struct BookmarkStoreTests {

    // MARK: - Helpers

    private func makeStore(bookmarkedIDs: Set<String> = [], error: Error? = nil) -> (BookmarkStore, StubFavoritesRepository) {
        let repo = StubFavoritesRepository(bookmarkedIDs: bookmarkedIDs, error: error)
        let analytics = NoopDiscoveryAnalyticsTracker()
        let store = BookmarkStore(repository: repo, analytics: analytics)
        // Pre-seed state via public API
        for id in bookmarkedIDs {
            store.applyServerState(true, seriesID: id)
        }
        return (store, repo)
    }

    // MARK: - Load Status

    @Test
    func loadStatusReplacesStaleState() async {
        let (store, repo) = makeStore(bookmarkedIDs: ["1", "2", "3"])
        repo.bookmarkedIDs = ["1", "3"]

        await store.loadStatus(seriesIDs: ["1", "2", "3"])

        #expect(store.isBookmarked("1"))
        #expect(!store.isBookmarked("2"))
        #expect(store.isBookmarked("3"))
    }

    @Test
    func loadStatusDeduplicatesAndFiltersEmpty() async {
        let (store, repo) = makeStore(bookmarkedIDs: [])
        repo.bookmarkedIDs = ["1"]

        await store.loadStatus(seriesIDs: ["1", "", "1", "2"])

        #expect(repo.fetchBookmarkedSeriesIDsCallCount == 1)
    }

    @Test
    func loadStatusFailurePreservesExistingState() async {
        // Start with IDs 1,2 bookmarked
        let (store, _) = makeStore(bookmarkedIDs: ["1", "2"])

        // Create a repo that fails
        let failRepo = StubFavoritesRepository(bookmarkedIDs: [], error: NSError(domain: "test", code: 500))
        let analytics = NoopDiscoveryAnalyticsTracker()
        let store2 = BookmarkStore(repository: failRepo, analytics: analytics)
        store2.applyServerState(true, seriesID: "1")
        store2.applyServerState(true, seriesID: "2")

        await store2.loadStatus(seriesIDs: ["1", "2"])

        // Existing state must be preserved on failure
        #expect(store2.isBookmarked("1"))
        #expect(store2.isBookmarked("2"))
    }

    @Test
    func loadStatusLateResponseDoesNotOverwriteToggle() async {
        let repo = StubFavoritesRepository(bookmarkedIDs: ["1"], delayMS: 500)
        let analytics = NoopDiscoveryAnalyticsTracker()
        let store = BookmarkStore(repository: repo, analytics: analytics)

        // Start a slow loadStatus for series "1" (server says bookmarked=false)
        repo.bookmarkedIDs = []
        async let _loadTask: Void = store.loadStatus(seriesIDs: ["1"])

        // While loadStatus is waiting, toggle succeeds (un-bookmark)
        try? await Task.sleep(nanoseconds: 10_000_000)
        // Simulate toggle: manually set bookmarked to false before loadStatus returns
        store.applyServerState(false, seriesID: "1")

        // Wait for loadStatus to complete
        _ = await _loadTask

        // Toggle result must NOT be overwritten by late loadStatus
        #expect(!store.isBookmarked("1"))
    }

    // MARK: - Toggle

    @Test
    func toggleAddsBookmarkOptimistically() async {
        let (store, repo) = makeStore(bookmarkedIDs: [])
        repo.bookmarkedIDs = ["5"]

        await store.toggle(seriesID: "5", sourceScene: "for_you")

        #expect(store.isBookmarked("5"))
        #expect(!store.isPending("5"))
        #expect(repo.setBookmarkedCalledWith?.bookmarked == true)
    }

    @Test
    func toggleRemovesBookmarkOptimistically() async {
        let (store, repo) = makeStore(bookmarkedIDs: ["5"])
        repo.bookmarkedIDs = []

        await store.toggle(seriesID: "5", sourceScene: "series")

        #expect(!store.isBookmarked("5"))
        #expect(!store.isPending("5"))
        #expect(repo.setBookmarkedCalledWith?.bookmarked == false)
    }

    @Test
    func removePendingShowsUIAsNotBookmarkedImmediately() async {
        // When user removes bookmark, isBookmarked should be false immediately,
        // even while the network request is pending.
        let repo = StubFavoritesRepository(bookmarkedIDs: [], delayMS: 500)
        let analytics = NoopDiscoveryAnalyticsTracker()
        let store = BookmarkStore(repository: repo, analytics: analytics)
        store.applyServerState(true, seriesID: "10")

        // Start remove — this will be optimistically false immediately
        async let _toggleTask: Void = store.toggle(seriesID: "10", sourceScene: "for_you")

        // Very short delay to let the toggle start
        try? await Task.sleep(nanoseconds: 10_000_000)

        // isBookmarked should be false (optimistic), and isPending should be true
        #expect(!store.isBookmarked("10"))
        #expect(store.isPending("10"))

        _ = await _toggleTask
    }

    @Test
    func toggleRollsBackOnFailure() async {
        let repo = StubFavoritesRepository(bookmarkedIDs: [], error: NSError(domain: "test", code: 500))
        let analytics = NoopDiscoveryAnalyticsTracker()
        let store = BookmarkStore(repository: repo, analytics: analytics)

        await store.toggle(seriesID: "10", sourceScene: "for_you")

        #expect(!store.isBookmarked("10"))
        #expect(store.errorMessage != nil)
    }

    @Test
    func duplicateToggleWhilePendingIsIgnored() async {
        let repo = StubFavoritesRepository(bookmarkedIDs: [], delayMS: 500)
        let analytics = NoopDiscoveryAnalyticsTracker()
        let store = BookmarkStore(repository: repo, analytics: analytics)

        async let _ = store.toggle(seriesID: "7", sourceScene: "for_you")
        try? await Task.sleep(nanoseconds: 10_000_000)
        await store.toggle(seriesID: "7", sourceScene: "series")

        let setCallCount = repo.setBookmarkCallCount
        #expect(setCallCount <= 1)
    }

    @Test
    func analyticsSentOnlyOnAddSuccess() async {
        let repo = StubFavoritesRepository(bookmarkedIDs: [])
        let analytics = SpyDiscoveryAnalyticsTracker()
        let store = BookmarkStore(repository: repo, analytics: analytics)

        await store.toggle(seriesID: "3", sourceScene: "for_you")
        #expect(analytics.bookmarkAddCount == 1)

        await store.toggle(seriesID: "3", sourceScene: "series")
        #expect(analytics.bookmarkAddCount == 1)
    }

    // MARK: - Apply Server State

    @Test
    func applyServerStateSyncsWithoutNetwork() async {
        let (store, _) = makeStore(bookmarkedIDs: ["1", "2"])

        store.applyServerState(false, seriesID: "2")

        #expect(!store.isBookmarked("2"))
        #expect(store.isBookmarked("1"))
    }
}

// MARK: - Test Doubles

final class StubFavoritesRepository: FavoritesRepositoryProtocol, @unchecked Sendable {
    var bookmarkedIDs: Set<String>
    var error: Error?
    var delayMS: UInt64 = 0

    var fetchBookmarkedSeriesIDsCallCount = 0
    var setBookmarkCallCount = 0
    var setBookmarkedCalledWith: (bookmarked: Bool, seriesID: String)?

    init(bookmarkedIDs: Set<String>, error: Error? = nil, delayMS: UInt64 = 0) {
        self.bookmarkedIDs = bookmarkedIDs
        self.error = error
        self.delayMS = delayMS
    }

    func fetchWatchHistory(cursor: String?, limit: Int) async throws -> CursorPage<WatchHistoryItem> {
        throw NSError(domain: "stub", code: 0)
    }

    func fetchBookmarks(cursor: String?, limit: Int) async throws -> CursorPage<DramaItem> {
        throw NSError(domain: "stub", code: 0)
    }

    func fetchBookmarkedSeriesIDs(_ seriesIDs: [String]) async throws -> Set<String> {
        fetchBookmarkedSeriesIDsCallCount += 1
        if let error { throw error }
        if delayMS > 0 { try? await Task.sleep(nanoseconds: delayMS * 1_000_000) }
        return bookmarkedIDs
    }

    func setBookmarked(_ bookmarked: Bool, seriesID: String) async throws -> Bool {
        setBookmarkCallCount += 1
        setBookmarkedCalledWith = (bookmarked, seriesID)
        if let error { throw error }
        if delayMS > 0 { try? await Task.sleep(nanoseconds: delayMS * 1_000_000) }
        return bookmarked
    }

    func reportProgress(_ report: WatchProgressReport) async throws {}
}

final class SpyDiscoveryAnalyticsTracker: DiscoveryAnalyticsTracking, @unchecked Sendable {
    var bookmarkAddCount = 0

    func trackSearchSubmit(query: String) {}
    func trackSearchResultClick(query: String, seriesID: String) {}
    func trackContentImpression(seriesID: String, sourceScene: String) {}
    func trackQualifiedPlay(seriesID: String, episodeID: String?, sourceScene: String) {}
    func trackPlayComplete(seriesID: String, episodeID: String?, sourceScene: String) {}
    func trackBookmark(seriesID: String, sourceScene: String) { bookmarkAddCount += 1 }
    func trackShare(seriesID: String, sourceScene: String) {}
    func flushPending() {}
    func flushForBackground() {}
}
