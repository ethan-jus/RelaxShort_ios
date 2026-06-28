import Foundation
import Testing
@testable import RelaxShort

@Suite(.serialized)
struct APIEndpointTests {
    @Test
    func episodePlayCarriesLocalUserIdentityInRealAPIMode() {
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

        defaults.set(true, forKey: "use_real_api")
        StorageService.shared.userId = nil

        #expect(APIEndpoint.episodePlay(episodeId: "101").headers["X-User-Id"] == "1")
    }
}
