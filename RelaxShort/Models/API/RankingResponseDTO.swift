import Foundation

// MARK: - Ranking Response DTO (Task30 R4B-1)
// 项目 Decoder 已使用 .convertFromSnakeCase，DTO 不重复声明 CodingKeys

struct RankingResponseDTO: Decodable, Sendable {
    let type: String
    let contentLanguage: String?
    let countryCode: String?
    let generatedAt: String?
    let matchedLanguage: String?
    let fallbackReason: String?
    let items: [RankingItemDTO]
}

struct RankingItemDTO: Decodable, Sendable {
    let rankPosition: Int
    let metricType: String
    let metricValue: Int64
    let card: FeedCardDTO
}
