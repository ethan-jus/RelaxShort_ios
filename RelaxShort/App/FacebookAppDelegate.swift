import FBSDKCoreKit
import UIKit

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
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        ApplicationDelegate.shared.application(
            app,
            open: url,
            sourceApplication:
                options[.sourceApplication] as? String,
            annotation: options[.annotation]
        )
    }
}
