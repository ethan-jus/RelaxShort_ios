import Foundation
import Testing
@testable import RelaxShort

struct ProfileRepositoryContractTests {
    @Test
    func decodesAvatarAndBookmarkCount() throws {
        let json = """
        {
          "user_id": 1,
          "public_id": "RS0000000001",
          "account_type": "REGISTERED",
          "nickname": "Ethan",
          "avatar_url": "https://cdn.example/avatar.png",
          "bookmark_count": 3,
          "role": "USER",
          "vip_level": 1,
          "status": 1,
          "preferences": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(
            UserProfileResponseDTO.self,
            from: json
        )

        #expect(dto.avatarUrl == "https://cdn.example/avatar.png")
        #expect(dto.bookmarkCount == 3)
        #expect(dto.publicId == "RS0000000001")
    }
}
