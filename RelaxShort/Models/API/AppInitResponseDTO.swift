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
    let supportedLanguages: [SupportedLanguageDTO]?
    let update: UpdateInfoDTO?
    let ads: AdsConfigDTO?
}

struct SupportedLanguageDTO: Decodable {
    let code: String
    let nameEn: String?
    let nameNative: String?
    let localizedName: String?
    let sortOrder: Int?
}

struct MixRatioDTO: Decodable {
    // JSON object e.g. {"zh-Hans":0.5,"en":0.5}，用 key-value 动态映射
}

struct UpdateInfoDTO: Decodable {
    let updateRequired: Bool?
    let updateRecommended: Bool?
    let updateType: String?
    let latestVersionName: String?
    let latestVersionCode: Int?
    let storeUrl: String?
    let releaseNotes: [String: String]?
}

struct AdsConfigDTO: Decodable {
    let adsEnabled: Bool?
    let appOpenEnabled: Bool?
    let rewardedEnabled: Bool?
    let interstitialEnabled: Bool?
    let rewardedInterstitialEnabled: Bool?
    let configCacheSeconds: Int?
}
