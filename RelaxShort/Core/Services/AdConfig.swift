import Foundation

/// 广告运行时配置（编译时配置，不用 UserDefaults）
enum AdConfig {
    /// 热启动展示间隔（秒），在后台超过此时间再次进入才展示开屏广告
    static let hotStartAdInterval: TimeInterval = 60.0

    /// 品牌页最短展示时长。
    static let brandingDuration: TimeInterval = 0.8

    /// 品牌展示结束后额外等待开屏广告的硬上限；总预算约 2 秒。
    static let coldStartAdLoadTimeout: TimeInterval = 1.2

    /// 广告过期时间（秒），AdMob 官方是 4 小时
    static let adExpiryInterval: TimeInterval = 4 * 3600

    /// 激励广告缓存最多保留一小时，超时后重新请求，避免展示陈旧竞价结果。
    static let rewardedAdExpiryInterval: TimeInterval = 3600

    /// 开发构建、模拟器和 TestFlight 必须使用 Google 官方测试广告位。
    /// 只有 App Store 正式包使用后端下发的正式广告位。
    static func adUnitID(remoteID: String, format: AdFormat) -> String {
        guard shouldUseTestAdUnits else { return remoteID }

        switch format {
        case .appOpen:
            return "ca-app-pub-3940256099942544/5575463023"
        case .rewarded:
            return "ca-app-pub-3940256099942544/1712485313"
        case .rewardedInterstitial:
            return "ca-app-pub-3940256099942544/6978759866"
        case .interstitial:
            return "ca-app-pub-3940256099942544/4411468910"
        case .unknown:
            return ""
        }
    }

    private static let shouldUseTestAdUnits: Bool = {
        #if targetEnvironment(simulator)
        return true
        #elseif DEBUG
        return true
        #else
        if let url = Bundle.main.appStoreReceiptURL {
            return url.lastPathComponent == "sandboxReceipt"
        }
        return false
        #endif
    }()
}
