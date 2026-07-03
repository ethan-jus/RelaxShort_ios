import Foundation

// MARK: - VIP Plan
struct VIPPlan: Identifiable {
    let id: String
    let title: String
    let price: String
    let originalPrice: String?
    let period: String
    let isRecommended: Bool
    let description: String?
    let dailyPrice: String?
    let discountPercent: Int?
}

// MARK: - VIP Benefit
struct VIPBenefit: Identifiable {
    let id: String = UUID().uuidString
    let icon: String
    let title: String
}
