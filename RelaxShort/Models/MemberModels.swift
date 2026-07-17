import Foundation

// MARK: - Member Plan Display

/// Member 套餐展示选项。商品可售范围来自后端，价格与优惠资格来自 StoreKit。
struct MemberPlanDisplayOption: Identifiable, Equatable {
    let id: String
    let productID: ProductID
    let titleKey: String
    let detailKey: String
    let promotion: MemberPromotion?
}

enum MemberPromotionOfferType: String, Equatable {
    case introductory
}

enum MemberPromotionPaymentMode: String, Equatable {
    case payAsYouGo = "pay_as_you_go"
    case payUpFront = "pay_up_front"
    case freeTrial = "free_trial"
}

enum MemberPromotionPeriodUnit: String, Equatable {
    case day
    case week
    case month
    case year
}

/// 服务端活动窗口。只有 StoreKit 同时提供匹配优惠时才允许展示。
struct MemberPromotion: Equatable {
    let campaignCode: String
    let offerType: MemberPromotionOfferType
    let paymentMode: MemberPromotionPaymentMode
    let periodUnit: MemberPromotionPeriodUnit
    let periodValue: Int
    let periodCount: Int
    let badgeKey: String
    let titleKey: String
    let startsAt: Date
    let endsAt: Date

    func canDisplay(
        at date: Date,
        hasMatchingStoreOffer: Bool
    ) -> Bool {
        hasMatchingStoreOffer
            && date >= startsAt
            && date <= endsAt
    }
}

struct MemberBenefitDisplayItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let titleKey: String
    let detailKey: String?
}

struct MemberLegalLinks: Equatable {
    let termsURL: URL
    let privacyURL: URL
}

enum MemberPurchasePolicy {
    static func canPurchase(
        hasPlan: Bool,
        hasStorePrice: Bool,
        hasLegalLinks: Bool
    ) -> Bool {
        hasPlan && hasStorePrice && hasLegalLinks
    }
}

enum MemberDisplayConfig {
    /// 年套餐是标准价格下的最低长期成本；最终选项仍以服务端可售目录为准。
    static let defaultSelectedPlanID = "vip_yearly"
}
