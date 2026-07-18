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

    private static func map(_ dto: RewardCenterResponseDTO) -> RewardCenterState {
        RewardCenterState(
            coinBalance: int(dto.coinBalance),
            firstCoinPurchaseBonusAvailable: dto.firstCoinPurchaseBonusAvailable,
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
            }
        )
    }

    private static func int(_ value: Decimal) -> Int {
        Int(truncating: value as NSNumber)
    }
}
