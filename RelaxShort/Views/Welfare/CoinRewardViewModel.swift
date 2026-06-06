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
    let maxDailyAdWatchCount: Int = 5
    /// 每次观看广告获得的金币
    let adWatchCoinReward: Int = 20
    /// 是否正在展示广告
    @Published var isShowingRewardedAd: Bool = false
    /// 当前广告倒计时（秒）
    @Published var adCountdown: Int = 0
    /// 广告总时长（秒）
    let adDuration: Int = 3

    // MARK: - Dependencies

    private let repository: CoinRewardRepositoryProtocol
    private let adService: any AdServiceProtocol

    // MARK: - Init

    init(
        repository: CoinRewardRepositoryProtocol,
        adService: (any AdServiceProtocol)? = nil
    ) {
        self.repository = repository
        self.adService = adService ?? RealAdService.shared
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
        guard self.dailyAdWatchCount < self.maxDailyAdWatchCount else { return }

        isShowingRewardedAd = true
        await startCountdown(seconds: adDuration)

        let result = await adService.showRewardedAd(coins: adWatchCoinReward)
        isShowingRewardedAd = false

        switch result {
        case .rewarded(let coins):
            coinBalance += coins
            self.dailyAdWatchCount += 1
            #if DEBUG
            Logger.viewModel.info("CoinRewardVM: ad watch rewarded \(coins) coins, daily count: \(self.dailyAdWatchCount)")
            #endif
        case .cancelled, .failed:
            break
        }
    }

    /// 剩余可观看广告次数
    var remainingAdWatchCount: Int {
        max(0, self.maxDailyAdWatchCount - self.dailyAdWatchCount)
    }

    // MARK: - Private

    /// 倒计时（每秒更新 adCountdown，用于 UI 展示）
    private func startCountdown(seconds: Int) async {
        adCountdown = seconds
        for _ in 0..<seconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard isShowingRewardedAd else { return }
            adCountdown -= 1
        }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
