import Foundation

/// 开屏广告配置（编译时配置，不用 UserDefaults）
enum AdConfig {
    /// 品牌展示后额外等待广告的最长时间（秒）。总最长等待 = brandingDuration + coldStartLoadTimeout
    static let coldStartLoadTimeout: TimeInterval = 2.5

    /// 热启动展示间隔（秒），在后台超过此时间再次进入才展示开屏广告
    static let hotStartAdInterval: TimeInterval = 60.0

    /// 品牌页展示时长（秒）。到期立即检查广告，就绪→展示，未就绪→再等 coldStartLoadTimeout
    static let brandingDuration: TimeInterval = 1.5

    /// 广告过期时间（秒），AdMob 官方是 4 小时
    static let adExpiryInterval: TimeInterval = 4 * 3600

    /// 开屏广告单元 ID — 自动区分正式/开发环境
    /// 判断依据：App Store 分发的包 receipt 不是 sandbox
    /// 开发构建 / TestFlight / 模拟器 → 测试广告
    /// App Store 正式包 → 正式广告
    static let appOpenAdUnitID: String = {
        #if targetEnvironment(simulator)
        return "ca-app-pub-3940256099942544/5575463023"
        #else
        if let url = Bundle.main.appStoreReceiptURL {
            return url.lastPathComponent == "sandboxReceipt"
                ? "ca-app-pub-3940256099942544/5575463023"
                : "ca-app-pub-1181692914441160/2847542268"
        }
        return "ca-app-pub-3940256099942544/5575463023"
        #endif
    }()

    /// AdMob 应用 ID
    static let appID = "ca-app-pub-1181692914441160~7575609396"
}
