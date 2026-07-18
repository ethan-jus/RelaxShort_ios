import SwiftUI
import Combine

// MARK: - 赚金币 / 福利中心 ViewModel
@MainActor
final class CoinRewardViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var checkInDays: [CheckInDay] = []
    @Published var coinBalance: Int = 0
    @Published var tasks: [CoinTask] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Ad Watch State

    /// 今日已观看激励广告次数
    @Published var dailyAdWatchCount: Int = 0
    /// 每日最大激励广告次数
    @Published var maxDailyAdWatchCount: Int = 0
    /// 每次观看广告获得的金币
    @Published var adWatchCoinReward: Int = 0

    // MARK: - Dependencies

    private let repository: CoinRewardRepositoryProtocol
    private let adService: any AdServiceProtocol
    private let adConfigRepository: AdConfigRepositoryProtocol
    private let adRewardRepository: AdRewardRepositoryProtocol
    private let detailRepository: DetailRepositoryProtocol

    // MARK: - Init

    init(
        repository: CoinRewardRepositoryProtocol,
        adService: (any AdServiceProtocol)? = nil,
        adConfigRepository: AdConfigRepositoryProtocol = RealAdConfigRepository(),
        adRewardRepository: AdRewardRepositoryProtocol = RealAdRewardRepository(),
        detailRepository: DetailRepositoryProtocol? = nil
    ) {
        self.repository = repository
        self.adService = adService ?? RealAdService.shared
        self.adConfigRepository = adConfigRepository
        self.adRewardRepository = adRewardRepository
        self.detailRepository = detailRepository ?? RealDetailRepository()
        Task { await loadData() }
    }

    // MARK: - Computed

    var checkedInCount: Int {
        checkInDays.filter(\.checked).count
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            checkInDays = try await repository.fetchCheckInDays()
        } catch {
            logError("CoinRewardViewModel.fetchCheckInDays failed: \(error)")
        }

        do {
            coinBalance = try await repository.fetchCoinBalance()
        } catch {
            logError("CoinRewardViewModel.fetchCoinBalance failed: \(error)")
        }

        do {
            tasks = try await repository.fetchTasks()
        } catch {
            logError("CoinRewardViewModel.fetchTasks failed: \(error)")
        }

        do {
            let config = try await adConfigRepository.fetchAdsConfig()
            let placement = config.rewardedEarnCoins
            adWatchCoinReward = placement.rewardCoins
            maxDailyAdWatchCount = config.adsEnabled && placement.enabled
                && placement.format == .rewarded
                ? placement.maxPerUserPerDay
                : 0
        } catch {
            logError("CoinRewardViewModel.fetchAdsConfig failed: \(error)")
        }
    }

    // MARK: - Actions

    func performCheckIn() {
        if let nextIndex = checkInDays.firstIndex(where: { !$0.checked }) {
            checkInDays[nextIndex].checked = true
            coinBalance += 30
        }
    }

    func performTask(_ task: CoinTask) {
        // TODO: Phase 2 对接真实 API
    }

    /// 观看激励广告获得金币
    func watchAdForCoins() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let config = try await adConfigRepository.fetchAdsConfig()
            let placement = config.rewardedEarnCoins
            maxDailyAdWatchCount = placement.maxPerUserPerDay
            adWatchCoinReward = placement.rewardCoins
            guard config.adsEnabled,
                  placement.enabled,
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
                if case .failed = result {
                    errorMessage = "广告加载失败，请稍后重试"
                }
                return
            }

            guard try await waitForDelivery(of: session) else {
                throw APIError(code: "AD_REWARD_PENDING", message: "奖励确认中，请稍后刷新")
            }
            let account = try await detailRepository.fetchUnlockAccount()
            coinBalance = account.balance
            dailyAdWatchCount += 1
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "广告暂不可用，请检查网络后重试"
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

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
