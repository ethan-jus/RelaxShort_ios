import Foundation
import Testing
@testable import RelaxShort

struct DiscoveryEventTests {
    @Test
    func playbackEventEncodesBackendContract() throws {
        let event = DiscoveryEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            eventType: .qualifiedPlay,
            seriesID: 20250312000003,
            episodeID: 2025031200000301,
            searchTerm: nil,
            contentLanguage: "en",
            countryCode: "GLOBAL",
            sourceScene: "rankings",
            occurredAt: Date(timeIntervalSince1970: 0)
        )

        let data = try JSONEncoder.discoveryEncoder().encode(event)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["event_type"] as? String == "qualified_play")
        #expect(json["series_id"] as? Int64 == 20250312000003)
        #expect(json["episode_id"] as? Int64 == 2025031200000301)
        #expect(json["source_scene"] as? String == "rankings")
    }
}
