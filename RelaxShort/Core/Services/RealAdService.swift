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
    private var lastAppOpenPresentationTime: Date?
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
        let now = Date()
        let bgDuration = now.timeIntervalSince(lastBg)
        let presentationInterval = lastAppOpenPresentationTime.map {
            now.timeIntervalSince($0)
        } ?? .infinity
        let presentationIntervalDescription = presentationInterval.isFinite
            ? "\(Int(presentationInterval))s"
            : "无"
        let should = bgDuration >= AdConfig.hotStartAdInterval
            && presentationInterval >= AdConfig.minimumAppOpenPresentationInterval
        print(
            "🦐 [AdService] 后台时长: \(Int(bgDuration))s, "
                + "距上次开屏: \(presentationIntervalDescription), "
                + "展示: \(should)"
        )
        return should
    }

    /// App Open 只应从应用根页面拉起；已有二级页、系统弹窗、登录、支付或其他全屏广告时跳过。
    var canPresentAppOpenAdFromRoot: Bool {
        guard rewardedPresentation == nil,
              !isShowingAppOpenAd,
              let rootViewController = appRootViewController() else {
            return false
        }
        return rootViewController.presentedViewController == nil
            && !hasPushedNavigation(in: rootViewController)
    }

    func prepareAds() async {
        guard isSDKReady, PrivacyConsentManager.shared.isAdRequestAllowed else { return }
        do {
            let config = try await adConfigRepository.fetchAdsConfig()
            cachedConfig = config
            guard config.adsEnabled else {
                print("🦐 [AdService] 全局广告开关已关闭")
                return
            }

            // 冷启动先争取开屏广告；激励广告随后并行预热，
            // 避免三个全屏广告请求同时竞争 SDK 首次网络。
            let appOpenLoaded = await loadAppOpenAd(using: config.appOpen)
            print("🦐 [AdService] 开屏广告预加载结果: \(appOpenLoaded)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                async let rewarded: Bool = self.preloadRewardedAd(
                    placement: config.rewardedEarnCoins
                )
                async let rewardedInterstitial: Bool = self.preloadRewardedAd(
                    placement: config.interstitialUnlockEpisode
                )
                _ = await (rewarded, rewardedInterstitial)
            }
        } catch {
            print("🦐 [AdService] 广告配置加载失败: \(error.localizedDescription)")
        }
    }

    func loadAppOpenAd() async -> Bool {
        guard isSDKReady, PrivacyConsentManager.shared.isAdRequestAllowed else { return false }
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
        guard PrivacyConsentManager.shared.isAdRequestAllowed,
              rewardedPresentation == nil,
              !isShowingAppOpenAd,
              let ad = validAppOpenAd else {
            print("🦐 [AdService] 广告未就绪")
            onDismiss()
            Task { await loadAppOpenAd() }
            return
        }

        appOpenAdOnDismiss = onDismiss

        guard canPresentAppOpenAdFromRoot,
              let rootVC = appRootViewController() else {
            onDismiss()
            appOpenAdOnDismiss = nil
            return
        }

        isShowingAppOpenAd = true
        lastAppOpenPresentationTime = Date()
        appOpenAd = nil
        isAppOpenAdReady = false
        ad.present(from: rootVC)
    }

    @discardableResult
    func preloadRewardedAd(placement: AdPlacementConfig) async -> Bool {
        guard PrivacyConsentManager.shared.isAdRequestAllowed else {
            print("🦐 [AdService] 跳过激励广告预加载：UMP 未允许广告请求")
            return false
        }
        guard await waitForSDKReady() else {
            print("🦐 [AdService] 跳过激励广告预加载：SDK 初始化超时")
            return false
        }
        guard placement.enabled, !placement.adUnitID.isEmpty else {
            print("🦐 [AdService] 跳过激励广告预加载：广告位关闭或 unitID 为空")
            return false
        }
        switch placement.format {
        case .rewarded:
            return await ensureRewardedAd(for: placement.adUnitID) != nil
        case .rewardedInterstitial:
            return await ensureRewardedInterstitialAd(for: placement.adUnitID) != nil
        default:
            return false
        }
    }

    func showRewardedAd(
        placement: AdPlacementConfig,
        ssvCustomData: String
    ) async -> AdRewardResult {
        guard PrivacyConsentManager.shared.isAdRequestAllowed else {
            print("🦐 [AdService] 激励广告不可用：UMP 未允许广告请求")
            return .failed
        }
        guard await waitForSDKReady() else {
            print("🦐 [AdService] 激励广告不可用：SDK 初始化超时")
            return .failed
        }
        guard placement.enabled,
              !placement.adUnitID.isEmpty,
              [.rewarded, .rewardedInterstitial].contains(placement.format) else {
            print("🦐 [AdService] 激励广告不可用：广告位配置无效 format=\(placement.format.rawValue) unitIDEmpty=\(placement.adUnitID.isEmpty)")
            return .failed
        }
        guard !isShowingAppOpenAd, rewardedPresentation == nil else {
            print("🦐 [AdService] 激励广告不可用：已有全屏广告正在展示")
            return .failed
        }
        guard let viewController = topViewController() else {
            print("🦐 [AdService] 激励广告不可用：找不到展示页面")
            return .failed
        }

        do {
            switch placement.format {
            case .rewarded:
                guard let ad = await takeRewardedAd(for: placement.adUnitID) else {
                    print("🦐 [AdService] 激励广告展示中止：两次加载均失败")
                    return .failed
                }
                configureSSV(on: ad, customData: ssvCustomData)
                let result = await present(
                    ad: ad,
                    from: viewController,
                    rewardCoins: placement.rewardCoins
                )
                Task { _ = await preloadRewardedAd(placement: placement) }
                return result
            case .rewardedInterstitial:
                guard let ad = await takeRewardedInterstitialAd(for: placement.adUnitID) else {
                    print("🦐 [AdService] 解锁激励插屏展示中止：两次加载均失败")
                    return .failed
                }
                configureSSV(on: ad, customData: ssvCustomData)
                let result = await present(
                    ad: ad,
                    from: viewController,
                    rewardCoins: placement.rewardCoins
                )
                Task { _ = await preloadRewardedAd(placement: placement) }
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

    /// UMP 允许后 Mobile Ads 初始化通常很快；点击时最多等待 2 秒，
    /// 避免启动竞态被立即误报成“广告加载失败”。
    private func waitForSDKReady() async -> Bool {
        if isSDKReady { return true }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if isSDKReady { return true }
        }
        return false
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

    private func appRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    private func hasPushedNavigation(in viewController: UIViewController) -> Bool {
        if let navigationController = viewController as? UINavigationController,
           navigationController.viewControllers.count > 1 {
            return true
        }
        return viewController.children.contains {
            hasPushedNavigation(in: $0)
        }
    }

    private func resolvedConfig() async throws -> AdsConfig {
        if let cachedConfig { return cachedConfig }
        let config = try await adConfigRepository.fetchAdsConfig()
        cachedConfig = config
        return config
    }

    private func loadAppOpenAd(using placement: AdPlacementConfig) async -> Bool {
        guard isSDKReady,
              PrivacyConsentManager.shared.isAdRequestAllowed,
              placement.enabled,
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
            defer { self?.rewardedAdLoadTask = nil }
            for attempt in 1...2 {
                do {
                    let ad = try await RewardedAd.load(
                        with: unitID,
                        request: Request()
                    )
                    self?.rewardedAd = ad
                    self?.rewardedAdUnitID = unitID
                    self?.rewardedAdLoadTime = Date()
                    print("🦐 [AdService] ✅ 奖励页激励视频预加载成功 attempt=\(attempt)")
                    return ad
                } catch {
                    let nsError = error as NSError
                    print("🦐 [AdService] ❌ 激励视频加载失败 attempt=\(attempt) domain=\(nsError.domain) code=\(nsError.code) message=\(error.localizedDescription)")
                    if attempt == 1 {
                        try? await Task.sleep(for: .milliseconds(400))
                    }
                }
            }
            return nil
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
            defer { self?.rewardedInterstitialLoadTask = nil }
            for attempt in 1...2 {
                do {
                    let ad = try await RewardedInterstitialAd.load(
                        with: unitID,
                        request: Request()
                    )
                    self?.rewardedInterstitialAd = ad
                    self?.rewardedInterstitialAdUnitID = unitID
                    self?.rewardedInterstitialAdLoadTime = Date()
                    print("🦐 [AdService] ✅ 解锁激励插屏预加载成功 attempt=\(attempt)")
                    return ad
                } catch {
                    let nsError = error as NSError
                    print("🦐 [AdService] ❌ 激励插屏加载失败 attempt=\(attempt) domain=\(nsError.domain) code=\(nsError.code) message=\(error.localizedDescription)")
                    if attempt == 1 {
                        try? await Task.sleep(for: .milliseconds(400))
                    }
                }
            }
            return nil
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
        let nsError = error as NSError
        print("🦐 [AdService] 激励广告展示失败 domain=\(nsError.domain) code=\(nsError.code) message=\(error.localizedDescription)")
        finish(.failed)
    }

    private func finish(_ result: AdRewardResult) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
        onFinish()
    }
}
