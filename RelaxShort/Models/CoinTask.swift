import Foundation

// MARK: - 奖励中心模型

struct CheckInDay: Identifiable {
    let dayNumber: Int
    let rewardCoins: Int
    let completed: Bool
    let current: Bool

    var id: Int { dayNumber }
}

struct AdRewardStep: Identifiable {
    let stepNumber: Int
    let rewardCoins: Int
    let completed: Bool
    let current: Bool

    var id: Int { stepNumber }
}

struct RewardCenterState {
    let coinBalance: Int
    let firstCoinPurchaseBonusAvailable: Bool
    let claimedCheckInToday: Bool
    let completedCheckInDays: Int
    let nextCheckInReward: Int?
    let checkInDays: [CheckInDay]
    let adPlacementCode: String
    let completedAdCount: Int
    let maxAdCount: Int
    let nextAdReward: Int?
    let adSteps: [AdRewardStep]
}
