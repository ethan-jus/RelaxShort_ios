import SwiftUI
import Combine

// MARK: - Login Method

/// 用户登录方式枚举
enum LoginMethod: String, Codable, CaseIterable {
    case google
    case apple
    case facebook
    case guest
}

// MARK: - Auth Store

/// 管理用户认证状态、VIP 状态、金币余额等。
/// 直接使用 MockAuthProvider 模拟登录（Phase 2 接入真实 SDK）。
@MainActor
final class AuthStore: ObservableObject {
    // MARK: Published

    @Published var isLoggedIn: Bool = false
    @Published var currentUser: User?
    @Published var loginMethod: LoginMethod?
    @Published var isVip: Bool = false
    @Published var vipExpireDate: Date?
    @Published var coinBalance: Int = 0
    @Published var isSigningIn: Bool = false
    @Published var authError: String?

    // MARK: Dependencies

    private let authProvider = MockAuthProvider()
    private let storage = StorageService.shared

    // MARK: Init

    init() {
        loadState()
    }

    // MARK: - Public Sign-In Actions

    func signInWithGoogle() {
        signIn(with: .google) { [authProvider] in
            try await authProvider.signInWithGoogle()
        }
    }

    func signInWithApple() {
        signIn(with: .apple) { [authProvider] in
            try await authProvider.signInWithApple()
        }
    }

    func signInWithFacebook() {
        signIn(with: .facebook) { [authProvider] in
            try await authProvider.signInWithFacebook()
        }
    }

    func signInAsGuest() {
        signIn(with: .guest) { [authProvider] in
            try await authProvider.signInAsGuest()
        }
    }

    // MARK: - Logout

    func logout() {
        storage.clearAuthData()
        isLoggedIn = false
        currentUser = nil
        loginMethod = nil
        isVip = false
        vipExpireDate = nil
        coinBalance = 0
        authError = nil
    }

    // MARK: - VIP / Coins

    func updateVipStatus(isVip: Bool, expireDate: Date?) {
        self.isVip = isVip
        self.vipExpireDate = expireDate
        persistUser()
    }

    func updateCoins(_ newBalance: Int) {
        coinBalance = newBalance
        persistUser()
    }

    /// 从后端加载的 Profile 数据同步到 AuthStore（不改变登录状态）。
    /// 调用方必须已确认 `isLoggedIn == true` 后再使用此方法。
    func applyLoadedProfile(_ user: User) {
        currentUser = user
        isVip = user.isVipValid
        vipExpireDate = user.vipExpireDate
        coinBalance = user.coinBalance
        storage.userId = user.id
        persistUser()
    }

    // MARK: - Private Helpers

    private func signIn(
        with method: LoginMethod,
        operation: @escaping () async throws -> User
    ) {
        Task {
            guard !isSigningIn else { return }
            isSigningIn = true
            authError = nil

            do {
                let user = try await operation()
                applySignIn(user: user, method: method)
            } catch {
                authError = error.localizedDescription
                logError("AuthStore.signIn(\(method)) failed: \(error)")
            }

            isSigningIn = false
        }
    }

    private func applySignIn(user: User, method: LoginMethod) {
        isLoggedIn = true
        currentUser = user
        loginMethod = method
        isVip = user.isVipValid
        vipExpireDate = user.vipExpireDate
        coinBalance = user.coinBalance
        saveState(method: method)
    }

    private func loadState() {
        isLoggedIn = storage.isLoggedIn

        guard isLoggedIn,
              let data = storage.userProfileData,
              let user = try? JSONDecoder().decode(User.self, from: data) else {
            return
        }

        currentUser = user
        loginMethod = storage.loginMethod
        isVip = user.isVipValid
        vipExpireDate = user.vipExpireDate
        coinBalance = user.coinBalance
    }

    private func saveState(method: LoginMethod) {
        storage.isLoggedIn = isLoggedIn
        storage.loginMethod = method
        persistUser()
    }

    /// 将当前用户状态序列化写入 StorageService
    private func persistUser() {
        guard var user = currentUser else { return }
        user.isVip = isVip
        user.vipExpireDate = vipExpireDate
        user.coinBalance = coinBalance

        if let data = try? JSONEncoder().encode(user) {
            storage.userProfileData = data
        }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
