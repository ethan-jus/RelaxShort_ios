import Foundation

// MARK: - Mock Auth Provider

/// 模拟第三方登录 Provider，不依赖真实 SDK。
/// 模拟 1.2 秒登录延迟，10% 概率返回失败以测试错误处理。
///
/// 使用方式：
/// ```swift
/// let provider = MockAuthProvider()
/// let result = await provider.signInWithGoogle()
/// ```
struct MockAuthProvider {

    // MARK: - Auth Error

    enum AuthError: LocalizedError {
        case simulationFailure
        case cancelled

        var errorDescription: String? {
            switch self {
            case .simulationFailure: return "模拟登录失败，请重试"
            case .cancelled:         return "登录已取消"
            }
        }
    }

    // MARK: - Constants

    private static let simulatedDelay: UInt64 = 1_200_000_000  // 1.2s
    private static let failureRate: Double = 0.10              // 10%

    // MARK: - Mock Users

    private static func mockUser(for method: LoginMethod) -> User {
        switch method {
        case .google:
            return User(
                id: "u_google_mock_001",
                nickname: "GoogleUser",
                avatarURL: nil,
                isVip: false,
                vipExpireDate: nil,
                coinBalance: 200,
                favoriteCount: 0
            )
        case .apple:
            return User(
                id: "u_apple_mock_001",
                nickname: "AppleUser",
                avatarURL: nil,
                isVip: true,
                vipExpireDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                coinBalance: 500,
                favoriteCount: 5
            )
        case .facebook:
            return User(
                id: "u_facebook_mock_001",
                nickname: "FBUser",
                avatarURL: nil,
                isVip: false,
                vipExpireDate: nil,
                coinBalance: 100,
                favoriteCount: 1
            )
        case .guest:
            return User(
                id: "u_guest_\(UUID().uuidString.prefix(8))",
                nickname: "游客\(Int.random(in: 1000...9999))",
                avatarURL: nil,
                isVip: false,
                vipExpireDate: nil,
                coinBalance: 50,
                favoriteCount: 0
            )
        }
    }

    // MARK: - Public Methods

    func signInWithGoogle() async throws -> User {
        try await simulateDelay(for: .google)
        return try simulateResult(for: .google)
    }

    func signInWithApple() async throws -> User {
        try await simulateDelay(for: .apple)
        return try simulateResult(for: .apple)
    }

    func signInWithFacebook() async throws -> User {
        try await simulateDelay(for: .facebook)
        return try simulateResult(for: .facebook)
    }

    func signInAsGuest() async throws -> User {
        try await simulateDelay(for: .guest)
        return try simulateResult(for: .guest)
    }

    // MARK: - Private

    private func simulateDelay(for method: LoginMethod) async throws {
        try await Task.sleep(nanoseconds: Self.simulatedDelay)
    }

    private func simulateResult(for method: LoginMethod) throws -> User {
        if Double.random(in: 0...1) < Self.failureRate {
            throw AuthError.simulationFailure
        }
        return Self.mockUser(for: method)
    }
}
