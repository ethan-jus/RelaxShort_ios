import Foundation
import Testing
@testable import RelaxShort

@MainActor
@Suite(.serialized)
struct AppleOAuthClientTests {

    // MARK: - Nonce Generation (Pure Logic)

    @Test
    func sha256HexOutputIsStable64CharLowercase() {
        let input = "test-raw-nonce-1234567890"
        let hex = AppleNonce.sha256Hex(input)

        #expect(hex.count == 64)
        #expect(hex == hex.lowercased())
        #expect(hex == "b003489bed192c917c3aff5a9647372ef26525e09636711540ab844012f1aa70")
    }

    @Test
    func nonceGenerationUsesProvidedSecureBytesAndBase64URL() throws {
        let nonce = try AppleNonce.generate { length in
            #expect(length == 32)
            return Array(0..<UInt8(length))
        }

        #expect(nonce == "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        #expect(nonce.count == 43)
    }

    @Test
    func nonceGenerationMapsRandomSourceFailure() {
        enum TestFailure: Error { case failed }

        do {
            _ = try AppleNonce.generate { _ in throw TestFailure.failed }
            Issue.record("安全随机源失败时应抛出错误")
        } catch AppleOAuthError.randomGenerationFailed {
            // 预期错误
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
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
