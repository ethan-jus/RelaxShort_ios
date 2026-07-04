import Foundation
import Testing
@testable import RelaxShort

struct ProfileRepositoryContractTests {
    @Test
    func decodesAvatarAndBookmarkCount() throws {
        let json = """
        {
          "user_id": 1,
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
    }
}
