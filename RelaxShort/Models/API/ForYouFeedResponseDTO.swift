import Foundation

enum FlexibleBoolDecoder {
    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "y"].contains(normalized) { return true }
            if ["false", "0", "no", "n"].contains(normalized) { return false }
        }
        return nil
    }
}

// MARK: - For You Feed Response DTO

/// 对应后端 `ForYouFeedResponse`（snake_case → JSONDecoder convertFromSnakeCase）
struct ForYouFeedResponseDTO: Decodable {
    let items: [FeedCardDTO]?
    let nextCursor: String?
    let hasMore: Bool?
    let matchedLanguage: String?
    let fallbackReason: String?
}

/// 对应后端 `FeedCardDto`
struct FeedCardDTO: Decodable {
    let seriesId: Int64
    let previewEpisodeId: Int64?
    let localizedTitle: String?
    let localizedSynopsis: String?
    let coverUrl: String?
    let horizontalCoverUrl: String?
    let displayFlags: [String]?
    let placementBadge: PlacementBadgeDTO?
    let tags: [String]?
    let playAsset: PlayAssetDTO?
    let monetization: MonetizationDTO?
    let contentLanguage: String?
    let matchedLanguage: String?
    let countryCode: String?
    let fallbackReason: String?
    /// Task14 后端已补齐的展示字段
    let viewCount: Int64?
    let category: String?
    let regionTag: String?
    let languageTag: String?
    let episodeCount: Int?
    let freeEpisodeRange: FreeEpisodeRangeDTO?
    let recommendationTraceId: String?
}

struct PlacementBadgeDTO: Decodable {
    let code: String
    let label: String?
    let tone: String?
}

/// 对应后端 `free_episode_range` {start, end}
struct FreeEpisodeRangeDTO: Decodable {
    let start: Int
    let end: Int
}

/// 对应后端 `monetization` Map
struct MonetizationDTO: Decodable {
    let isFree: Bool?
    let vipRequired: Bool?
    let unlockCoinCost: Decimal?

    private enum CodingKeys: String, CodingKey {
        case isFree
        case vipRequired
        case unlockCoinCost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isFree = FlexibleBoolDecoder.decode(container, forKey: .isFree)
        vipRequired = FlexibleBoolDecoder.decode(container, forKey: .vipRequired)
        unlockCoinCost = try container.decodeIfPresent(Decimal.self, forKey: .unlockCoinCost)
    }
}

/// 对应后端 `play_asset` Map（简版：仅含 master URL / fallback / qualities 摘要）
/// Task24 R2: 后端 feed 快照 play_asset_json 的 key 是 `hls` / `mp4_fallback`，
/// 但 convertFromSnakeCase 只把 mp4_fallback→mp4Fallback，不把 hls→hlsMasterUrl。
/// 这里显式兼容两类 key：后端 feed 快照的短 key（hls/mp4Fallback）与播放接口的标准 key（hlsMasterUrl/mp4FallbackUrl）。
struct PlayAssetDTO: Decodable {
    let hlsMasterUrl: String?
    let mp4FallbackUrl: String?
    let qualities: [QualityDTO]?
    let subtitles: [SubtitleDTO]?

    private enum CodingKeys: String, CodingKey {
        case hls
        case hlsMasterUrl
        case mp4Fallback
        case mp4FallbackUrl
        case qualities
        case subtitles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hlsMasterUrl = try container.decodeIfPresent(String.self, forKey: .hlsMasterUrl)
            ?? container.decodeIfPresent(String.self, forKey: .hls)
        mp4FallbackUrl = try container.decodeIfPresent(String.self, forKey: .mp4FallbackUrl)
            ?? container.decodeIfPresent(String.self, forKey: .mp4Fallback)
        qualities = try container.decodeIfPresent([QualityDTO].self, forKey: .qualities)
        subtitles = try container.decodeIfPresent([SubtitleDTO].self, forKey: .subtitles)
    }
}

struct QualityDTO: Decodable {
    let quality: String?
    let url: String?
    let width: Int?
    let height: Int?
    let bitrateKbps: Int?
    let codec: String?
    let fileSize: Int64?
    let vipRequired: Bool?

    private enum CodingKeys: String, CodingKey {
        case quality
        case url
        case width
        case height
        case bitrateKbps
        case codec
        case fileSize
        case vipRequired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quality = try container.decodeIfPresent(String.self, forKey: .quality)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        vipRequired = FlexibleBoolDecoder.decode(container, forKey: .vipRequired)
    }
}

struct SubtitleDTO: Decodable {
    let lang: String?
    let url: String?
    let type: String?
    let isDefault: Bool?
    let isAutoGenerated: Bool?

    private enum CodingKeys: String, CodingKey {
        case lang
        case url
        case type
        case isDefault
        case isAutoGenerated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lang = try container.decodeIfPresent(String.self, forKey: .lang)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        isDefault = FlexibleBoolDecoder.decode(container, forKey: .isDefault)
        isAutoGenerated = FlexibleBoolDecoder.decode(container, forKey: .isAutoGenerated)
    }
}
