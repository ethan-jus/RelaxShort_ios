import Foundation

// MARK: - Real Search Repository

/// 真实后端搜索仓库。
@MainActor
final class RealSearchRepository: SearchRepositoryProtocol {

    private let client = APIClient.shared

    func fetchSuggestions() async throws -> [String] {
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")
        let dto: SearchDefaultResponseDTO = try await client.requestData(
            .searchDefault(contentLanguage: contentLang, countryCode: country)
        )
        return dto.suggestions ?? []
    }

    /// 执行真实搜索
    func search(query: String, cursor: String? = nil, limit: Int = 20) async throws -> ([DramaItem], String?, Bool) {
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")
        let dto: SearchResponseDTO = try await client.requestData(
            .searchV2(query: query, cursor: cursor, limit: limit,
                      contentLanguage: contentLang, countryCode: country)
        )
        let items = (dto.items ?? []).map(FeedCardDTOMapper.toDramaItem)
        return (items, dto.nextCursor, dto.hasMore ?? false)
    }
}

// MARK: - DTOs for Search

struct SearchDefaultResponseDTO: Decodable {
    let hotSeries: [FeedCardDTO]?
    let suggestions: [String]?
    let categories: [CategoryItemDTO]?
}

struct CategoryItemDTO: Decodable {
    let code: String?
    let localizedName: String?
    let iconUrl: String?
    let sortOrder: Int?
}

struct SearchResponseDTO: Decodable {
    let items: [FeedCardDTO]?
    let nextCursor: String?
    let hasMore: Bool?
}
