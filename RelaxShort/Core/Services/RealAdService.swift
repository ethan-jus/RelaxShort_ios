import GoogleMobileAds
import SwiftUI

final class RealAdService: NSObject, ObservableObject, AdServiceProtocol {
    static let shared = RealAdService()

    private var appOpenAd: GADAppOpenAd?
    private var appOpenLoadTime: Date?
    private var appOpenAdOnDismiss: (() -> Void)?
    private var lastBackgroundTime: Date?
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
        let unitID = AdConfig.appOpenAdUnitID
        print("🦐 [AdService] 开始加载广告，unitID: \(unitID)")
        do {
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

    // 原有 Rewarded/Interstitial stub 保持不动
    func showRewardedAd(coins: Int) async -> AdRewardResult { .rewarded(coins: coins) }
    func showUnlockAd() async -> AdRewardResult { .rewarded(coins: 0) }
    func showInterstitial() async -> Bool { true }
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
