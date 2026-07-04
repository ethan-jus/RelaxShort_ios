import Foundation

struct AuthSessionResponseDTO: Decodable {
    let accessToken: String
    let accessTokenExpiresIn: TimeInterval
    let refreshToken: String
    let refreshTokenExpiresIn: TimeInterval
    let account: AuthAccountDTO
}

struct AuthAccountDTO: Decodable {
    let publicId: String
    let accountType: String
    let nickname: String?
    let avatarUrl: String?
    let provider: String?
}

extension AuthSessionResponseDTO {
    func toDomain(now: Date = Date()) throws -> AuthSession {
        guard let type = AccountType(rawValue: account.accountType) else {
            throw AuthError.invalidSession
        }
        return AuthSession(
            accessToken: accessToken,
            accessTokenExpiresAt: now.addingTimeInterval(accessTokenExpiresIn),
            refreshToken: refreshToken,
            refreshTokenExpiresAt: now.addingTimeInterval(refreshTokenExpiresIn),
            account: AuthAccount(
                publicID: account.publicId,
                accountType: type,
                nickname: account.nickname,
                avatarURL: account.avatarUrl,
                provider: account.provider
            )
        )
    }
}
