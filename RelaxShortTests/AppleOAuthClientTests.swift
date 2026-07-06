import CryptoKit
import Foundation
import Testing
@testable import RelaxShort

@MainActor
@Suite(.serialized)
struct AppleOAuthClientTests {

    // MARK: - Nonce Generation (Pure Logic)

    @Test
    func sha256HexOutputIsStable64CharLowercase() {
        // 使用确定性输入验证 SHA-256 输出
        let input = "test-raw-nonce-1234567890"
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        let hex = hashed.compactMap { String(format: "%02x", $0) }.joined()

        #expect(hex.count == 64)
        #expect(hex == hex.lowercased())
        // 验证确定性
        let again = SHA256.hash(data: inputData)
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(hex == again)
    }

    @Test
    func credentialEqualityWorks() {
        let a = AppleOAuthCredential(
            identityToken: "token",
            authorizationCode: "code",
            rawNonce: "nonce",
            userIdentifier: "user-001",
            displayName: "John"
        )
        let b = AppleOAuthCredential(
            identityToken: "token",
            authorizationCode: "code",
            rawNonce: "nonce",
            userIdentifier: "user-001",
            displayName: "John"
        )
        let c = AppleOAuthCredential(
            identityToken: "other",
            authorizationCode: "code",
            rawNonce: "nonce",
            userIdentifier: "user-001",
            displayName: nil
        )
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func credentialDisplayNameCanBeNil() {
        let cred = AppleOAuthCredential(
            identityToken: "token",
            authorizationCode: "code",
            rawNonce: "nonce",
            userIdentifier: "user-001",
            displayName: nil
        )
        #expect(cred.displayName == nil)
    }
}

// MARK: - Fake Client for Coordinator Tests

final class AppleClientFake: AppleOAuthClientProtocol {
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    @MainActor
    func signIn() async throws -> AppleOAuthCredential {
        if let error { throw error }
        return AppleOAuthCredential(
            identityToken: "apple-id-token",
            authorizationCode: "apple-auth-code",
            rawNonce: "apple-raw-nonce",
            userIdentifier: "apple-user-001",
            displayName: "Test User"
        )
    }
}
