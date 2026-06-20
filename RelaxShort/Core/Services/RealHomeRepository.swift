import Foundation

// MARK: - Real Home Repository

/// 真实后端 HomeRepositoryProtocol 实现。
/// 首轮只接 For You；`fetchBanners` 暂返回空（后端无独立 banner 接口）。
@MainActor
final class RealHomeRepository: HomeRepositoryProtocol {

    private let client = APIClient.shared

    func fetchDramas(category: DramaCategory) async throws -> [DramaItem] {
        // 首轮忽略 category，统一走 forYou
        return try await fetchForYou()
    }

    func fetchBanners() async throws -> [BannerItem] {
        // Task12 Gap: 后端无独立 banner 接口，banner 在 Home 响应中，暂返回空
        return []
    }

    // MARK: - For You

    func fetchForYou(cursor: String? = nil, limit: Int = 10) async throws -> [DramaItem] {
        let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")

        let dto: ForYouFeedResponseDTO = try await client.requestData(
            .forYou(cursor: cursor, limit: limit,
                    contentLanguage: contentLang, countryCode: country)
        )
        return (dto.items ?? []).map(FeedCardDTOMapper.toDramaItem)
    }
}

// MARK: - FeedCardDTO → DramaItem 映射

enum FeedCardDTOMapper {
    /// 将后端 FeedCardDTO 映射为 iOS UI 模型 DramaItem。
    /// 后端暂缺的字段（view_count、category、region_tag、language_tag）给安全默认值，
    /// 标注来自 Task12 Gap，待后端补齐后移除。
    static func toDramaItem(from card: FeedCardDTO) -> DramaItem {
        DramaItem(
            id: String(card.seriesId),
            title: card.localizedTitle ?? "",
            coverURL: card.coverUrl ?? "",
            videoURL: card.playAsset?.hlsMasterUrl,
            category: card.tags?.first ?? "",
            tags: card.tags ?? [],
            viewCount: 0,               // Gap: 后端暂缺 view_count
            episodeCount: 0,            // 需从 series detail 接口获取
            currentEpisode: 0,
            synopsis: card.localizedSynopsis ?? "",
            isHot: false,
            isTrending: false,
            rating: 0,
            coinReward: 0,
            badgeText: nil,
            imageHeight: 168,
            badge: card.monetization?.vipRequired == true ? .vip : nil,
            regionTag: nil,             // Gap: 后端暂缺 region_tag (Task12 P1)
            languageTag: card.contentLanguage, // 近似替代 language_tag
            isFollowed: false,
            isBookmarked: false,
            isVIPOnly: card.monetization?.vipRequired ?? false,
            isComingSoon: false,
            coinPrice: card.monetization?.unlockCoinCost.flatMap { Int(truncating: $0 as NSNumber) },
            freeEpisodeRange: nil,      // Gap: 后端暂缺 free_episode_range (Task12 P2)
            isMemberOnly: false
        )
    }
}
