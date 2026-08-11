import FBSDKCoreKit
import UIKit

/// Facebook 登录按需初始化。自动事件与广告标识采集均已关闭，冷启动无需提前访问 Facebook。
@MainActor
enum FacebookSDKBootstrap {
    private static var didInitialize = false
    private static var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

    static func recordLaunchOptions(_ options: [UIApplication.LaunchOptionsKey: Any]?) {
        launchOptions = options
    }

    @discardableResult
    static func initializeIfNeeded() -> Bool {
        guard !didInitialize else { return true }
        didInitialize = true
        return ApplicationDelegate.shared.application(
            UIApplication.shared,
            didFinishLaunchingWithOptions: launchOptions
        )
    }
}

final class FacebookAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == OfflineDownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        OfflineDownloadManager.shared.backgroundSessionCompletionHandler =
            completionHandler
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FacebookSDKBootstrap.recordLaunchOptions(launchOptions)
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        FacebookSDKBootstrap.initializeIfNeeded()
        return ApplicationDelegate.shared.application(
            app,
            open: url,
            sourceApplication:
                options[.sourceApplication] as? String,
            annotation: options[.annotation]
        )
    }
}
