import Foundation

// MARK: - Real Home Repository

/// 真实后端 HomeRepositoryProtocol 实现。
/// Task15 扩展：支持 Home/Search/Ranking/Categories 真实 API。
/// `fetchBanners` 暂返回空（后端无独立 banner 接口）。
@MainActor
final class RealHomeRepository: HomeRepositoryProtocol {

    let usesRemoteContentCatalog = true

    private let client = APIClient.shared

    func fetchDramas(category: DramaCategory) async throws -> [DramaItem] {
        let country = ContentLanguagePreference.countryCode
        let categoryCode: String?
        switch category {
        case .all:
            categoryCode = nil
        default:
            let categories = try await fetchHomeCategories()
            categoryCode = categories.first {
                $0.title.localizedCaseInsensitiveCompare(category.rawValue) == .orderedSame
            }?.code
            guard categoryCode != nil else { return [] }
        }

        let page = try await fetchCatalogSeries(
            categoryCode: categoryCode,
            contentLanguage: ContentLanguagePreference.effectiveLanguage,
            country: country,
            cursor: nil,
            limit: 20
        )
        return page.items
    }

    func fetchBanners() async throws -> [BannerItem] {
        // 后端无独立 banner 接口，banner 在 Home 响应中，暂返回空
        return []
    }

    func fetchCatalogSeries(
        categoryCode: String?,
        contentLanguage: String?,
        country: String?,
        cursor: String?,
        limit: Int
    ) async throws -> (items: [DramaItem], nextCursor: String?, hasMore: Bool) {
        let pageSize = max(1, min(limit, 30))
        let dto: SearchResponseDTO = try await client.requestData(
            .catalogSeries(
                categoryCode: categoryCode,
                contentLanguage: contentLanguage,
                countryCode: country,
                cursor: cursor,
                limit: pageSize
            )
        )
        var seenSeriesIDs = Set<String>()
        let items = (dto.items ?? [])
            .map(FeedCardDTOMapper.toDramaItem)
            .filter { seenSeriesIDs.insert($0.id).inserted }
        return (
            items: items,
            nextCursor: dto.nextCursor,
            hasMore: dto.hasMore ?? false
        )
    }

    // MARK: - For You

    /// Task36A: 支持 feedSeed 和游标分页的 For You 请求。
    /// 首次调用传入 feedSeed，后续翻页传入 cursor（含 seedHash），同一 session 内翻页稳定。
    func fetchForYouPaginated(contentLang: String? = nil, country: String? = nil,
                               cursor: String? = nil, limit: Int = 10,
                               feedSeed: String? = nil) async throws -> (
        items: [DramaItem], nextCursor: String?, hasMore: Bool
    ) {
        let lang = contentLang ?? ContentLanguagePreference.effectiveLanguage
        let cty = country ?? ContentLanguagePreference.countryCode
        let dto: ForYouFeedResponseDTO = try await client.requestData(
            .forYou(cursor: cursor, limit: limit, contentLanguage: lang, countryCode: cty,
                    feedSeed: feedSeed, strictContentLanguage: true)
        )
        return (
            items: (dto.items ?? []).map(FeedCardDTOMapper.toDramaItem),
            nextCursor: dto.nextCursor,
            hasMore: dto.hasMore ?? false
        )
    }

    func fetchForYou(contentLang: String? = nil, country: String? = nil,
                     cursor: String? = nil, limit: Int = 10,
                     strictContentLanguage: Bool = false) async throws -> [DramaItem] {
        if strictContentLanguage {
            let lang = contentLang ?? ContentLanguagePreference.effectiveLanguage
            let cty = country ?? ContentLanguagePreference.countryCode
            let dto: ForYouFeedResponseDTO = try await client.requestData(
                .forYou(cursor: cursor, limit: limit, contentLanguage: lang, countryCode: cty,
                        feedSeed: nil, strictContentLanguage: true)
            )
            return (dto.items ?? []).map(FeedCardDTOMapper.toDramaItem)
        }

        let result = try await fetchForYouPaginated(
            contentLang: contentLang, country: country, cursor: cursor, limit: limit, feedSeed: nil
        )
        return result.items
    }

    // MARK: - Categories

    func fetchHomeCategories() async throws -> [HomeCategory] {
        // 分类目录默认跨内容语言；名称由实时 X-App-Language 请求头本地化。
        let country = ContentLanguagePreference.countryCode
        let dto: CategoriesResponseDTO = try await client.requestData(
            .categories(contentLanguage: nil, countryCode: country)
        )
        return (dto.items ?? []).map { item in
            HomeCategory(
                id: item.code ?? "",
                code: item.code ?? "",
                title: item.localizedName ?? item.code ?? "",
                localCategory: nil
            )
        }
    }

    // MARK: - Rankings (R4B-1: 返回 RankingEntry 领域模型)

    func fetchRankingEntries(type: String) async throws -> [RankingEntry] {
        let contentLang = ContentLanguagePreference.effectiveLanguage
        let country = ContentLanguagePreference.countryCode
        let dto: RankingResponseDTO = try await client.requestData(
            .rankings(type: type, contentLanguage: contentLang, countryCode: country)
        )
        return dto.items.map {
            RankingEntry(
                rankPosition: $0.rankPosition,
                metricType: $0.metricType,
                metricValue: $0.metricValue,
                drama: FeedCardDTOMapper.toDramaItem(from: $0.card)
            )
        }
    }

    // MARK: - Categories

    func fetchCategories() async throws -> [CategoryItemDTO] {
        let country = ContentLanguagePreference.countryCode
        let dto: CategoriesResponseDTO = try await client.requestData(
            .categories(contentLanguage: nil, countryCode: country)
        )
        return dto.items ?? []
    }

    func fetchSupportedLanguages() async throws -> [HomeContentLanguage] {
        let items: [SupportedLanguageDTO] = try await client.requestData(.languages)
        return items.map {
            HomeContentLanguage(
                code: $0.code,
                nameEn: $0.nameEn ?? "",
                nameNative: $0.nameNative ?? "",
                localizedName: $0.localizedName ?? ""
            )
        }
    }
}

// MARK: - Home Section Models

struct HomeSectionContent: Identifiable {
    let id: String
    let code: String
    let sectionType: String?
    let titleKey: String?
    let items: [DramaItem]
}

struct HomeTabContent {
    let code: String
    let sections: [HomeSectionContent]
}

extension RealHomeRepository {
    func fetchHomeTabs(contentLang: String?, country: String?) async throws -> [HomeTabContent] {
        let lang = contentLang ?? ContentLanguagePreference.effectiveLanguage
        let cty = country ?? ContentLanguagePreference.countryCode
        let dto: HomeResponseDTO = try await client.requestData(
            .home(contentLanguage: lang, countryCode: cty)
        )
        guard let tabs = dto.tabs else { return [] }
        return tabs.compactMap { tab in
            guard let code = tab.code else { return nil }
            let sections: [HomeSectionContent] = (tab.sections ?? []).compactMap { sec in
                guard let secCode = sec.code else { return nil }
                let items = (sec.items ?? []).map(FeedCardDTOMapper.toDramaItem)
                return HomeSectionContent(
                    id: secCode,
                    code: secCode,
                    sectionType: sec.sectionType,
                    titleKey: sec.titleKey,
                    items: items
                )
            }
            return HomeTabContent(code: code, sections: sections)
        }
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

        // HLS 分段更适合移动网络快速首播和自适应码率；旧内容缺 HLS 时才回退 MP4。
        let resolvedVideoURL = card.playAsset?.standardHlsMasterUrl
            ?? card.playAsset?.hlsMasterUrl
            ?? card.playAsset?.mp4FallbackUrl

        var item = DramaItem(
            id: String(card.seriesId),
            title: card.localizedTitle ?? "",
            coverURL: card.coverUrl ?? "",
            videoURL: resolvedVideoURL,
            previewEpisodeID: card.previewEpisodeId.map(String.init),
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
            isPublicPreview: card.monetization?.isFree == true
                && card.monetization?.vipRequired != true,
            isComingSoon: false,
            coinPrice: card.monetization?.unlockCoinCost.flatMap { Int(truncating: $0 as NSNumber) },
            freeEpisodeRange: freeRange,
            isMemberOnly: false
        )
        item.bannerCoverURL = card.horizontalCoverUrl
        item.categoryCode = card.categoryCode
        item.contentFormat = card.contentFormat.flatMap(ContentFormat.init(rawValue:))
        item.productionMethod = card.productionMethod.flatMap(ProductionMethod.init(rawValue:))
        item.displayFlags = card.displayFlags ?? []
        item.placementBadge = card.placementBadge.map {
            PlacementBadge(
                code: $0.code,
                label: $0.label ?? $0.code,
                tone: PlacementBadgeTone(rawValue: $0.tone ?? "") ?? .neutral
            )
        }
        return item
    }
}
