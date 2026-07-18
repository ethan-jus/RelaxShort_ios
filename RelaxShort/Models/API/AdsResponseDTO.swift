import Foundation

struct AdsConfigResponseDTO: Decodable {
    let adsEnabled: Bool?
    let appOpen: AdPlacementConfigDTO?
    let rewardedEarnCoins: AdPlacementConfigDTO?
    let interstitialUnlockEpisode: AdPlacementConfigDTO?
    let interstitial: AdPlacementConfigDTO?
}

struct AdPlacementConfigDTO: Decodable {
    let enabled: Bool?
    let adUnitId: String?
    let adFormat: String?
    let rewardCoins: Decimal?
    let maxPerUserPerDay: Int?
    let cooldownSeconds: Int?
}

struct AdRewardStartResponseDTO: Decodable {
    let sessionId: Int64
    let placementCode: String
    let adUnitId: String
    let adFormat: String
    let rewardType: String
    let rewardCoins: Decimal?
    let targetEpisodeId: Int64?
    let ssvCustomData: String
    let expiresAt: String?
}

struct AdRewardCompleteResponseDTO: Decodable {
    let sessionId: Int64
    let status: String
    let pendingVerification: Bool
    let rewardCoins: Decimal?
}
