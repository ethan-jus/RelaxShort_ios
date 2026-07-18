import Foundation

final class RealAdConfigRepository: AdConfigRepositoryProtocol {
    private let client = APIClient.shared

    func fetchAdsConfig() async throws -> AdsConfig {
        let dto: AdsConfigResponseDTO = try await client.requestData(.adsConfig)
        return AdsConfig(
            adsEnabled: dto.adsEnabled ?? false,
            appOpen: Self.map(dto.appOpen, placementCode: "app_open"),
            rewardedEarnCoins: Self.map(dto.rewardedEarnCoins, placementCode: "rewarded_earn_coins"),
            interstitialUnlockEpisode: Self.map(
                dto.interstitialUnlockEpisode,
                placementCode: "interstitial_unlock_episode"
            ),
            interstitial: Self.map(dto.interstitial, placementCode: "episode_transition")
        )
    }

    private static func map(
        _ dto: AdPlacementConfigDTO?,
        placementCode: String
    ) -> AdPlacementConfig {
        AdPlacementConfig(
            placementCode: placementCode,
            enabled: dto?.enabled ?? false,
            adUnitID: dto?.adUnitId ?? "",
            format: AdFormat(rawValue: dto?.adFormat ?? "") ?? .unknown,
            rewardCoins: dto?.rewardCoins.map { Int(truncating: $0 as NSNumber) } ?? 0,
            maxPerUserPerDay: dto?.maxPerUserPerDay ?? 0,
            cooldownSeconds: dto?.cooldownSeconds ?? 0
        )
    }
}

final class RealAdRewardRepository: AdRewardRepositoryProtocol {
    private let client = APIClient.shared

    func startSession(
        placementCode: String,
        rewardType: String,
        targetEpisodeID: String?
    ) async throws -> AdRewardSession {
        let key = "ios-ad-start-\(UUID().uuidString)"
        let dto: AdRewardStartResponseDTO = try await client.requestData(
            .adsRewardStart(
                placementCode: placementCode,
                rewardType: rewardType,
                targetEpisodeID: targetEpisodeID,
                idempotencyKey: key
            )
        )
        return AdRewardSession(
            id: dto.sessionId,
            idempotencyKey: key,
            placement: AdPlacementConfig(
                placementCode: dto.placementCode,
                enabled: true,
                adUnitID: dto.adUnitId,
                format: AdFormat(rawValue: dto.adFormat) ?? .unknown,
                rewardCoins: dto.rewardCoins.map { Int(truncating: $0 as NSNumber) } ?? 0,
                maxPerUserPerDay: 0,
                cooldownSeconds: 0
            ),
            rewardType: dto.rewardType,
            ssvCustomData: dto.ssvCustomData
        )
    }

    func completeSession(_ session: AdRewardSession) async throws -> AdRewardCompletion {
        let dto: AdRewardCompleteResponseDTO = try await client.requestData(
            .adsRewardComplete(
                sessionID: session.id,
                placementCode: session.placement.placementCode,
                idempotencyKey: session.idempotencyKey
            )
        )
        return AdRewardCompletion(
            status: dto.status,
            pendingVerification: dto.pendingVerification
        )
    }

    func cancelSession(_ session: AdRewardSession) async {
        let _: AdRewardCancelResponseDTO? = try? await client.requestData(
            .adsRewardCancel(
                sessionID: session.id,
                placementCode: session.placement.placementCode,
                idempotencyKey: session.idempotencyKey
            )
        )
    }
}
