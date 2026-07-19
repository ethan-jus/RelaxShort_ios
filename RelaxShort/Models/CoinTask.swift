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

struct MarketingRewardTask: Identifiable {
    let code: String
    let title: String
    let description: String
    let currentValue: Int
    let targetValue: Int
    let rewardCoins: Int
    let resetCycle: String
    let completed: Bool
    let action: String

    var id: String { code }
}

struct ReferralRewardState {
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

struct RewardCenterState {
    let coinBalance: Int
    let firstCoinPurchaseBonusAvailable: Bool
    let remainingEarnableCoins: Int
    let claimedCheckInToday: Bool
    let completedCheckInDays: Int
    let nextCheckInReward: Int?
    let checkInDays: [CheckInDay]
    let adPlacementCode: String
    let completedAdCount: Int
    let maxAdCount: Int
    let nextAdReward: Int?
    let adSteps: [AdRewardStep]
    let tasks: [MarketingRewardTask]
    let referral: ReferralRewardState
}

@MainActor
final class RewardSummaryStore: ObservableObject {
    @Published private(set) var remainingEarnableCoins = 0
    @Published private(set) var coinBalance = 0
    private let repository: CoinRewardRepositoryProtocol

    init(repository: CoinRewardRepositoryProtocol = RealCoinRewardRepository()) {
        self.repository = repository
    }

    func refresh() async {
        do {
            apply(try await repository.fetchRewardCenter())
        } catch {
            Logger.viewModel.warning("RewardSummaryStore refresh failed: \(error.localizedDescription)")
        }
    }

    func apply(_ state: RewardCenterState) {
        remainingEarnableCoins = state.remainingEarnableCoins
        coinBalance = state.coinBalance
    }

    func apply(balance: Int, remainingEarnableCoins: Int) {
        self.coinBalance = balance
        self.remainingEarnableCoins = remainingEarnableCoins
    }
}
