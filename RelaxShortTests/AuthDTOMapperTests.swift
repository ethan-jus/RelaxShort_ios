import Foundation
import Testing
@testable import RelaxShort

struct AuthDTOMapperTests {
    @Test
    func mapsAnonymousSessionAndExpirations() throws {
        let dto = AuthSessionResponseDTO(
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: "refresh",
            refreshTokenExpiresIn: 2_592_000,
            account: AuthAccountDTO(
                publicId: "RS0000000001",
                accountType: "ANONYMOUS",
                nickname: nil,
                avatarUrl: nil,
                provider: nil
            )
        )
        let now = Date(timeIntervalSince1970: 1_000)
        let session = try dto.toDomain(now: now)
        #expect(session.account.accountType == .anonymous)
        #expect(session.accessTokenExpiresAt == now.addingTimeInterval(900))
        #expect(session.refreshTokenExpiresAt == now.addingTimeInterval(2_592_000))
    }
}
