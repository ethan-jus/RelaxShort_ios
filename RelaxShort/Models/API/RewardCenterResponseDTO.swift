import Foundation

struct RewardCenterResponseDTO: Decodable {
    let coinBalance: Decimal
    let firstCoinPurchaseBonusAvailable: Bool
    let remainingEarnableCoins: Decimal
    let checkIn: CheckInStatusDTO
    let adRewards: AdRewardStatusDTO
    let tasks: [MarketingTaskDTO]
    let referral: ReferralStatusDTO
}

struct MarketingTaskDTO: Decodable {
    let code: String
    let title: String
    let description: String
    let currentValue: Int
    let targetValue: Int
    let rewardCoins: Decimal
    let resetCycle: String
    let completed: Bool
    let action: String
}

struct ReferralStatusDTO: Decodable {
    let inviteCode: String
    let inviterRewardCoins: Int
    let inviteeRewardCoins: Int
    let qualifiedFriends: Int
    let weeklyRemaining: Int
    let lifetimeRemaining: Int
    let codeApplied: Bool
    let appliedCode: String?
    let appliedStatus: String?
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
