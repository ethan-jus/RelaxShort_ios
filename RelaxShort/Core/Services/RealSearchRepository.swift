import Foundation

// MARK: - Real Search Repository

/// 真实后端 SearchRepositoryProtocol 实现。
/// - `fetchDramas(category:)` 首版读取 `search/default` 的 `hot_series`。
/// - `fetchBanners()` 返回空（后端无独立 search banner）。
@MainActor
final class RealSearchRepository: SearchRepositoryProtocol {

    private let client = APIClient.shared

    func fetchDramas(category: DramaCategory) async throws -> [DramaItem] {
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")
        // 首版：用 search/default 的 hot_series 作为搜索发现候选数据
        let dto: SearchDefaultResponseDTO = try await client.requestData(
            .searchDefault(contentLanguage: contentLang, countryCode: country)
        )
        return (dto.hotSeries ?? []).map(FeedCardDTOMapper.toDramaItem)
    }

    func fetchBanners() async throws -> [BannerItem] {
        // 后端无独立 search banner，返回空
        return []
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
