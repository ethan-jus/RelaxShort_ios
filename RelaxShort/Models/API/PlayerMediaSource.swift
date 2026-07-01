import Foundation

// MARK: - Player Media Source

/// iOS 播放器媒体源模型，表达后端播放接口返回的完整 HLS/MP4/字幕/缩略图信息。
/// 与现有单 URL `Episode.videoURL` 不同，此模型支持：
/// - HLS master playlist
/// - MP4 fallback
/// - 多清晰度 rendition
/// - 字幕轨
/// - 进度缩略图
struct PlaybackMediaSourceDTO {
    let sourceType: String            // hls / mp4 / hls_with_fallback
    let masterUrl: String?            // HLS master playlist
    let fallbackMp4Url: String?        // MP4 fallback URL
    let qualities: [QualityDTO]
    let subtitleTracks: [SubtitleDTO]
    let defaultSubtitleLanguage: String?
    let thumbnailTrack: ThumbnailDTO?
    let resumeTime: Int?

    init(
        sourceType: String,
        masterUrl: String?,
        fallbackMp4Url: String?,
        qualities: [QualityDTO] = [],
        subtitleTracks: [SubtitleDTO] = [],
        defaultSubtitleLanguage: String? = nil,
        thumbnailTrack: ThumbnailDTO? = nil,
        resumeTime: Int? = nil
    ) {
        self.sourceType = sourceType
        self.masterUrl = masterUrl
        self.fallbackMp4Url = fallbackMp4Url
        self.qualities = qualities
        self.subtitleTracks = subtitleTracks
        self.defaultSubtitleLanguage = defaultSubtitleLanguage
        self.thumbnailTrack = thumbnailTrack
        self.resumeTime = resumeTime
    }

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
        self.resumeTime = playResponse.resumeTime
    }

    /// 将播放接口 DTO 转换为 PlayerKit 的 `PlayerMediaSource` 枚举。
    func toPlayerMediaSource() -> PlayerMediaSource? {
        switch sourceType {
        case "hls_with_fallback":
            guard let hls = masterUrl,
                  let hlsURL = URL(string: hls),
                  let mp4 = fallbackMp4Url,
                  let mp4URL = URL(string: mp4) else {
                return fallbackMP4Source()
            }
            return .hlsWithFallback(masterURL: hlsURL, fallbackMP4URL: mp4URL)
        case "hls":
            guard let hls = masterUrl, let hlsURL = URL(string: hls) else {
                return fallbackMP4Source()
            }
            return .hls(masterURL: hlsURL)
        case "mp4":
            return fallbackMP4Source()
        default:
            guard let preferred = preferredPlaybackURL,
                  let url = URL(string: preferred) else { return nil }
            return .mp4(url)
        }
    }

    private func fallbackMP4Source() -> PlayerMediaSource? {
        guard let mp4 = fallbackMp4Url ?? qualities.first?.url,
              let mp4URL = URL(string: mp4) else { return nil }
        return .mp4(mp4URL)
    }
}
