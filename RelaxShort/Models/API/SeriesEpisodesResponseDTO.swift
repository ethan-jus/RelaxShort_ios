import Foundation

// MARK: - Series Episodes Response DTO

/// 对应后端 `EpisodeListResponse`
struct SeriesEpisodesResponseDTO: Decodable {
    let seriesId: Int64
    let contentLanguage: String?
    let episodes: [EpisodeItemDTO]?
}

struct EpisodeItemDTO: Decodable {
    let episodeId: Int64
    let episodeNumber: Int
    let localizedTitle: String?
    let localizedSynopsis: String?
    let durationSeconds: Int?
    let isFree: Bool?
    let vipRequired: Bool?
    let unlocked: Bool?
    let unlockCoinCost: Decimal?
    let status: Int?

    private enum CodingKeys: String, CodingKey {
        case episodeId
        case episodeNumber
        case localizedTitle
        case localizedSynopsis
        case durationSeconds
        case isFree
        case vipRequired
        case unlocked
        case unlockCoinCost
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodeId = try container.decode(Int64.self, forKey: .episodeId)
        episodeNumber = try container.decode(Int.self, forKey: .episodeNumber)
        localizedTitle = try container.decodeIfPresent(String.self, forKey: .localizedTitle)
        localizedSynopsis = try container.decodeIfPresent(String.self, forKey: .localizedSynopsis)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        isFree = FlexibleBoolDecoder.decode(container, forKey: .isFree)
        vipRequired = FlexibleBoolDecoder.decode(container, forKey: .vipRequired)
        unlocked = FlexibleBoolDecoder.decode(container, forKey: .unlocked)
        unlockCoinCost = try container.decodeIfPresent(Decimal.self, forKey: .unlockCoinCost)
        status = try container.decodeIfPresent(Int.self, forKey: .status)
    }
}

// MARK: - Episode Play Response DTO

/// 对应后端 `EpisodePlayResponse`
struct EpisodePlayResponseDTO: Decodable {
    let episodeId: Int64
    let contentLanguage: String?
    let sourceType: String?          // hls / mp4 / hls_with_fallback
    let masterUrl: String?
    let fallbackMp4Url: String?
    let qualities: [QualityDTO]?
    let subtitleTracks: [SubtitleDTO]?
    let defaultSubtitleLanguage: String?
    let thumbnailTrack: ThumbnailDTO?
    let signedExpireAt: String?
    let resumeTime: Int?
    let cdnReadyStatus: Int?
    let assetVersion: Int?
}

struct ThumbnailDTO: Decodable {
    let spriteUrl: String?
    let width: Int?
    let height: Int?
    let columns: Int?
    let rows: Int?
    let intervalSeconds: Int?
}

struct EpisodeUnlockResponseDTO: Decodable {
    let unlocked: Bool
    let balanceAfter: Decimal?
}

struct ApplePaymentVerifyResponseDTO: Decodable {
    struct WalletSummaryDTO: Decodable {
        let balance: Decimal?
    }

    let status: String?
    let wallet: WalletSummaryDTO?
}

struct AppleAccountTokenResponseDTO: Decodable {
    let appAccountToken: String
}
