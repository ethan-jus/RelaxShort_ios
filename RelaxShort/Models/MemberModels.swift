import Foundation

// MARK: - Member Plan Display Option

/// Member 套餐展示选项（仅 UI 展示用，非后端数据）。
/// 第一版为临时配置，不关联 StoreKit 商品或后端价格。
struct MemberPlanDisplayOption: Identifiable, Equatable {
    let id: String
    /// 本地化 key 对应的套餐标题
    let titleKey: String
    /// 展示价格（USD 字符串）
    let price: String
    /// 划线原价，空则不显示
    let originalPrice: String?
    /// 本地化 key 对应的详细说明
    let detailKey: String
    /// 是否展示促销倒计时徽标
    let showsPromotion: Bool
}

// MARK: - Member Display Config

/// Member 页面第一版临时展示配置。
/// 套餐价格、权益文案和促销信息均为静态展示，不驱动购买或 StoreKit 行为。
/// 后续接入后端套餐配置时替换此枚举。
enum MemberDisplayConfig {

    /// 当前选中的套餐 ID
    static let defaultSelectedPlanID = "weekly"

    /// 第一版套餐列表
    static let plans: [MemberPlanDisplayOption] = [
        .init(
            id: "weekly",
            titleKey: "member.plan.weekly",
            price: "$12.99",
            originalPrice: "$19.99",
            detailKey: "member.plan.weekly_detail",
            showsPromotion: true
        ),
        .init(
            id: "yearly",
            titleKey: "member.plan.yearly",
            price: "$149.99/year",
            originalPrice: nil,
            detailKey: "member.plan.yearly_detail",
            showsPromotion: false
        )
    ]

    /// 权益列表
    struct Benefit: Identifiable {
        let id: String
        let icon: String
        let titleKey: String
        let detailKey: String?
    }

    static let benefits: [Benefit] = [
        .init(id: "unlimited", icon: "infinity", titleKey: "member.benefit.unlimited", detailKey: "member.benefit.unlimited_detail"),
        .init(id: "download", icon: "arrow.down.to.line", titleKey: "member.benefit.download", detailKey: nil),
        .init(id: "points", icon: "star.fill", titleKey: "member.benefit.points", detailKey: nil),
        .init(id: "exclusive", icon: "play.rectangle", titleKey: "member.benefit.exclusive", detailKey: nil),
        .init(id: "quality", icon: "4k.tv", titleKey: "member.benefit.quality", detailKey: nil),
        .init(id: "gift", icon: "gift.fill", titleKey: "member.benefit.gift_drama", detailKey: nil),
        .init(id: "membership", icon: "person.2.fill", titleKey: "member.benefit.gift_membership", detailKey: nil),
        .init(id: "themes", icon: "paintpalette.fill", titleKey: "member.benefit.themes", detailKey: nil),
        .init(id: "ad_free", icon: "speaker.slash.fill", titleKey: "member.benefit.ad_free", detailKey: nil)
    ]

    /// 促销倒计时初始秒数（1 小时）
    static let promotionDuration: Int = 3600
}
