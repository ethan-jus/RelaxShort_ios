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
            return "auth.missing_google_token".localized
        case .missingFacebookAuthenticationToken:
            return "auth.missing_facebook_token".localized
        case .noPresentingViewController:
            return "auth.cannot_open_login".localized
        case .invalidSession:
            return "auth.invalid_session".localized
        case .keychain:
            return "auth.keychain_failed".localized
        }
    }
}
