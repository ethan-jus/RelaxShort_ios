import GoogleMobileAds
import SwiftUI

@MainActor
final class RealAdService: NSObject, ObservableObject, AdServiceProtocol {
    static let shared = RealAdService()

    private var appOpenAd: AppOpenAd?
    private var appOpenLoadTime: Date?
    private var appOpenLoadTask: Task<AppOpenAd?, Never>?
    private var appOpenAdOnDismiss: (() -> Void)?
    private var lastBackgroundTime: Date?
    private var rewardedAd: RewardedAd?
    private var rewardedAdUnitID: String?
    private var rewardedAdLoadTime: Date?
    private var rewardedAdLoadTask: Task<RewardedAd?, Never>?
    private var rewardedInterstitialAd: RewardedInterstitialAd?
    private var rewardedInterstitialAdUnitID: String?
    private var rewardedInterstitialAdLoadTime: Date?
    private var rewardedInterstitialLoadTask: Task<RewardedInterstitialAd?, Never>?
    private var rewardedPresentation: RewardedPresentationDelegate?
    private var cachedConfig: AdsConfig?
    private var isShowingAppOpenAd = false
    private let adConfigRepository: AdConfigRepositoryProtocol = RealAdConfigRepository()
    @Published var isSDKReady = false
    @Published var isAppOpenAdReady = false
    private(set) var wasInBackground = false

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        lastBackgroundTime = Date()
        wasInBackground = true
        print("🦐 [AdService] App 进入后台")
    }

    /// 每次前台恢复只消费一次机会；短时间切回不展示。
    func consumeBackgroundAppOpenOpportunity() -> Bool {
        guard wasInBackground, let lastBg = lastBackgroundTime else { return false }
        wasInBackground = false
        let bgDuration = Date().timeIntervalSince(lastBg)
        let should = bgDuration >= AdConfig.hotStartAdInterval
        print("🦐 [AdService] 后台时长: \(Int(bgDuration))s, 阈值: \(Int(AdConfig.hotStartAdInterval))s, 展示: \(should)")
        return should
    }

    func prepareAds() async {
        guard isSDKReady else { return }
        do {
            let config = try await adConfigRepository.fetchAdsConfig()
            cachedConfig = config
            guard config.adsEnabled else {
                print("🦐 [AdService] 全局广告开关已关闭")
                return
            }

            // 冷启动的关键路径只抢占开屏广告。激励广告随后并行预热，
            // 避免三个全屏广告请求同时竞争首次网络与 SDK 初始化资源。
            let appOpenLoaded = await loadAppOpenAd(using: config.appOpen)
            print("🦐 [AdService] 冷启动开屏广告准备结果: \(appOpenLoaded)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                async let rewarded: Void = self.preloadRewardedAd(
                    placement: config.rewardedEarnCoins
                )
                async let rewardedInterstitial: Void = self.preloadRewardedAd(
                    placement: config.interstitialUnlockEpisode
                )
                _ = await (rewarded, rewardedInterstitial)
            }
        } catch {
            print("🦐 [AdService] 广告配置加载失败: \(error.localizedDescription)")
        }
    }

    func loadAppOpenAd() async -> Bool {
        do {
            let config = try await resolvedConfig()
            let placement = config.appOpen
            guard config.adsEnabled else { return false }
            return await loadAppOpenAd(using: placement)
        } catch {
            print("🦐 [AdService] 开屏广告配置加载失败: \(error.localizedDescription)")
            return false
        }
    }

    func showAppOpenAd(onDismiss: @escaping () -> Void) {
        guard rewardedPresentation == nil,
              !isShowingAppOpenAd,
              let ad = validAppOpenAd else {
            print("🦐 [AdService] 广告未就绪")
            onDismiss()
            Task { await loadAppOpenAd() }
            return
        }

        appOpenAdOnDismiss = onDismiss

        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let rootVC = keyWindow.rootViewController else {
            onDismiss()
            appOpenAdOnDismiss = nil
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        isShowingAppOpenAd = true
        appOpenAd = nil
        isAppOpenAdReady = false
        ad.present(from: topVC)
    }

    func preloadRewardedAd(placement: AdPlacementConfig) async {
        guard isSDKReady,
              placement.enabled,
              !placement.adUnitID.isEmpty else { return }
        switch placement.format {
        case .rewarded:
            _ = await ensureRewardedAd(for: placement.adUnitID)
        case .rewardedInterstitial:
            _ = await ensureRewardedInterstitialAd(for: placement.adUnitID)
        default:
            return
        }
    }

    func showRewardedAd(
        placement: AdPlacementConfig,
        ssvCustomData: String
    ) async -> AdRewardResult {
        guard placement.enabled,
              !placement.adUnitID.isEmpty,
              [.rewarded, .rewardedInterstitial].contains(placement.format),
              !isShowingAppOpenAd,
              rewardedPresentation == nil,
              let viewController = topViewController() else {
            return .failed
        }

        do {
            switch placement.format {
            case .rewarded:
                guard let ad = await takeRewardedAd(for: placement.adUnitID) else {
                    return .failed
                }
                configureSSV(on: ad, customData: ssvCustomData)
                let result = await present(
                    ad: ad,
                    from: viewController,
                    rewardCoins: placement.rewardCoins
                )
                Task { await preloadRewardedAd(placement: placement) }
                return result
            case .rewardedInterstitial:
                guard let ad = await takeRewardedInterstitialAd(for: placement.adUnitID) else {
                    return .failed
                }
                configureSSV(on: ad, customData: ssvCustomData)
                let result = await present(
                    ad: ad,
                    from: viewController,
                    rewardCoins: placement.rewardCoins
                )
                Task { await preloadRewardedAd(placement: placement) }
                return result
            default:
                return .failed
            }
        }
    }

    func showInterstitial() async -> Bool { true }

    private func configureSSV(
        on ad: RewardedAd,
        customData: String
    ) {
        let options = ServerSideVerificationOptions()
        options.customRewardText = customData
        ad.serverSideVerificationOptions = options
    }

    private func configureSSV(
        on ad: RewardedInterstitialAd,
        customData: String
    ) {
        let options = ServerSideVerificationOptions()
        options.customRewardText = customData
        ad.serverSideVerificationOptions = options
    }

    private func present(
        ad: RewardedAd,
        from viewController: UIViewController,
        rewardCoins: Int
    ) async -> AdRewardResult {
        await withCheckedContinuation { continuation in
            let delegate = RewardedPresentationDelegate(
                rewardCoins: rewardCoins,
                continuation: continuation,
                onFinish: { [weak self] in self?.rewardedPresentation = nil }
            )
            rewardedPresentation = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(from: viewController) {
                delegate.didEarnReward()
            }
        }
    }

    private func present(
        ad: RewardedInterstitialAd,
        from viewController: UIViewController,
        rewardCoins: Int
    ) async -> AdRewardResult {
        await withCheckedContinuation { continuation in
            let delegate = RewardedPresentationDelegate(
                rewardCoins: rewardCoins,
                continuation: continuation,
                onFinish: { [weak self] in self?.rewardedPresentation = nil }
            )
            rewardedPresentation = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(from: viewController) {
                delegate.didEarnReward()
            }
        }
    }

    private func topViewController() -> UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private var validAppOpenAd: AppOpenAd? {
        guard let appOpenAd,
              let appOpenLoadTime,
              Date().timeIntervalSince(appOpenLoadTime) < AdConfig.adExpiryInterval else {
            self.appOpenAd = nil
            isAppOpenAdReady = false
            return nil
        }
        return appOpenAd
    }

    private func resolvedConfig() async throws -> AdsConfig {
        if let cachedConfig { return cachedConfig }
        let config = try await adConfigRepository.fetchAdsConfig()
        cachedConfig = config
        return config
    }

    private func loadAppOpenAd(using placement: AdPlacementConfig) async -> Bool {
        guard placement.enabled,
              placement.format == .appOpen,
              !placement.adUnitID.isEmpty else {
            print("🦐 [AdService] 开屏广告位已关闭或配置无效")
            return false
        }
        if validAppOpenAd != nil { return true }
        if let appOpenLoadTask {
            return await appOpenLoadTask.value != nil
        }

        let unitID = placement.adUnitID
        print("🦐 [AdService] 开始预加载开屏广告，unitID: \(unitID)")
        let task = Task { @MainActor [weak self] () -> AppOpenAd? in
            do {
                let ad = try await AppOpenAd.load(
                    with: unitID,
                    request: Request()
                )
                ad.fullScreenContentDelegate = self
                self?.appOpenAd = ad
                self?.appOpenLoadTime = Date()
                self?.isAppOpenAdReady = true
                self?.appOpenLoadTask = nil
                print("🦐 [AdService] ✅ 开屏广告预加载成功")
                return ad
            } catch {
                self?.appOpenLoadTask = nil
                print("🦐 [AdService] ❌ 开屏广告预加载失败: \(error.localizedDescription)")
                return nil
            }
        }
        appOpenLoadTask = task
        return await task.value != nil
    }

    private func ensureRewardedAd(for unitID: String) async -> RewardedAd? {
        if rewardedAdUnitID == unitID,
           let rewardedAd,
           let rewardedAdLoadTime,
           Date().timeIntervalSince(rewardedAdLoadTime) < AdConfig.rewardedAdExpiryInterval {
            return rewardedAd
        }
        rewardedAd = nil
        if let rewardedAdLoadTask {
            return await rewardedAdLoadTask.value
        }
        let task = Task { @MainActor [weak self] () -> RewardedAd? in
            do {
                let ad = try await RewardedAd.load(
                    with: unitID,
                    request: Request()
                )
                self?.rewardedAd = ad
                self?.rewardedAdUnitID = unitID
                self?.rewardedAdLoadTime = Date()
                self?.rewardedAdLoadTask = nil
                print("🦐 [AdService] ✅ 奖励页激励视频预加载成功")
                return ad
            } catch {
                self?.rewardedAdLoadTask = nil
                print("🦐 [AdService] ❌ 激励视频预加载失败: \(error.localizedDescription)")
                return nil
            }
        }
        rewardedAdLoadTask = task
        return await task.value
    }

    private func ensureRewardedInterstitialAd(
        for unitID: String
    ) async -> RewardedInterstitialAd? {
        if rewardedInterstitialAdUnitID == unitID,
           let rewardedInterstitialAd,
           let rewardedInterstitialAdLoadTime,
           Date().timeIntervalSince(rewardedInterstitialAdLoadTime) < AdConfig.rewardedAdExpiryInterval {
            return rewardedInterstitialAd
        }
        rewardedInterstitialAd = nil
        if let rewardedInterstitialLoadTask {
            return await rewardedInterstitialLoadTask.value
        }
        let task = Task { @MainActor [weak self] () -> RewardedInterstitialAd? in
            do {
                let ad = try await RewardedInterstitialAd.load(
                    with: unitID,
                    request: Request()
                )
                self?.rewardedInterstitialAd = ad
                self?.rewardedInterstitialAdUnitID = unitID
                self?.rewardedInterstitialAdLoadTime = Date()
                self?.rewardedInterstitialLoadTask = nil
                print("🦐 [AdService] ✅ 解锁激励插屏预加载成功")
                return ad
            } catch {
                self?.rewardedInterstitialLoadTask = nil
                print("🦐 [AdService] ❌ 激励插屏预加载失败: \(error.localizedDescription)")
                return nil
            }
        }
        rewardedInterstitialLoadTask = task
        return await task.value
    }

    private func takeRewardedAd(for unitID: String) async -> RewardedAd? {
        guard let ad = await ensureRewardedAd(for: unitID) else { return nil }
        rewardedAd = nil
        rewardedAdLoadTime = nil
        return ad
    }

    private func takeRewardedInterstitialAd(
        for unitID: String
    ) async -> RewardedInterstitialAd? {
        guard let ad = await ensureRewardedInterstitialAd(for: unitID) else { return nil }
        rewardedInterstitialAd = nil
        rewardedInterstitialAdLoadTime = nil
        return ad
    }
}

extension RealAdService: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("🦐 [AdService] 广告关闭")
        isShowingAppOpenAd = false
        appOpenAdOnDismiss?()
        appOpenAdOnDismiss = nil
        Task { await loadAppOpenAd() }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("🦐 [AdService] 广告展示失败: \(error.localizedDescription)")
        isShowingAppOpenAd = false
        appOpenAdOnDismiss?()
        appOpenAdOnDismiss = nil
        Task { await loadAppOpenAd() }
    }
}

@MainActor
private final class RewardedPresentationDelegate: NSObject, FullScreenContentDelegate {
    private let rewardCoins: Int
    private var continuation: CheckedContinuation<AdRewardResult, Never>?
    private let onFinish: () -> Void
    private var earnedReward = false

    init(
        rewardCoins: Int,
        continuation: CheckedContinuation<AdRewardResult, Never>,
        onFinish: @escaping () -> Void
    ) {
        self.rewardCoins = rewardCoins
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func didEarnReward() {
        earnedReward = true
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish(earnedReward ? .rewarded(coins: rewardCoins) : .cancelled)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        finish(.failed)
    }

    private func finish(_ result: AdRewardResult) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
        onFinish()
    }
}
