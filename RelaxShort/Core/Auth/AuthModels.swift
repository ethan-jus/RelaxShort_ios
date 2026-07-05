import Foundation

/// 后端账户类型。匿名账户同样拥有真实服务端用户和资产。
enum AccountType: String, Codable {
    case anonymous = "ANONYMOUS"
    case registered = "REGISTERED"
    case merged = "MERGED"
}

struct AuthAccount: Codable, Equatable {
    let publicID: String
    let accountType: AccountType
    let nickname: String?
    let avatarURL: String?
    let provider: String?

    var isRegistered: Bool { accountType == .registered }
}

struct AuthSession: Equatable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let account: AuthAccount
}

enum AuthState: Equatable {
    case restoring
    case anonymous(AuthAccount)
    case authenticated(AuthAccount)
    case failed(String)

    var account: AuthAccount? {
        switch self {
        case .anonymous(let account), .authenticated(let account):
            return account
        case .restoring, .failed:
            return nil
        }
    }
}

enum AuthError: LocalizedError {
    case missingGoogleIDToken
    case missingFacebookAuthenticationToken
    case noPresentingViewController
    case invalidSession
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingGoogleIDToken:
            return "Google 未返回有效身份令牌，请重试。"
        case .missingFacebookAuthenticationToken:
            return "未获取到 Facebook 认证令牌"
        case .noPresentingViewController:
            return "暂时无法打开登录页面，请重试。"
        case .invalidSession:
            return "登录状态已失效，请重新登录。"
        case .keychain:
            return "无法安全保存登录状态。"
        }
    }
}
