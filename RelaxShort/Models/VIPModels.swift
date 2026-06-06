import Foundation

// MARK: - VIP 套餐模型
struct VIPPlan: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
    let originalPrice: String?
    let period: String
    let isRecommended: Bool
    let description: String?
    let dailyPrice: String?
    let discountPercent: Int?

    // Week会员特殊描述
    var weeklyDescription: String? {
        id == "weekly" ? "前3周$12.99/周，然后$19.99/周" : nil
    }

    static func == (lhs: VIPPlan, rhs: VIPPlan) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - VIP 权益模型
struct VIPBenefit: Identifiable {
    let id: String
    let icon: String
    let title: String

    init(id: String = UUID().uuidString, icon: String, title: String) {
        self.id = id
        self.icon = icon
        self.title = title
    }
}
