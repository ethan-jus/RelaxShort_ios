import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

// MARK: - Apple OAuth Credential

/// 原生 Sign in with Apple 返回的凭据。仅保留验签所需的字段。
struct AppleOAuthCredential: Equatable {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
    let userIdentifier: String
    let displayName: String?
}

// MARK: - Protocol

protocol AppleOAuthClientProtocol {
    @MainActor
    func signIn() async throws -> AppleOAuthCredential
}

// MARK: - Client Errors

enum AppleOAuthError: Error, LocalizedError {
    case missingIdentityToken
    case missingAuthorizationCode
    case randomGenerationFailed
    case unexpectedCredentialType

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Apple 登录未返回身份令牌。"
        case .missingAuthorizationCode:
            return "Apple 登录未返回授权码。"
        case .randomGenerationFailed:
            return "安全随机数生成失败，请重试。"
        case .unexpectedCredentialType:
            return "Apple 登录返回了意外的凭据类型。"
        }
    }
}

// MARK: - Delegate Bridge

/// 持有 ASAuthorizationController 回调 continuation。
/// 同时作为 delegate 和 presentation context provider，简化生命周期管理。
private final class AppleAuthBridge: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<AppleOAuthCredential, Error>?
    private let rawNonce: String
    private var resumed = false

    init(rawNonce: String) {
        self.rawNonce = rawNonce
    }

    @MainActor
    func perform() async throws -> AppleOAuthCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256Hex(rawNonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard !resumed, let c = self.continuation else { return }
        resumed = true
        self.continuation = nil

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            c.resume(throwing: AppleOAuthError.unexpectedCredentialType)
            return
        }
        guard let idData = credential.identityToken,
              let idToken = String(data: idData, encoding: .utf8),
              !idToken.isEmpty else {
            c.resume(throwing: AppleOAuthError.missingIdentityToken)
            return
        }
        guard let codeData = credential.authorizationCode,
              let authCode = String(data: codeData, encoding: .utf8),
              !authCode.isEmpty else {
            c.resume(throwing: AppleOAuthError.missingAuthorizationCode)
            return
        }

        let displayName: String?
        if let fullName = credential.fullName {
            let formatted = PersonNameComponentsFormatter()
                .string(from: fullName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty {
                displayName = formatted
            } else {
                displayName = nil
            }
        } else {
            displayName = nil
        }

        c.resume(returning: AppleOAuthCredential(
            identityToken: idToken,
            authorizationCode: authCode,
            rawNonce: rawNonce,
            userIdentifier: credential.user,
            displayName: displayName
        ))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        guard !resumed, let c = self.continuation else { return }
        resumed = true
        self.continuation = nil

        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            c.resume(throwing: CancellationError())
        } else {
            c.resume(throwing: error)
        }
    }

    // MARK: Presentation Context

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? UIWindow()
    }

    // MARK: Nonce

    private func sha256Hex(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Client Implementation

final class AppleOAuthClient: AppleOAuthClientProtocol {
    @MainActor
    func signIn() async throws -> AppleOAuthCredential {
        let rawNonce = try generateNonce()
        let bridge = AppleAuthBridge(rawNonce: rawNonce)
        return try await bridge.perform()
    }

    private func generateNonce() throws -> String {
        let length = 32
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            throw AppleOAuthError.randomGenerationFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
