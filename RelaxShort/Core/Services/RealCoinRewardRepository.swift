import Foundation

final class RealCoinRewardRepository: CoinRewardRepositoryProtocol {
    private let client = APIClient.shared

    func fetchRewardCenter() async throws -> RewardCenterState {
        let dto: RewardCenterResponseDTO = try await client.requestData(.rewardCenter)
        return Self.map(dto)
    }

    func checkIn() async throws -> RewardCenterState {
        let key = "ios-check-in-\(UUID().uuidString)"
        let dto: RewardCenterResponseDTO = try await client.requestData(
            .rewardCheckIn(idempotencyKey: key)
        )
        return Self.map(dto)
    }

    func recordShare(
        seriesID: String,
        episodeID: String?,
        channel: String,
        idempotencyKey: String
    ) async throws -> RewardCenterState {
        let dto: RewardCenterResponseDTO = try await client.requestData(
            .rewardShareComplete(
                seriesID: seriesID,
                episodeID: episodeID,
                channel: channel,
                idempotencyKey: idempotencyKey
            )
        )
        return Self.map(dto)
    }

    func applyInviteCode(_ code: String) async throws -> RewardCenterState {
        let dto: RewardCenterResponseDTO = try await client.requestData(
            .rewardApplyInviteCode(code: code)
        )
        return Self.map(dto)
    }

    private static func map(_ dto: RewardCenterResponseDTO) -> RewardCenterState {
        RewardCenterState(
            coinBalance: int(dto.coinBalance),
            firstCoinPurchaseBonusAvailable: dto.firstCoinPurchaseBonusAvailable,
            remainingEarnableCoins: int(dto.remainingEarnableCoins),
            claimedCheckInToday: dto.checkIn.claimedToday,
            completedCheckInDays: dto.checkIn.completedDays,
            nextCheckInReward: dto.checkIn.nextRewardCoins.map(int),
            checkInDays: dto.checkIn.days.map {
                CheckInDay(
                    dayNumber: $0.stepNumber,
                    rewardCoins: int($0.rewardCoins),
                    completed: $0.completed,
                    current: $0.current
                )
            },
            adPlacementCode: dto.adRewards.placementCode,
            completedAdCount: dto.adRewards.completedCount,
            maxAdCount: dto.adRewards.maxPerDay,
            nextAdReward: dto.adRewards.nextRewardCoins.map(int),
            adSteps: dto.adRewards.steps.map {
                AdRewardStep(
                    stepNumber: $0.stepNumber,
                    rewardCoins: int($0.rewardCoins),
                    completed: $0.completed,
                    current: $0.current
                )
            },
            tasks: dto.tasks.map {
                MarketingRewardTask(
                    code: $0.code,
                    title: $0.title,
                    description: $0.description,
                    currentValue: $0.currentValue,
                    targetValue: $0.targetValue,
                    rewardCoins: int($0.rewardCoins),
                    resetCycle: $0.resetCycle,
                    completed: $0.completed,
                    action: $0.action
                )
            },
            referral: ReferralRewardState(
                inviteCode: dto.referral.inviteCode,
                inviterRewardCoins: dto.referral.inviterRewardCoins,
                inviteeRewardCoins: dto.referral.inviteeRewardCoins,
                qualifiedFriends: dto.referral.qualifiedFriends,
                weeklyRemaining: dto.referral.weeklyRemaining,
                lifetimeRemaining: dto.referral.lifetimeRemaining,
                codeApplied: dto.referral.codeApplied,
                appliedCode: dto.referral.appliedCode,
                appliedStatus: dto.referral.appliedStatus
            )
        )
    }

    private static func int(_ value: Decimal) -> Int {
        Int(truncating: value as NSNumber)
    }
}
