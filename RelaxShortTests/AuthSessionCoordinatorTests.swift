import Foundation
import Testing
@testable import RelaxShort

@MainActor
@Suite(.serialized)
struct AuthSessionCoordinatorTests {
    @Test
    func bootstrapCreatesRealAnonymousSession() async {
        let repository = AuthRepositoryFake()
        let tokens = TokenStoreFake()
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: tokens,
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )

        await coordinator.bootstrap()

        #expect(coordinator.hasSession)
        #expect(coordinator.isRegistered == false)
        #expect(tokens.token == "anonymous-refresh")
    }

    @Test
    func googleUpgradeReplacesAnonymousSession() async {
        let repository = AuthRepositoryFake()
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )
        await coordinator.bootstrap()

        await coordinator.signInWithGoogle()

        #expect(coordinator.isRegistered)
        #expect(coordinator.account?.provider == "google")
    }

    @Test
    func googleResponseLossReusesMergeRequestID() async {
        let repository = AuthRepositoryFake()
        repository.googleError = NetworkError.networkTimeout
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )
        await coordinator.bootstrap()

        await coordinator.signInWithGoogle()
        repository.googleError = nil
        await coordinator.signInWithGoogle()

        #expect(repository.googleMergeRequestIDs.count == 2)
        #expect(repository.googleMergeRequestIDs[0] == repository.googleMergeRequestIDs[1])
        #expect(coordinator.isRegistered)
    }

    @Test
    func googleCancellationDoesNotShowError() async {
        let repository = AuthRepositoryFake()
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(error: CancellationError()),
            facebookClient: FacebookClientFake()
        )
        await coordinator.bootstrap()

        await coordinator.signInWithGoogle()

        #expect(coordinator.errorMessage == nil)
        #expect(coordinator.isRegistered == false)
    }

    @Test
    func logoutReplacesRegisteredSessionWithAnonymousSession() async {
        let repository = AuthRepositoryFake()
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )
        await coordinator.bootstrap()
        await coordinator.signInWithGoogle()
        #expect(coordinator.isRegistered)

        await coordinator.logout()

        #expect(coordinator.hasSession)
        #expect(coordinator.isRegistered == false)
        #expect(repository.loggedOutRefreshTokens == ["google-refresh"])
    }

    @Test
    func facebookUpgradeReplacesAnonymousSession() async {
        let repository = AuthRepositoryFake()
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )
        await coordinator.bootstrap()

        await coordinator.signInWithFacebook()

        #expect(coordinator.isRegistered)
        #expect(coordinator.account?.provider == "facebook")
        #expect(repository.facebookNonces == ["facebook-nonce"])
    }

    @Test
    func facebookResponseLossReusesMergeRequestID() async {
        let repository = AuthRepositoryFake()
        repository.facebookError = NetworkError.networkTimeout
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )
        await coordinator.bootstrap()

        await coordinator.signInWithFacebook()
        repository.facebookError = nil
        await coordinator.signInWithFacebook()

        #expect(repository.facebookMergeRequestIDs.count == 2)
        #expect(repository.facebookMergeRequestIDs[0] == repository.facebookMergeRequestIDs[1])
        #expect(coordinator.isRegistered)
    }

    @Test
    func facebookCancellationDoesNotShowError() async {
        let coordinator = AuthSessionCoordinator(
            repository: AuthRepositoryFake(),
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(error: CancellationError())
        )
        await coordinator.bootstrap()

        await coordinator.signInWithFacebook()

        #expect(coordinator.errorMessage == nil)
        #expect(coordinator.isRegistered == false)
    }
}

private final class TokenStoreFake: AuthTokenStoring {
    var token: String?
    func readRefreshToken() throws -> String? { token }
    func saveRefreshToken(_ token: String) throws { self.token = token }
    func deleteRefreshToken() throws { token = nil }
}

private final class AuthRepositoryFake: RealAuthRepositoryProtocol {
    var googleError: Error?
    var googleMergeRequestIDs: [UUID] = []
    var facebookError: Error?
    var facebookMergeRequestIDs: [UUID] = []
    var facebookNonces: [String] = []
    var appleError: Error?
    var appleMergeRequestIDs: [UUID] = []
    var appleRawNonces: [String] = []
    var appleDisplayNames: [String?] = []
    var loggedOutRefreshTokens: [String] = []

    func createAnonymous(deviceID: String, idempotencyKey: UUID) async throws -> AuthSession {
        makeSession(type: .anonymous, prefix: "anonymous")
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        makeSession(type: .anonymous, prefix: "renewed")
    }

    func signInWithGoogle(
        idToken: String,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession {
        googleMergeRequestIDs.append(mergeRequestID)
        if let googleError { throw googleError }
        return makeSession(type: .registered, prefix: "google", provider: "google")
    }

    func signInWithFacebook(
        authenticationToken: String,
        nonce: String,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession {
        facebookMergeRequestIDs.append(mergeRequestID)
        facebookNonces.append(nonce)
        if let facebookError { throw facebookError }
        return makeSession(type: .registered, prefix: "facebook", provider: "facebook")
    }

    func signInWithApple(
        identityToken: String,
        authorizationCode: String,
        rawNonce: String,
        displayName: String?,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession {
        appleMergeRequestIDs.append(mergeRequestID)
        appleRawNonces.append(rawNonce)
        appleDisplayNames.append(displayName)
        if let appleError { throw appleError }
        return makeSession(type: .registered, prefix: "apple", provider: "apple")
    }

    func logout(_ refreshToken: String) async throws {
        loggedOutRefreshTokens.append(refreshToken)
    }

    private func makeSession(
        type: AccountType,
        prefix: String,
        provider: String? = nil
    ) -> AuthSession {
        AuthSession(
            accessToken: "\(prefix)-access",
            accessTokenExpiresAt: Date().addingTimeInterval(900),
            refreshToken: "\(prefix)-refresh",
            refreshTokenExpiresAt: Date().addingTimeInterval(2_592_000),
            account: AuthAccount(
                publicID: "RS0000000001",
                accountType: type,
                nickname: nil,
                avatarURL: nil,
                provider: provider
            )
        )
    }
}

private final class GoogleClientFake: GoogleOAuthClientProtocol {
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    @MainActor func signIn() async throws -> String {
        if let error { throw error }
        return "google-id-token"
    }
    @MainActor func signOut() {}
}

private final class FacebookClientFake: FacebookOAuthClientProtocol {
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    @MainActor func signIn() async throws -> FacebookOAuthCredential {
        if let error { throw error }
        return FacebookOAuthCredential(
            authenticationToken: "facebook-authentication-token",
            nonce: "facebook-nonce"
        )
    }

    @MainActor func signOut() {}
}

// MARK: - Apple Tests

extension AuthSessionCoordinatorTests {

    @Test
    func appleUpgradeReplacesAnonymousSession() async {
        let repository = AuthRepositoryFake()
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )
        await coordinator.bootstrap()

        await coordinator.signInWithApple()

        #expect(coordinator.isRegistered)
        #expect(coordinator.account?.provider == "apple")
        #expect(repository.appleRawNonces == ["apple-raw-nonce"])
    }

    @Test
    func appleResponseLossReusesMergeRequestID() async {
        let repository = AuthRepositoryFake()
        repository.appleError = NetworkError.networkTimeout
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )
        await coordinator.bootstrap()

        await coordinator.signInWithApple()
        repository.appleError = nil
        await coordinator.signInWithApple()

        #expect(repository.appleMergeRequestIDs.count == 2)
        #expect(repository.appleMergeRequestIDs[0] == repository.appleMergeRequestIDs[1])
        #expect(coordinator.isRegistered)
    }

    @Test
    func appleCancellationDoesNotShowError() async {
        let coordinator = AuthSessionCoordinator(
            repository: AuthRepositoryFake(),
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake(error: CancellationError())
        )
        await coordinator.bootstrap()

        await coordinator.signInWithApple()

        #expect(coordinator.errorMessage == nil)
        #expect(coordinator.isRegistered == false)
    }

    @Test
    func appleConcurrencyGateBlocksOtherProviders() async {
        let repository = AuthRepositoryFake()
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake(error: CancellationError())
        )
        await coordinator.bootstrap()

        await coordinator.signInWithApple()

        #expect(coordinator.isRegistered == false)
    }

    @Test
    func logoutClearsApplePendingKey() async {
        let repository = AuthRepositoryFake()
        let coordinator = AuthSessionCoordinator(
            repository: repository,
            tokenStore: TokenStoreFake(),
            googleClient: GoogleClientFake(),
            facebookClient: FacebookClientFake(),
            appleClient: AppleClientFake()
        )
        await coordinator.bootstrap()
        await coordinator.signInWithApple()

        #expect(coordinator.isRegistered)
        await coordinator.logout()

        #expect(coordinator.hasSession)
        #expect(coordinator.isRegistered == false)
        #expect(repository.loggedOutRefreshTokens == ["apple-refresh"])
    }
}
