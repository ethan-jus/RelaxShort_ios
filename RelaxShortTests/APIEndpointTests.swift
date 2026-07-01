import Foundation
import Testing
@testable import RelaxShort

@Suite(.serialized)
struct APIEndpointTests {

    // MARK: - Helpers

    /// Saves and restores UserDefaults/StorageService state around a test.
    private func withUserDefaultsRestored(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let originalRealAPI = defaults.object(forKey: "use_real_api")
        let originalUserID = StorageService.shared.userId
        defer {
            if let originalRealAPI {
                defaults.set(originalRealAPI, forKey: "use_real_api")
            } else {
                defaults.removeObject(forKey: "use_real_api")
            }
            StorageService.shared.userId = originalUserID
        }
        body()
    }

    private func enableRealAPI() {
        UserDefaults.standard.set(true, forKey: "use_real_api")
        StorageService.shared.userId = nil
    }

    // MARK: - Existing

    @Test
    func episodePlayCarriesLocalUserIdentityInRealAPIMode() {
        withUserDefaultsRestored {
            enableRealAPI()
            #expect(APIEndpoint.episodePlay(episodeId: "101").headers["X-User-Id"] == "1")
        }
    }

    // MARK: - Task31: watchHistoryV2

    @Test
    func watchHistoryV2PathAndMethod() {
        withUserDefaultsRestored {
            enableRealAPI()
            let endpoint = APIEndpoint.watchHistoryV2(cursor: nil, limit: 20)
            #expect(endpoint.path == "/api/v2/watch-history")
            #expect(endpoint.method == .get)
            #expect(endpoint.headers["X-User-Id"] == "1")
        }
    }

    @Test
    func watchHistoryV2CursorAndLimitInQuery() {
        let endpoint = APIEndpoint.watchHistoryV2(cursor: "cursor-abc", limit: 10)
        let url = endpoint.url
        #expect(url != nil)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(components != nil)
        let items = components?.queryItems ?? []
        #expect(items.contains(where: { $0.name == "cursor" && $0.value == "cursor-abc" }))
        #expect(items.contains(where: { $0.name == "limit" && $0.value == "10" }))
    }

    // MARK: - Task31: watchProgress

    @Test
    func watchProgressPathMethodAndBody() {
        withUserDefaultsRestored {
            enableRealAPI()
            let report = WatchProgressReport(
                seriesID: "123",
                episodeID: "456",
                progressSeconds: 30,
                totalDuration: 120,
                completed: false,
                playSessionID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
                finalReport: false,
                sourceType: "mp4",
                quality: "auto",
                contentLanguage: "en",
                subtitleLanguage: nil
            )
            let endpoint = APIEndpoint.watchProgress(report)
            #expect(endpoint.path == "/api/v2/watch-progress")
            #expect(endpoint.method == .post)
            #expect(endpoint.headers["X-User-Id"] == "1")

            // Snake case body with UUID
            let body = endpoint.body
            #expect(body != nil)
            if let body {
                let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                #expect(dict != nil)
                #expect(dict?["series_id"] as? String == "123")
                #expect(dict?["episode_id"] as? String == "456")
                #expect(dict?["progress_seconds"] as? Int == 30)
                #expect(dict?["total_duration"] as? Int == 120)
                #expect(dict?["completed"] as? Bool == false)
                #expect(dict?["final_report"] as? Bool == false)
                #expect(dict?["play_session_id"] as? String == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
            }
        }
    }

    // MARK: - Task31: bookmarksV2

    @Test
    func bookmarksV2PathMethodAndHeaders() {
        withUserDefaultsRestored {
            enableRealAPI()
            let endpoint = APIEndpoint.bookmarksV2(cursor: nil, limit: 20)
            #expect(endpoint.path == "/api/v2/users/me/bookmarks")
            #expect(endpoint.method == .get)
            #expect(endpoint.headers["X-User-Id"] == "1")
        }
    }

    @Test
    func bookmarksV2CursorAndLimitQuery() {
        let endpoint = APIEndpoint.bookmarksV2(cursor: "cursor-xyz", limit: 15)
        let url = endpoint.url
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let items = components?.queryItems ?? []
        #expect(items.contains(where: { $0.name == "cursor" && $0.value == "cursor-xyz" }))
        #expect(items.contains(where: { $0.name == "limit" && $0.value == "15" }))
    }

    // MARK: - Task31: bookmarkStatus

    @Test
    func bookmarkStatusPathMethodAndSeriesIDs() {
        withUserDefaultsRestored {
            enableRealAPI()
            let endpoint = APIEndpoint.bookmarkStatus(seriesIDs: ["1", "3", "5"])
            #expect(endpoint.path == "/api/v2/users/me/bookmark-status")
            #expect(endpoint.method == .get)
            #expect(endpoint.headers["X-User-Id"] == "1")

            let url = endpoint.url
            let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            let items = components?.queryItems ?? []
            let idsItem = items.first(where: { $0.name == "series_ids" })
            #expect(idsItem?.value == "1,3,5")
        }
    }

    // MARK: - Task31: setBookmark (POST/DELETE)

    @Test
    func setBookmarkPostPathAndMethod() {
        withUserDefaultsRestored {
            enableRealAPI()
            let endpoint = APIEndpoint.setBookmark(seriesID: "42", bookmarked: true)
            #expect(endpoint.path == "/api/v2/series/42/bookmark")
            #expect(endpoint.method == .post)
            #expect(endpoint.headers["X-User-Id"] == "1")
        }
    }

    @Test
    func setBookmarkDeletePathMethodAndNilBody() {
        withUserDefaultsRestored {
            enableRealAPI()
            let endpoint = APIEndpoint.setBookmark(seriesID: "42", bookmarked: false)
            #expect(endpoint.path == "/api/v2/series/42/bookmark")
            #expect(endpoint.method == .delete)
            #expect(endpoint.headers["X-User-Id"] == "1")
            // DELETE must not have a body
            #expect(endpoint.body == nil)
        }
    }

    // MARK: - Task31: X-User-Id presence on all new endpoints

    @Test
    func allNewEndpointsIncludeXUserIdHeader() {
        withUserDefaultsRestored {
            enableRealAPI()
            let report = WatchProgressReport(
                seriesID: "1", episodeID: "1", progressSeconds: 0, totalDuration: 1,
                completed: false,
                playSessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                finalReport: false, sourceType: nil, quality: nil,
                contentLanguage: nil, subtitleLanguage: nil
            )
            let endpoints: [APIEndpoint] = [
                .watchHistoryV2(cursor: nil, limit: 20),
                .watchProgress(report),
                .bookmarksV2(cursor: nil, limit: 20),
                .bookmarkStatus(seriesIDs: ["1"]),
                .setBookmark(seriesID: "1", bookmarked: true),
            ]
            for endpoint in endpoints {
                #expect(endpoint.headers["X-User-Id"] == "1",
                        "Missing X-User-Id for \(endpoint.path)")
            }
        }
    }
}
