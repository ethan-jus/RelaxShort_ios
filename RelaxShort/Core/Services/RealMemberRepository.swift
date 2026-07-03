import Foundation

// MARK: - Real Member Repository

/// 真实 Member 订阅页数据仓库。
/// 调用 `GET /api/v2/member`，不依赖 Mock 数据。
struct RealMemberRepository: MemberRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchMemberContent(
        contentLanguage: String?,
        countryCode: String?
    ) async throws -> MemberContent {
        let dto: MemberResponseDTO = try await client.requestData(
            .member(
                contentLanguage: contentLanguage,
                countryCode: countryCode
            )
        )
        return MemberContent(
            backgroundPosters: dto.backgroundPosters.map(FeedCardDTOMapper.toDramaItem),
            memberOnlyDramas: dto.memberOnlyDramas.map(FeedCardDTOMapper.toDramaItem)
        )
    }
}
