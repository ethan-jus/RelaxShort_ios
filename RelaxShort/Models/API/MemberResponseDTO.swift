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
    let plans: [PlanDTO]?
    let benefits: [BenefitDTO]?
    let legalLinks: LegalLinksDTO?

    struct PlanDTO: Decodable {
        let productCode: String
        let storeProductId: String
        let titleKey: String
        let detailKey: String
        let sortOrder: Int?
        let promotion: PromotionDTO?
    }

    struct PromotionDTO: Decodable {
        let campaignCode: String
        let offerType: String
        let paymentMode: String
        let periodUnit: String
        let periodValue: Int
        let periodCount: Int
        let badgeKey: String
        let titleKey: String
        let startsAtEpochSeconds: TimeInterval
        let endsAtEpochSeconds: TimeInterval
    }

    struct BenefitDTO: Decodable {
        let code: String
        let icon: String?
        let titleKey: String
        let detailKey: String?
    }

    struct LegalLinksDTO: Decodable {
        let termsUrl: String
        let privacyUrl: String
    }
}
