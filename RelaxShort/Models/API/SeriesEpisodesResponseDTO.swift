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
    let unlockCoinCost: Decimal?
    let status: Int?
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
