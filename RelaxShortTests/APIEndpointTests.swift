import Foundation
import Testing
@testable import RelaxShort

@Suite(.serialized)
struct APIEndpointTests {
    @Test
    func protectedEndpointsDoNotUseLegacyUserIdentityHeader() {
        let report = WatchProgressReport(
            seriesID: "1", episodeID: "1", progressSeconds: 0, totalDuration: 1,
            completed: false,
            playSessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            finalReport: false, sourceType: nil, quality: nil,
            contentLanguage: nil, subtitleLanguage: nil
        )
        let endpoints: [APIEndpoint] = [
            .episodePlay(episodeId: "101"),
            .watchHistoryV2(cursor: nil, limit: 20),
            .deleteWatchHistory(seriesID: "1"),
            .watchProgress(report),
            .bookmarksV2(cursor: nil, limit: 20),
            .bookmarkStatus(seriesIDs: ["1"]),
            .setBookmark(seriesID: "1", bookmarked: true)
        ]
        for endpoint in endpoints {
            #expect(endpoint.headers["X-User-Id"] == nil)
        }
    }

    @Test
    func watchHistoryEndpointHasCursorAndLimit() {
        let endpoint = APIEndpoint.watchHistoryV2(cursor: "cursor-abc", limit: 10)
        #expect(endpoint.path == "/api/v2/watch-history")
        #expect(endpoint.method == .get)
        let items = endpoint.url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems ?? []
        #expect(items.contains { $0.name == "cursor" && $0.value == "cursor-abc" })
        #expect(items.contains { $0.name == "limit" && $0.value == "10" })
    }

    @Test
    func watchProgressUsesSnakeCaseBody() {
        let report = WatchProgressReport(
            seriesID: "123", episodeID: "456", progressSeconds: 30, totalDuration: 120,
            completed: false,
            playSessionID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            finalReport: false, sourceType: "mp4", quality: "auto",
            contentLanguage: "en", subtitleLanguage: nil
        )
        let endpoint = APIEndpoint.watchProgress(report)
        let dictionary = endpoint.body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        #expect(endpoint.method == .post)
        #expect(dictionary?["series_id"] as? String == "123")
        #expect(dictionary?["progress_seconds"] as? Int == 30)
        #expect(dictionary?["play_session_id"] as? String == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
    }

    @Test
    func bookmarkEndpointsHaveExpectedMethods() {
        let add = APIEndpoint.setBookmark(seriesID: "42", bookmarked: true)
        let remove = APIEndpoint.setBookmark(seriesID: "42", bookmarked: false)
        #expect(add.path == "/api/v2/series/42/bookmark")
        #expect(add.method == .post)
        #expect(remove.method == .delete)
        #expect(remove.body == nil)
    }
}
