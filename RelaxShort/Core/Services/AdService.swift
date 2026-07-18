import Foundation
import Combine

// MARK: - Ad Reward Result

/// 激励广告观看结果
enum AdRewardResult {
    /// 成功观看完整广告，用户获得奖励
    case rewarded(coins: Int)
    /// 用户中途退出
    case cancelled
    /// 广告加载失败
    case failed
}

// MARK: - Ad Service Protocol

@MainActor
protocol AdServiceProtocol {
    /// 根据服务端广告位格式展示激励视频或激励插屏。
    func showRewardedAd(
        placement: AdPlacementConfig,
        ssvCustomData: String
    ) async -> AdRewardResult
    /// 展示插屏广告
    func showInterstitial() async -> Bool
    /// 加载开屏广告
    func loadAppOpenAd() async -> Bool
}

// MARK: - Mock Ad Service (Dev Only)

/// 开发阶段模拟广告服务。
/// Phase 2 移除，统一使用 `RealAdService`。
@MainActor
final class MockAdService: ObservableObject, AdServiceProtocol {

    @Published var dailyAdWatchCount: Int = 0
    let maxDailyAdWatchCount: Int = 5
    @Published var isShowingAd: Bool = false
    @Published var adCountdown: Int = 0
    let adDuration: Int = 3

    @Published var appOpenAdShown: Bool = false

    init() {
        #if DEBUG
        Logger.store.info("MockAdService init")
        #endif
    }

    func showRewardedAd(
        placement: AdPlacementConfig,
        ssvCustomData: String
    ) async -> AdRewardResult {
        guard self.dailyAdWatchCount < self.maxDailyAdWatchCount else {
            #if DEBUG
            Logger.store.info("MockAdService: daily ad watch limit reached (\(self.dailyAdWatchCount)/\(self.maxDailyAdWatchCount))")
            #endif
            return .failed
        }
        isShowingAd = true
        defer { isShowingAd = false }
        await startCountdown(seconds: adDuration)
        dailyAdWatchCount += 1
        if Double.random(in: 0...1) < 0.9 {
            #if DEBUG
            Logger.store.info("MockAdService: rewarded ad completed, earned \(placement.rewardCoins) coins")
            #endif
            return .rewarded(coins: placement.rewardCoins)
        } else {
            #if DEBUG
            Logger.store.info("MockAdService: rewarded ad failed (random)")
            #endif
            return .failed
        }
    }

    func showInterstitial() async -> Bool {
        isShowingAd = true
        defer { isShowingAd = false }
        await startCountdown(seconds: adDuration)
        #if DEBUG
        Logger.store.info("MockAdService: interstitial ad shown")
        #endif
        return true
    }

    func loadAppOpenAd() async -> Bool {
        isShowingAd = true
        defer { isShowingAd = false; appOpenAdShown = true }
        await startCountdown(seconds: adDuration)
        #if DEBUG
        Logger.store.info("MockAdService: app open ad loaded")
        #endif
        return true
    }

    func skipAppOpenAd() {
        isShowingAd = false
        appOpenAdShown = true
        #if DEBUG
        Logger.store.info("MockAdService: app open ad skipped")
        #endif
    }

    private func startCountdown(seconds: Int) async {
        adCountdown = seconds
        for _ in 0..<seconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard isShowingAd else { return }
            adCountdown -= 1
        }
    }
}
