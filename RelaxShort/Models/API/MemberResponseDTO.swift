import Foundation

// MARK: - Member Response DTO

/// 对应后端 `MemberResponse`（snake_case → JSONDecoder convertFromSnakeCase）
struct MemberResponseDTO: Decodable {
    let contentLanguage: String?
    let countryCode: String?
    let matchedLanguage: String?
    let fallbackReason: String?
    let backgroundPosters: [FeedCardDTO]
    let memberOnlyDramas: [FeedCardDTO]
}
