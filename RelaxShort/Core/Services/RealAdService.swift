import GoogleMobileAds
import SwiftUI

@MainActor
final class RealAdService: NSObject, ObservableObject, AdServiceProtocol {
    static let shared = RealAdService()

    private var appOpenAd: GADAppOpenAd?
    private var appOpenLoadTime: Date?
    private var appOpenAdOnDismiss: (() -> Void)?
    private var lastBackgroundTime: Date?
    private var rewardedPresentation: RewardedPresentationDelegate?
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

    /// 判断是否应该展示开屏广告
    var shouldShowAppOpen: Bool {
        guard let lastBg = lastBackgroundTime else {
            // 冷启动 → 展示
            return true
        }
        let bgDuration = Date().timeIntervalSince(lastBg)
        let should = bgDuration >= AdConfig.hotStartAdInterval
        print("🦐 [AdService] 后台时长: \(Int(bgDuration))s, 阈值: \(Int(AdConfig.hotStartAdInterval))s, 展示: \(should)")
        return should
    }

    func loadAppOpenAd() async -> Bool {
        do {
            let config = try await adConfigRepository.fetchAdsConfig()
            let placement = config.appOpen
            guard config.adsEnabled,
                  placement.enabled,
                  placement.format == .appOpen,
                  !placement.adUnitID.isEmpty else {
                print("🦐 [AdService] 开屏广告位已关闭或配置无效")
                return false
            }
            let unitID = placement.adUnitID
            print("🦐 [AdService] 开始加载广告，unitID: \(unitID)")
            let request = GADRequest()
            let ad = try await GADAppOpenAd.load(
                withAdUnitID: unitID,
                request: request
            )
            await MainActor.run {
                appOpenAd = ad
                appOpenLoadTime = Date()
                isAppOpenAdReady = true
                ad.fullScreenContentDelegate = self
            }
            print("🦐 [AdService] ✅ 广告加载成功 responseID: \(ad.responseInfo.responseIdentifier ?? "nil")")
            return true
        } catch {
            let nsError = error as NSError
            print("🦐 [AdService] ❌ 广告加载失败 code=\(nsError.code) domain=\(nsError.domain) desc=\(nsError.localizedDescription)")
            return false
        }
    }

    func showAppOpenAd(onDismiss: @escaping () -> Void) {
        guard let ad = appOpenAd else {
            print("🦐 [AdService] 广告未就绪")
            onDismiss()
            return
        }

        if let loadTime = appOpenLoadTime,
           Date().timeIntervalSince(loadTime) > AdConfig.adExpiryInterval {
            print("🦐 [AdService] 广告已过期")
            appOpenAd = nil
            isAppOpenAdReady = false
            onDismiss()
            return
        }

        appOpenAdOnDismiss = onDismiss

        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let rootVC = keyWindow.rootViewController else {
            onDismiss()
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        ad.present(fromRootViewController: topVC)
        appOpenAd = nil
        isAppOpenAdReady = false
    }

    func showRewardedAd(
        placement: AdPlacementConfig,
        ssvCustomData: String
    ) async -> AdRewardResult {
        guard placement.enabled,
              !placement.adUnitID.isEmpty,
              [.rewarded, .rewardedInterstitial].contains(placement.format),
              rewardedPresentation == nil,
              let viewController = topViewController() else {
            return .failed
        }

        do {
            switch placement.format {
            case .rewarded:
                let ad = try await GADRewardedAd.load(
                    withAdUnitID: placement.adUnitID,
                    request: GADRequest()
                )
                configureSSV(on: ad, customData: ssvCustomData)
                return await present(
                    ad: ad,
                    from: viewController,
                    rewardCoins: placement.rewardCoins
                )
            case .rewardedInterstitial:
                let ad = try await GADRewardedInterstitialAd.load(
                    withAdUnitID: placement.adUnitID,
                    request: GADRequest()
                )
                configureSSV(on: ad, customData: ssvCustomData)
                return await present(
                    ad: ad,
                    from: viewController,
                    rewardCoins: placement.rewardCoins
                )
            default:
                return .failed
            }
        } catch {
            print("🦐 [AdService] 激励广告加载失败: \(error.localizedDescription)")
            return .failed
        }
    }

    func showInterstitial() async -> Bool { true }

    private func configureSSV(
        on ad: GADRewardedAd,
        customData: String
    ) {
        let options = GADServerSideVerificationOptions()
        options.customRewardString = customData
        ad.serverSideVerificationOptions = options
    }

    private func configureSSV(
        on ad: GADRewardedInterstitialAd,
        customData: String
    ) {
        let options = GADServerSideVerificationOptions()
        options.customRewardString = customData
        ad.serverSideVerificationOptions = options
    }

    private func present(
        ad: GADRewardedAd,
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
            ad.present(fromRootViewController: viewController) {
                delegate.didEarnReward()
            }
        }
    }

    private func present(
        ad: GADRewardedInterstitialAd,
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
            ad.present(fromRootViewController: viewController) {
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
}

extension RealAdService: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("🦐 [AdService] 广告关闭")
        appOpenAdOnDismiss?()
        appOpenAdOnDismiss = nil
    }
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("🦐 [AdService] 广告展示失败: \(error.localizedDescription)")
        appOpenAdOnDismiss?()
        appOpenAdOnDismiss = nil
    }
}

@MainActor
private final class RewardedPresentationDelegate: NSObject, GADFullScreenContentDelegate {
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

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        finish(earnedReward ? .rewarded(coins: rewardCoins) : .cancelled)
    }

    func ad(
        _ ad: GADFullScreenPresentingAd,
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
