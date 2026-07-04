import Foundation

/// 用户模型 — 包含个人信息、会员状态、金币余额等核心字段
struct User: Codable, Identifiable, Equatable {
    /// 用户唯一标识
    let id: String
    /// 用户昵称
    var nickname: String
    /// 用户头像 URL（可选，nil 时使用默认头像）
    var avatarURL: String?
    /// 是否 VIP 会员
    var isVip: Bool
    /// VIP 过期时间（非会员时为 nil）
    var vipExpireDate: Date?
    /// 金币余额
    var coinBalance: Int
    /// 用户收藏的短剧数量
    var favoriteCount: Int
    /// 画质等级 (如 "1080P")
    var qualityLevel: String?
    /// 剧集总数
    var totalDramas: Int?
    /// 福利中心金币
    var benefitCoins: Int?
    
    // MARK: - Computed Properties
    
    /// VIP 是否有效（含过期判断）
    var isVipValid: Bool {
        guard isVip, let expireDate = vipExpireDate else { return false }
        return expireDate > Date()
    }
    
    /// 会员剩余天数（非会员返回 0）
    var vipRemainingDays: Int {
        guard let expireDate = vipExpireDate, isVip else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expireDate).day ?? 0
        return max(days, 0)
    }
}
