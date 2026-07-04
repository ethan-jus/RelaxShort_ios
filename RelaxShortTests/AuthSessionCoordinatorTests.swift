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
            googleClient: GoogleClientFake()
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
            googleClient: GoogleClientFake()
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
            googleClient: GoogleClientFake()
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
            googleClient: GoogleClientFake(error: CancellationError())
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
            googleClient: GoogleClientFake()
        )
        await coordinator.bootstrap()
        await coordinator.signInWithGoogle()
        #expect(coordinator.isRegistered)

        await coordinator.logout()

        #expect(coordinator.hasSession)
        #expect(coordinator.isRegistered == false)
        #expect(repository.loggedOutRefreshTokens == ["google-refresh"])
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
