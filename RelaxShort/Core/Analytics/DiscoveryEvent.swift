import Foundation

// MARK: - Discovery Event Models (Task30 R4B-1)

enum DiscoveryEventType: String, Codable, Sendable {
    case searchSubmit = "search_submit"
    case searchResultClick = "search_result_click"
    case contentImpression = "content_impression"
    case qualifiedPlay = "qualified_play"
    case playComplete = "play_complete"
    case bookmark
    case share
}

struct DiscoveryEvent: Codable, Identifiable, Sendable {
    let eventID: UUID
    let eventType: DiscoveryEventType
    let seriesID: Int64?
    let episodeID: Int64?
    let searchTerm: String?
    let contentLanguage: String
    let countryCode: String
    let sourceScene: String
    let occurredAt: Date
    var id: UUID { eventID }

    enum CodingKeys: String, CodingKey {
        case eventID = "eventId"
        case eventType
        case seriesID = "seriesId"
        case episodeID = "episodeId"
        case searchTerm
        case contentLanguage
        case countryCode
        case sourceScene
        case occurredAt
    }
}

struct DiscoveryEventBatchRequest: Encodable, Sendable { let events: [DiscoveryEvent] }

struct DiscoveryEventBatchResponseDTO: Decodable, Sendable {
    let acceptedCount: Int
    let duplicateCount: Int
    let totalCount: Int
}

extension JSONEncoder {
    static func discoveryEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static func discoveryDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
