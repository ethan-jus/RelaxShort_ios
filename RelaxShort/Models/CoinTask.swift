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
    let claimed: Bool
    let claimable: Bool
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
    private static let freshnessInterval: TimeInterval = 30

    @Published private(set) var remainingEarnableCoins = 0
    @Published private(set) var coinBalance = 0
    private let repository: CoinRewardRepositoryProtocol
    private var refreshTask: Task<RewardCenterState, Error>?
    private var lastRefreshAt: Date?

    init(repository: CoinRewardRepositoryProtocol = RealCoinRewardRepository()) {
        self.repository = repository
    }

    func refresh(force: Bool = false) async {
        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < Self.freshnessInterval {
            return
        }

        let task: Task<RewardCenterState, Error>
        if let refreshTask {
            task = refreshTask
        } else {
            let newTask = Task { try await repository.fetchRewardCenter() }
            refreshTask = newTask
            task = newTask
        }

        do {
            apply(try await task.value)
        } catch {
            Logger.viewModel.warning("RewardSummaryStore refresh failed: \(error.localizedDescription)")
        }
        refreshTask = nil
    }

    func apply(_ state: RewardCenterState) {
        remainingEarnableCoins = state.remainingEarnableCoins
        coinBalance = state.coinBalance
        lastRefreshAt = Date()
    }

    func apply(balance: Int, remainingEarnableCoins: Int) {
        self.coinBalance = balance
        self.remainingEarnableCoins = remainingEarnableCoins
    }
}
