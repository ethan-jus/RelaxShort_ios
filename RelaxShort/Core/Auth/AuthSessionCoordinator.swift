import Foundation

/// App 唯一认证状态机。负责匿名账户、token 轮换、Google 升级和退出后重建匿名账户。
@MainActor
final class AuthSessionCoordinator: ObservableObject {
    static let shared = AuthSessionCoordinator()

    @Published private(set) var state: AuthState = .restoring
    @Published private(set) var isSigningIn = false
    @Published private(set) var errorMessage: String?

    private let repository: RealAuthRepositoryProtocol
    private let tokenStore: AuthTokenStoring
    private let googleClient: GoogleOAuthClientProtocol
    private var session: AuthSession?
    private var bootstrapTask: Task<Void, Never>?
    private var refreshTask: Task<AuthSession, Error>?

    private let bootstrapKeyName = "auth.anonymous-bootstrap-key"
    private let googleMergeRequestKeyName = "auth.google-merge-request-key"

    init(
        repository: RealAuthRepositoryProtocol = RealAuthRepository(),
        tokenStore: AuthTokenStoring = AuthKeychainStore.shared,
        googleClient: GoogleOAuthClientProtocol = GoogleOAuthClient()
    ) {
        self.repository = repository
        self.tokenStore = tokenStore
        self.googleClient = googleClient
    }

    var hasSession: Bool { session != nil }
    var isRegistered: Bool { state.account?.isRegistered == true }
    var account: AuthAccount? { state.account }

    func clearError() {
        errorMessage = nil
    }

    func bootstrap() async {
        if session != nil { return }
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        let task = Task { await restoreOrCreateSession() }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    private func restoreOrCreateSession() async {
        state = .restoring

        if let refreshToken = try? tokenStore.readRefreshToken() {
            do {
                try install(try await repository.refresh(refreshToken))
                return
            } catch {
                try? tokenStore.deleteRefreshToken()
            }
        }
        await createAnonymous()
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if session == nil { await bootstrap() }
        guard let current = session else { throw AuthError.invalidSession }
        if !forceRefresh, current.accessTokenExpiresAt.timeIntervalSinceNow > 60 {
            return current.accessToken
        }
        return try await refreshSession().accessToken
    }

    func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let token = try await validAccessToken()
            let idToken = try await googleClient.signIn()
            let defaults = UserDefaults.standard
            let mergeRequestID: UUID
            if let raw = defaults.string(forKey: googleMergeRequestKeyName),
               let pending = UUID(uuidString: raw) {
                mergeRequestID = pending
            } else {
                mergeRequestID = UUID()
                defaults.set(
                    mergeRequestID.uuidString.lowercased(),
                    forKey: googleMergeRequestKeyName
                )
            }
            let upgraded = try await repository.signInWithGoogle(
                idToken: idToken,
                anonymousAccessToken: token,
                deviceID: InstallIdentityProvider.shared.installID(),
                mergeRequestID: mergeRequestID
            )
            try install(upgraded)
            defaults.removeObject(forKey: googleMergeRequestKeyName)
        } catch {
            if error is CancellationError { return }
            if let apiError = error as? APIError,
               apiError.code == "AUTH_ACCOUNT_MERGE_CONFLICT" {
                // 身份与挂起请求不一致时废弃旧键，允许用户重新选择账号。
                UserDefaults.standard.removeObject(forKey: googleMergeRequestKeyName)
            }
            errorMessage = error.localizedDescription
        }
    }

    /// 退出注册账户后立即创建全新的匿名账户，避免旧注册资产继续留在当前设备会话。
    func logout() async {
        let oldRefreshToken = session?.refreshToken
        session = nil
        state = .restoring
        try? tokenStore.deleteRefreshToken()
        googleClient.signOut()
        UserDefaults.standard.removeObject(forKey: bootstrapKeyName)
        UserDefaults.standard.removeObject(forKey: googleMergeRequestKeyName)
        await bootstrap()
        if let oldRefreshToken {
            try? await repository.logout(oldRefreshToken)
        }
    }

    private func refreshSession() async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = session?.refreshToken ?? (try? tokenStore.readRefreshToken()) else {
            throw AuthError.invalidSession
        }

        let task = Task { try await repository.refresh(refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let renewed = try await task.value
            try install(renewed)
            return renewed
        } catch {
            session = nil
            try? tokenStore.deleteRefreshToken()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    private func createAnonymous() async {
        let defaults = UserDefaults.standard
        let requestID: UUID
        if let raw = defaults.string(forKey: bootstrapKeyName), let saved = UUID(uuidString: raw) {
            requestID = saved
        } else {
            requestID = UUID()
            defaults.set(requestID.uuidString.lowercased(), forKey: bootstrapKeyName)
        }

        do {
            let anonymous = try await repository.createAnonymous(
                deviceID: InstallIdentityProvider.shared.installID(),
                idempotencyKey: requestID
            )
            try install(anonymous)
            defaults.removeObject(forKey: bootstrapKeyName)
        } catch {
            state = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func install(_ newSession: AuthSession) throws {
        try tokenStore.saveRefreshToken(newSession.refreshToken)
        session = newSession
        state = newSession.account.isRegistered
            ? .authenticated(newSession.account)
            : .anonymous(newSession.account)
    }
}
