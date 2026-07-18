import Foundation

struct RewardCenterResponseDTO: Decodable {
    let coinBalance: Decimal
    let firstCoinPurchaseBonusAvailable: Bool
    let checkIn: CheckInStatusDTO
    let adRewards: AdRewardStatusDTO
}

struct CheckInStatusDTO: Decodable {
    let claimedToday: Bool
    let completedDays: Int
    let nextDayNumber: Int?
    let nextRewardCoins: Decimal?
    let days: [RewardStepDTO]
}

struct AdRewardStatusDTO: Decodable {
    let placementCode: String
    let completedCount: Int
    let maxPerDay: Int
    let remainingCount: Int
    let nextRewardCoins: Decimal?
    let steps: [RewardStepDTO]
}

struct RewardStepDTO: Decodable {
    let stepNumber: Int
    let rewardCoins: Decimal
    let completed: Bool
    let current: Bool
}
