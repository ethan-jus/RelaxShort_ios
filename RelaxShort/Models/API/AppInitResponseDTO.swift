import Foundation

// MARK: - App Init Response DTO

/// 对应后端 `AppInitResponse`（snake_case → JSONDecoder convertFromSnakeCase）
struct AppInitResponseDTO: Decodable {
    let uiLanguage: String
    let contentLanguage: String
    let countryCode: String
    let fallbackLanguages: [String]?
    let mixRatio: MixRatioDTO?
    let matchedLanguage: String?
    let fallbackReason: String?
    let update: UpdateInfoDTO?
    let ads: AdsConfigDTO?
}

struct MixRatioDTO: Decodable {
    // JSON object e.g. {"zh-Hans":0.5,"en":0.5}，用 key-value 动态映射
}

struct UpdateInfoDTO: Decodable {
    let updateRequired: Bool?
    let updateRecommended: Bool?
    let updateType: String?
    let latestVersionName: String?
    let storeUrl: String?
    let releaseNotes: ReleaseNotesDTO?
}

struct AdsConfigDTO: Decodable {
    let adsEnabled: Bool?
    let appOpenEnabled: Bool?
    let rewardedEnabled: Bool?
    let interstitialEnabled: Bool?
    let rewardedInterstitialEnabled: Bool?
    let configCacheSeconds: Int?
}

// 使用泛型容器处理动态 key 的 JSON（如 release_notes 多语言 map）
struct ReleaseNotesDTO: Decodable {
    // 作为占位 — 后端目前以 Object 返回
}
