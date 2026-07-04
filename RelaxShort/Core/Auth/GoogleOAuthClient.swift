import GoogleSignIn
import UIKit

protocol GoogleOAuthClientProtocol {
    @MainActor func signIn() async throws -> String
    @MainActor func signOut()
}

/// Google SDK 仅负责取得 ID token；账户创建、归属和资产合并由后端完成。
final class GoogleOAuthClient: GoogleOAuthClientProtocol {
    @MainActor
    func signIn() async throws -> String {
        guard let presenting = Self.topViewController() else {
            throw AuthError.noPresentingViewController
        }
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        } catch let error as NSError
            where error.domain == kGIDSignInErrorDomain && error.code == -5 {
            throw CancellationError()
        }
        guard let idToken = result.user.idToken?.tokenString, !idToken.isEmpty else {
            throw AuthError.missingGoogleIDToken
        }
        return idToken
    }

    @MainActor
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    @MainActor
    private static func topViewController(from suppliedRoot: UIViewController? = nil) -> UIViewController? {
        let root = suppliedRoot ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}
