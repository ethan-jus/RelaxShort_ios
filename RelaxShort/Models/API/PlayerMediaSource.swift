import Foundation

// MARK: - Player Media Source

/// iOS 播放器媒体源模型，表达后端播放接口返回的完整 HLS/MP4/字幕/缩略图信息。
/// 与现有单 URL `Episode.videoURL` 不同，此模型支持：
/// - HLS master playlist
/// - MP4 fallback
/// - 多清晰度 rendition
/// - 字幕轨
/// - 进度缩略图
struct PlayerMediaSource {
    let sourceType: String            // hls / mp4 / hls_with_fallback
    let masterUrl: String?            // HLS master playlist
    let fallbackMp4Url: String?        // MP4 fallback URL
    let qualities: [QualityDTO]
    let subtitleTracks: [SubtitleDTO]
    let defaultSubtitleLanguage: String?
    let thumbnailTrack: ThumbnailDTO?

    /// 兼容现有 `VideoPlayerView` 的推荐播放地址：HLS > MP4 fallback > 首个清晰度
    var preferredPlaybackURL: String? {
        if let hls = masterUrl, !hls.isEmpty { return hls }
        if let mp4 = fallbackMp4Url, !mp4.isEmpty { return mp4 }
        return qualities.first?.url
    }

    init(from playResponse: EpisodePlayResponseDTO) {
        self.sourceType = playResponse.sourceType ?? "hls"
        self.masterUrl = playResponse.masterUrl
        self.fallbackMp4Url = playResponse.fallbackMp4Url
        self.qualities = playResponse.qualities ?? []
        self.subtitleTracks = playResponse.subtitleTracks ?? []
        self.defaultSubtitleLanguage = playResponse.defaultSubtitleLanguage
        self.thumbnailTrack = playResponse.thumbnailTrack
    }
}
