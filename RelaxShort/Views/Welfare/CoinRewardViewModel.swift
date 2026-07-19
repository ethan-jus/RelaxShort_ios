import SwiftUI
import Combine

// MARK: - 赚金币 / 福利中心 ViewModel
@MainActor
final class CoinRewardViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var checkInDays: [CheckInDay] = []
    @Published var coinBalance: Int = 0
    @Published var firstCoinPurchaseBonusAvailable = false
    @Published var adRewardSteps: [AdRewardStep] = []
    @Published var claimedCheckInToday = false
    @Published var nextCheckInReward: Int?
    @Published var remainingEarnableCoins = 0
    @Published var marketingTasks: [MarketingRewardTask] = []
    @Published var referral = ReferralRewardState(
        inviteCode: "",
        inviterRewardCoins: 200,
        inviteeRewardCoins: 100,
        qualifiedFriends: 0,
        weeklyRemaining: 3,
        lifetimeRemaining: 20,
        codeApplied: false,
        appliedCode: nil,
        appliedStatus: nil
    )
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Ad Watch State

    /// 今日已观看激励广告次数
    @Published var dailyAdWatchCount: Int = 0
    /// 每日最大激励广告次数
    @Published var maxDailyAdWatchCount: Int = 0
    /// 下一次观看广告获得的金币
    @Published var adWatchCoinReward: Int = 0

    // MARK: - Dependencies

    private let repository: CoinRewardRepositoryProtocol
    private let adService: any AdServiceProtocol
    private let adConfigRepository: AdConfigRepositoryProtocol
    private let adRewardRepository: AdRewardRepositoryProtocol
    private var rewardedCoinPlacement: AdPlacementConfig?

    // MARK: - Init

    init(
        repository: CoinRewardRepositoryProtocol,
        adService: (any AdServiceProtocol)? = nil,
        adConfigRepository: AdConfigRepositoryProtocol = RealAdConfigRepository(),
        adRewardRepository: AdRewardRepositoryProtocol = RealAdRewardRepository()
    ) {
        self.repository = repository
        self.adService = adService ?? RealAdService.shared
        self.adConfigRepository = adConfigRepository
        self.adRewardRepository = adRewardRepository
        Task { await loadData() }
    }

    // MARK: - Computed

    var checkedInCount: Int {
        checkInDays.filter(\.completed).count
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            apply(try await repository.fetchRewardCenter())
        } catch {
            errorMessage = error.localizedDescription
            logError("CoinRewardViewModel.fetchRewardCenter failed: \(error)")
        }

        do {
            let config = try await adConfigRepository.fetchAdsConfig()
            let placement = config.rewardedEarnCoins
            if config.adsEnabled && placement.enabled && placement.format == .rewarded
                && remainingAdWatchCount > 0 {
                rewardedCoinPlacement = placement
                await adService.preloadRewardedAd(placement: placement)
            }
        } catch {
            logError("CoinRewardViewModel.fetchAdsConfig failed: \(error)")
        }
    }

    // MARK: - Actions

    func performCheckIn() async {
        guard !isLoading, !claimedCheckInToday else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            apply(try await repository.checkIn())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 观看激励广告获得金币
    func watchAdForCoins() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let placement = try await resolvedRewardedCoinPlacement()
            guard placement.enabled,
                  placement.format == .rewarded,
                  remainingAdWatchCount > 0 else {
                throw APIError(code: "ADS_NOT_AVAILABLE", message: "激励广告暂不可用")
            }

            let session = try await adRewardRepository.startSession(
                placementCode: placement.placementCode,
                rewardType: "coins",
                targetEpisodeID: nil
            )
            guard session.placement.format == .rewarded else {
                throw APIError(code: "AD_FORMAT_MISMATCH", message: "广告配置不一致，请稍后重试")
            }

            let result = await adService.showRewardedAd(
                placement: session.placement,
                ssvCustomData: session.ssvCustomData
            )
            guard case .rewarded = result else {
                await adRewardRepository.cancelSession(session)
                if case .failed = result {
                    errorMessage = "广告加载失败，请稍后重试"
                }
                return
            }

            guard try await waitForDelivery(of: session) else {
                throw APIError(code: "AD_REWARD_PENDING", message: "奖励确认中，请稍后刷新")
            }
            apply(try await repository.fetchRewardCenter())
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "广告暂不可用，请检查网络后重试"
        }
    }

    func applyInviteCode(_ code: String) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            apply(try await repository.applyInviteCode(code))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 剩余可观看广告次数
    var remainingAdWatchCount: Int {
        max(0, self.maxDailyAdWatchCount - self.dailyAdWatchCount)
    }

    // MARK: - Private

    private func waitForDelivery(of session: AdRewardSession) async throws -> Bool {
        for attempt in 0..<12 {
            let completion = try await adRewardRepository.completeSession(session)
            if completion.isDelivered {
                return true
            }
            if attempt < 11 {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        return false
    }

    private func resolvedRewardedCoinPlacement() async throws -> AdPlacementConfig {
        if let rewardedCoinPlacement { return rewardedCoinPlacement }
        let config = try await adConfigRepository.fetchAdsConfig()
        let placement = config.rewardedEarnCoins
        guard config.adsEnabled,
              placement.enabled,
              placement.format == .rewarded else {
            throw APIError(code: "ADS_NOT_AVAILABLE", message: "激励广告暂不可用")
        }
        rewardedCoinPlacement = placement
        await adService.preloadRewardedAd(placement: placement)
        return placement
    }

    private func apply(_ state: RewardCenterState) {
        coinBalance = state.coinBalance
        firstCoinPurchaseBonusAvailable = state.firstCoinPurchaseBonusAvailable
        remainingEarnableCoins = state.remainingEarnableCoins
        marketingTasks = state.tasks
        referral = state.referral
        checkInDays = state.checkInDays
        claimedCheckInToday = state.claimedCheckInToday
        nextCheckInReward = state.nextCheckInReward
        adRewardSteps = state.adSteps
        dailyAdWatchCount = state.completedAdCount
        maxDailyAdWatchCount = state.maxAdCount
        adWatchCoinReward = state.nextAdReward ?? 0
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
