import Foundation

// MARK: - User Profile Response DTO

/// 对应后端 `GET /api/v2/users/me` 响应 data 字段
/// JSONDecoder 使用 `.convertFromSnakeCase`，后端返回 snake_case 自动映射
struct UserProfileResponseDTO: Decodable {
    let userId: Int64
    let publicId: String
    let accountType: String
    let nickname: String?
    /// `convertFromSnakeCase` 会把 `avatar_url` 转成 `avatarUrl`，
    /// 属性必须保持该拼写，避免 URL 缩写导致头像静默解码为 nil。
    let avatarUrl: String?
    let bookmarkCount: Int?
    let role: String?
    let vipLevel: Int?
    let status: Int?
    let preferences: UserPreferencesDTO?
}

/// 用户偏好子结构
struct UserPreferencesDTO: Decodable {
    let uiLanguage: String?
    let contentLanguage: String?
    let subtitleLanguage: String?
    let defaultQuality: String?
}

// MARK: - Wallet Response DTO

/// 对应后端 `GET /api/v2/users/me/wallet` 响应 data 字段
struct WalletResponseDTO: Decodable {
    let userId: Int64
    let balance: Decimal?
    let totalEarned: Decimal?
    let totalSpent: Decimal?
    let vip: WalletVipDTO?
}

/// 钱包内 VIP 状态子结构
struct WalletVipDTO: Decodable {
    let active: Bool?
    let vipLevel: Int?
    let expiresAt: String?   // ISO 8601 日期字符串，nullable
}
