import Foundation

// MARK: - UI Analytics Client (Task30 R4B-1)

@MainActor protocol DiscoveryAnalyticsTracking: Sendable {
    func trackSearchSubmit(query: String)
    func trackSearchResultClick(query: String, seriesID: String)
    func trackContentImpression(seriesID: String, sourceScene: String)
    func trackQualifiedPlay(seriesID: String, episodeID: String?, sourceScene: String)
    func trackPlayComplete(seriesID: String, episodeID: String?, sourceScene: String)
    func trackBookmark(seriesID: String, sourceScene: String)
    func trackShare(seriesID: String, sourceScene: String)
    func flushPending()
    func flushForBackground()
}

@MainActor struct NoopDiscoveryAnalyticsTracker: DiscoveryAnalyticsTracking {
    func trackSearchSubmit(query: String) {}
    func trackSearchResultClick(query: String, seriesID: String) {}
    func trackContentImpression(seriesID: String, sourceScene: String) {}
    func trackQualifiedPlay(seriesID: String, episodeID: String?, sourceScene: String) {}
    func trackPlayComplete(seriesID: String, episodeID: String?, sourceScene: String) {}
    func trackBookmark(seriesID: String, sourceScene: String) {}
    func trackShare(seriesID: String, sourceScene: String) {}
    func flushPending() {}
    func flushForBackground() {}
}

@MainActor final class DiscoveryAnalyticsClient: DiscoveryAnalyticsTracking {
    private let reporter: DiscoveryAnalyticsReporter
    init(reporter: DiscoveryAnalyticsReporter = DiscoveryAnalyticsReporter()) { self.reporter = reporter }

    func trackSearchSubmit(query: String) {
        let e = buildEvent(type: .searchSubmit, query: query, seriesID: nil, episodeID: nil, sourceScene: "search")
        Task { await reporter.track(e) }
    }
    func trackSearchResultClick(query: String, seriesID: String) {
        guard let sid = Int64(seriesID) else { return }
        let e = buildEvent(type: .searchResultClick, query: query, seriesID: sid, episodeID: nil, sourceScene: "search")
        Task { await reporter.track(e) }
    }
    func trackContentImpression(seriesID: String, sourceScene: String) {
        track(type: .contentImpression, seriesID: seriesID, episodeID: nil, sourceScene: sourceScene)
    }
    func trackQualifiedPlay(seriesID: String, episodeID: String?, sourceScene: String) {
        track(type: .qualifiedPlay, seriesID: seriesID, episodeID: episodeID, sourceScene: sourceScene)
    }
    func trackPlayComplete(seriesID: String, episodeID: String?, sourceScene: String) {
        track(type: .playComplete, seriesID: seriesID, episodeID: episodeID, sourceScene: sourceScene)
    }
    func trackBookmark(seriesID: String, sourceScene: String) {
        track(type: .bookmark, seriesID: seriesID, episodeID: nil, sourceScene: sourceScene)
    }
    func trackShare(seriesID: String, sourceScene: String) {
        track(type: .share, seriesID: seriesID, episodeID: nil, sourceScene: sourceScene)
    }
    func flushPending() { Task { await reporter.flush() } }
    func flushForBackground() { Task { await reporter.flushForBackground() } }

    private func track(type: DiscoveryEventType, seriesID: String, episodeID: String?, sourceScene: String) {
        guard let sid = Int64(seriesID) else { return }
        let event = buildEvent(
            type: type,
            query: nil,
            seriesID: sid,
            episodeID: episodeID.flatMap(Int64.init),
            sourceScene: sourceScene
        )
        Task { await reporter.track(event) }
    }

    private func buildEvent(
        type: DiscoveryEventType,
        query: String?,
        seriesID: Int64?,
        episodeID: Int64?,
        sourceScene: String
    ) -> DiscoveryEvent {
        DiscoveryEvent(eventID: UUID(), eventType: type, seriesID: seriesID, episodeID: episodeID, searchTerm: query,
                        contentLanguage: UserDefaults.standard.string(forKey: "app_content_language") ?? "en",
                        countryCode: UserDefaults.standard.string(forKey: "app_country_code") ?? "GLOBAL",
                        sourceScene: sourceScene, occurredAt: Date())
    }
}
