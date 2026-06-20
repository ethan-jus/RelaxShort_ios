import Foundation

// MARK: - Real Home Repository

/// 真实后端 HomeRepositoryProtocol 实现。
/// Task15 扩展：支持 Home/Search/Ranking/Categories 真实 API。
/// `fetchBanners` 暂返回空（后端无独立 banner 接口）。
@MainActor
final class RealHomeRepository: HomeRepositoryProtocol {

    private let client = APIClient.shared

    func fetchDramas(category: DramaCategory) async throws -> [DramaItem] {
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")

        switch category {
        case .all:
            // .all：优先走 Home 首页首个有 items 的 section；解析失败 fallback 到 For You
            if let homeItems = try? await fetchHomeFirstSection(contentLang: contentLang, country: country),
               !homeItems.isEmpty {
                return homeItems
            }
            return try await fetchForYou(contentLang: contentLang, country: country)
        default:
            // 其他分类：通过 categories 接口匹配本地化名称或 code，再调 categorySeries
            // 当前后端分类 code 与 iOS DramaCategory 中文名无稳定映射，优先用 For You 降级
            // Gap: 分类 code 映射需后端提供完整 category 列表后可对齐
            return try await fetchForYou(contentLang: contentLang, country: country)
        }
    }

    func fetchBanners() async throws -> [BannerItem] {
        // 后端无独立 banner 接口，banner 在 Home 响应中，暂返回空
        return []
    }

    // MARK: - For You

    func fetchForYou(contentLang: String? = nil, country: String? = nil,
                     cursor: String? = nil, limit: Int = 10) async throws -> [DramaItem] {
        let lang = contentLang ?? UserDefaults.standard.string(forKey: "app_content_language")
        let cty = country ?? UserDefaults.standard.string(forKey: "app_country_code")
        let dto: ForYouFeedResponseDTO = try await client.requestData(
            .forYou(cursor: cursor, limit: limit, contentLanguage: lang, countryCode: cty)
        )
        return (dto.items ?? []).map(FeedCardDTOMapper.toDramaItem)
    }

    // MARK: - Home

    /// 解析 Home 首页第一个有 items 的 section
    private func fetchHomeFirstSection(contentLang: String?, country: String?) async throws -> [DramaItem]? {
        let dto: HomeResponseDTO = try await client.requestData(
            .home(contentLanguage: contentLang, countryCode: country)
        )
        guard let tabs = dto.tabs else { return nil }
        for tab in tabs {
            for section in tab.sections ?? [] {
                if let items = section.items, !items.isEmpty {
                    return items.map(FeedCardDTOMapper.toDramaItem)
                }
            }
        }
        return nil
    }

    // MARK: - Rankings

    func fetchRankings(type: String = "popular") async throws -> [DramaItem] {
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")
        let dto: RankingResponseDTO = try await client.requestData(
            .rankings(type: type, contentLanguage: contentLang, countryCode: country)
        )
        return (dto.items ?? []).map(FeedCardDTOMapper.toDramaItem)
    }

    // MARK: - Categories

    func fetchCategories() async throws -> [CategoryItemDTO] {
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")
        let dto: CategoriesResponseDTO = try await client.requestData(
            .categories(contentLanguage: contentLang, countryCode: country)
        )
        return dto.items ?? []
    }
}

// MARK: - DTOs

struct HomeResponseDTO: Decodable {
    let tabs: [TabDTO]?
    struct TabDTO: Decodable {
        let code: String?
        let sections: [SectionDTO]?
    }
    struct SectionDTO: Decodable {
        let code: String?
        let sectionType: String?
        let titleKey: String?
        let items: [FeedCardDTO]?
    }
}

struct RankingResponseDTO: Decodable {
    let items: [FeedCardDTO]?
}

struct CategoriesResponseDTO: Decodable {
    let items: [CategoryItemDTO]?
}

// MARK: - FeedCardDTO → DramaItem 映射

enum FeedCardDTOMapper {
    /// 将后端 FeedCardDTO 映射为 iOS UI 模型 DramaItem。
    /// Task14 后端已补齐 view_count/category/region_tag/language_tag/episode_count/free_episode_range。
    /// 字段缺失时给安全 fallback（兼容旧快照数据）。
    static func toDramaItem(from card: FeedCardDTO) -> DramaItem {
        let freeRange: ClosedRange<Int>? = {
            if let r = card.freeEpisodeRange { return r.start...r.end }
            return nil
        }()

        return DramaItem(
            id: String(card.seriesId),
            title: card.localizedTitle ?? "",
            coverURL: card.coverUrl ?? "",
            videoURL: card.playAsset?.hlsMasterUrl,
            category: card.category ?? card.tags?.first ?? "",
            tags: card.tags ?? [],
            viewCount: Int(card.viewCount ?? 0),
            episodeCount: card.episodeCount ?? 0,
            currentEpisode: 0,
            synopsis: card.localizedSynopsis ?? "",
            isHot: false,
            isTrending: false,
            rating: 0,
            coinReward: 0,
            badgeText: nil,
            imageHeight: 168,
            badge: card.monetization?.vipRequired == true ? .vip : nil,
            regionTag: card.regionTag,
            languageTag: card.languageTag ?? card.contentLanguage,
            isFollowed: false,
            isBookmarked: false,
            isVIPOnly: card.monetization?.vipRequired ?? false,
            isComingSoon: false,
            coinPrice: card.monetization?.unlockCoinCost.flatMap { Int(truncating: $0 as NSNumber) },
            freeEpisodeRange: freeRange,
            isMemberOnly: false
        )
    }
}
