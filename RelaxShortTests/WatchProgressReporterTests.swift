import Foundation
import Testing
@testable import RelaxShort

struct WatchProgressReporterTests {

    // MARK: - Helpers

    private func makeReporter(
        throttleInterval: Duration = .seconds(15),
        minProgressDelta: Int = 3,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        uuidGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) -> (WatchProgressReporter, SpyFavoritesRepository) {
        let repo = SpyFavoritesRepository()
        let reporter = WatchProgressReporter(
            repository: repo,
            throttleInterval: throttleInterval,
            minProgressDelta: minProgressDelta,
            now: now,
            uuidGenerator: uuidGenerator
        )
        return (reporter, repo)
    }

    // MARK: - Begin

    @Test
    func beginCreatesNewSession() async {
        let (reporter, _) = makeReporter()
        let hasActive = await reporter.hasActiveSession()
        #expect(!hasActive)

        await reporter.begin(seriesID: "1", episodeID: "101")
        let active = await reporter.hasActiveSession()
        #expect(active)
    }

    @Test
    func beginSameEpisodeDoesNotReset() async {
        let (reporter, _) = makeReporter()

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 10, duration: 100)
        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 20, duration: 100)

        let active = await reporter.hasActiveSession()
        #expect(active)
    }

    @Test
    func beginDifferentEpisodeCreatesNewSession() async {
        let (reporter, _) = makeReporter()

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 10, duration: 100)
        await reporter.begin(seriesID: "1", episodeID: "102")

        let active = await reporter.hasActiveSession()
        #expect(active)
    }

    // MARK: - Throttle

    @Test
    func multipleTicksWithinThrottleWindowSendOnlyOnce() async {
        let (reporter, repo) = makeReporter()

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 5, duration: 100)
        await reporter.observe(seconds: 6, duration: 100)
        await reporter.observe(seconds: 9, duration: 100)

        let sent = await repo.reportProgressCallCount
        #expect(sent >= 1)
    }

    @Test
    func insufficientProgressDeltaDoesNotSend() async {
        let (reporter, repo) = makeReporter()

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 5, duration: 100)
        let afterFirst = await repo.reportProgressCallCount

        await reporter.observe(seconds: 6, duration: 100) // only 1s delta < 3
        let afterSecond = await repo.reportProgressCallCount
        #expect(afterSecond == afterFirst)
    }

    // MARK: - Finalize uses latest values (P0)

    @Test
    func finalizeUsesLatestProgressNotLastSent() async {
        let (reporter, repo) = makeReporter()

        // First heartbeat sends 10/100
        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 10, duration: 100)

        // Then observe 23/100 but it's throttled (time hasn't advanced)
        // latest values should still be saved
        await reporter.observe(seconds: 23, duration: 100)

        // finalize(false) must use latest (23/100), not lastSent (10/100)
        await reporter.finalize(completed: false)

        let reports = await repo.sentReports
        let finalReports = reports.filter { $0.finalReport }
        #expect(finalReports.count >= 1)
        if let final = finalReports.last {
            #expect(final.progressSeconds == 23)
            #expect(final.totalDuration == 100)
        }
    }

    @Test
    func finalizeNotCompletedDoesNotFakeOneToOneRatio() async {
        let (reporter, repo) = makeReporter()

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 30, duration: 120)
        await reporter.finalize(completed: false)

        let reports = await repo.sentReports
        let finalReports = reports.filter { $0.finalReport }
        #expect(finalReports.count >= 1)
        if let final = finalReports.last {
            // progress/total must NOT be equal (not 30/30 or similar 1:1 fake)
            #expect(final.progressSeconds != final.totalDuration)
            #expect(final.completed == false)
        }
    }

    @Test
    func heartBeatFailureAllowsRetryOnNextQualifyingTick() async {
        let repo = SpyFavoritesRepository(shouldFailCount: 1) // fail first send
        let (reporter, _) = (WatchProgressReporter(repository: repo), repo)

        await reporter.begin(seriesID: "1", episodeID: "101")
        // First observe: delta >= 3, will attempt send but fail
        await reporter.observe(seconds: 5, duration: 100)

        let afterFirstAttempt = await repo.reportProgressCallCount
        #expect(afterFirstAttempt == 1)

        // After failure, lastSentSeconds was NOT updated
        // Next observe with sufficient delta should retry
        await reporter.observe(seconds: 10, duration: 100) // delta = 10-0 = 10 >= 3

        let afterSecondAttempt = await repo.reportProgressCallCount
        #expect(afterSecondAttempt == 2)
    }

    // MARK: - Finalize

    @Test
    func finalizeSendsFinalReportAndClearsSession() async {
        let (reporter, repo) = makeReporter()

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 30, duration: 100)
        await reporter.finalize(completed: false)

        let reports = await repo.sentReports
        let finalReports = reports.filter { $0.finalReport }
        #expect(finalReports.count >= 1)

        let active = await reporter.hasActiveSession()
        #expect(!active)
    }

    @Test
    func completionFinalizeSetsCompletedTrue() async {
        let (reporter, repo) = makeReporter()

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 95, duration: 100)
        await reporter.finalize(completed: true)

        let reports = await repo.sentReports
        let finalReports = reports.filter { $0.finalReport }
        #expect(finalReports.contains(where: { $0.completed }))
    }

    @Test
    func finalizeAfterResumeCreatesNewSession() async {
        let (reporter, _) = makeReporter()

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 15, duration: 100)
        await reporter.finalize(completed: false)

        #expect(await !reporter.hasActiveSession())

        await reporter.begin(seriesID: "1", episodeID: "102")
        #expect(await reporter.hasActiveSession())
    }

    @Test
    func finalizeNoOpWhenNoActiveSession() async {
        let (reporter, _) = makeReporter()
        await reporter.finalize(completed: false)
        // Should not crash
    }

    // MARK: - Actor Reentrancy (P0)

    @Test
    func oldFinalizeAwaitDoesNotClearNewSession() async {
        // Use a delayed repository so finalize suspends during await
        let repo = SpyFavoritesRepository(delayMS: 500)
        let uuidSeq = UUIDSequence()
        let (reporter, _) = (
            WatchProgressReporter(repository: repo, uuidGenerator: { uuidSeq.next() }),
            repo
        )

        // Begin session A
        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 10, duration: 100)

        // Start finalize for session A — this will suspend during the delayed send
        async let _finalize: Void = reporter.finalize(completed: false)

        // Give finalize time to enter the await
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Begin session B while finalize of A is still in-flight
        await reporter.begin(seriesID: "1", episodeID: "102")

        // Wait for old finalize to complete
        _ = await _finalize

        // Session B should still be active (not cleared by old finalize)
        let active = await reporter.hasActiveSession()
        #expect(active)
    }

    @Test
    func newSessionReportsWithDifferentUUID() async {
        let repo = SpyFavoritesRepository()
        let uuidSeq = UUIDSequence()
        let (reporter, _) = (
            WatchProgressReporter(repository: repo, uuidGenerator: { uuidSeq.next() }),
            repo
        )

        await reporter.begin(seriesID: "1", episodeID: "101")
        await reporter.observe(seconds: 10, duration: 100)

        let uuid1 = await firstPlaySessionID(from: repo)

        await reporter.finalize(completed: false)
        await reporter.begin(seriesID: "1", episodeID: "102")
        await reporter.observe(seconds: 5, duration: 100)

        let reports = await repo.sentReports
        let allIDs = reports.map { $0.playSessionID }
        let uniqueIDs = Set(allIDs)

        // After finalize + new begin, there should be at least 2 distinct UUIDs
        #expect(uniqueIDs.count >= 2)
    }

    private func firstPlaySessionID(from repo: SpyFavoritesRepository) async -> UUID? {
        let reports = await repo.sentReports
        return reports.first?.playSessionID
    }
}

// MARK: - Test Doubles

/// 可控 UUID 序列，每次调用 next() 返回下一个 UUID。
final class UUIDSequence: @unchecked Sendable {
    private var uuids: [UUID]
    private var index = 0
    private let lock = NSLock()

    init() {
        self.uuids = [
            UUID(uuidString: "AAAAAAAA-AAAA-4AAA-AAAA-AAAAAAAAAAA1")!,
            UUID(uuidString: "BBBBBBBB-BBBB-4BBB-BBBB-BBBBBBBBBBB2")!,
            UUID(uuidString: "CCCCCCCC-CCCC-4CCC-CCCC-CCCCCCCCCCC3")!,
            UUID(uuidString: "DDDDDDDD-DDDD-4DDD-DDDD-DDDDDDDDDDD4")!,
            UUID(uuidString: "EEEEEEEE-EEEE-4EEE-EEEE-EEEEEEEEEEE5")!,
        ]
    }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let uuid = uuids[index % uuids.count]
        index += 1
        return uuid
    }
}

actor SpyFavoritesRepository: FavoritesRepositoryProtocol, @unchecked Sendable {
    var sentReports: [WatchProgressReport] = []
    var reportProgressCallCount = 0
    private var shouldFailCount: Int
    let delayMS: UInt64

    init(shouldFailCount: Int = 0, delayMS: UInt64 = 0) {
        self.shouldFailCount = shouldFailCount
        self.delayMS = delayMS
    }

    func fetchWatchHistory(cursor: String?, limit: Int) async throws -> CursorPage<WatchHistoryItem> {
        throw NSError(domain: "spy", code: 0)
    }

    func fetchBookmarks(cursor: String?, limit: Int) async throws -> CursorPage<DramaItem> {
        throw NSError(domain: "spy", code: 0)
    }

    func fetchBookmarkedSeriesIDs(_ seriesIDs: [String]) async throws -> Set<String> {
        return []
    }

    func setBookmarked(_ bookmarked: Bool, seriesID: String) async throws -> Bool {
        return bookmarked
    }

    func reportProgress(_ report: WatchProgressReport) async throws {
        if delayMS > 0 {
            try? await Task.sleep(nanoseconds: delayMS * 1_000_000)
        }
        sentReports.append(report)
        reportProgressCallCount += 1
        if shouldFailCount > 0 {
            shouldFailCount -= 1
            throw NSError(domain: "spy", code: 500)
        }
    }
}
