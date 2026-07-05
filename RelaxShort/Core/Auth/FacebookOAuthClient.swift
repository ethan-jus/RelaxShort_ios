import FacebookLogin
import UIKit

// MARK: - Facebook OAuth Credential

struct FacebookOAuthCredential: Equatable {
    let authenticationToken: String
    let nonce: String
}

protocol FacebookOAuthClientProtocol {
    @MainActor func signIn() async throws -> FacebookOAuthCredential
    @MainActor func signOut()
}

// MARK: - Facebook OAuth Client

/// Facebook Limited Login：使用 AuthenticationToken JWT + nonce。
/// 仅返回签名凭据；不返回 AccessToken、Profile.current 或 userID。
final class FacebookOAuthClient: FacebookOAuthClientProtocol {
    private let loginManager = LoginManager()

    @MainActor
    func signIn() async throws -> FacebookOAuthCredential {
        let nonce = UUID().uuidString.lowercased()
        let configuration = LoginConfiguration(
            permissions: ["public_profile", "email"],
            tracking: .limited,
            nonce: nonce
        )

        return try await withCheckedThrowingContinuation { continuation in
            loginManager.logIn(viewController: nil, configuration: configuration) { result in
                switch result {
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .success:
                    guard let token = AuthenticationToken.current?.tokenString,
                          !token.isEmpty else {
                        continuation.resume(throwing: AuthError.missingFacebookAuthenticationToken)
                        return
                    }
                    continuation.resume(returning: FacebookOAuthCredential(
                        authenticationToken: token,
                        nonce: nonce
                    ))
                }
            }
        }
    }

    @MainActor
    func signOut() {
        loginManager.logOut()
    }
}
