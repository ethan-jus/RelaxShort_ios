import Foundation

// MARK: - 播放器状态

/// 播放器播放状态（UI 以此为准，不直接读 AVPlayer 状态）
enum PlayerPlaybackState: Equatable {
    case idle
    case preparing
    case ready
    case playing
    case pausedByUser
    case pausedBySystem
    case waitingNetwork
    case stalled
    case recovering
    case failed(message: String?)
}

// MARK: - 暂停原因

/// 暂停原因：用户暂停禁止自动恢复，系统暂停允许自动续播
enum PlayerPauseReason: Equatable {
    case none
    case user
    case system
}

// MARK: - 字幕格式

enum PlayerSubtitleFormat: Hashable {
    case vtt
    case srt
}

// MARK: - 字幕轨道

struct PlayerSubtitleTrack: Identifiable, Hashable {
    let id: String
    let languageCode: String
    let displayName: String
    let url: URL
    let format: PlayerSubtitleFormat
    let isDefault: Bool
}

// MARK: - 媒体源

enum PlayerMediaSource: Hashable {
    /// MP4 无字幕（走缓存 delegate）
    case mp4(URL)
    /// MP4 + 外挂字幕
    case mp4WithExternalSubtitles(videoURL: URL, subtitles: [PlayerSubtitleTrack])
    /// MP4 内封字幕
    case mp4WithEmbeddedSubtitles(URL)
    /// HLS master playlist
    case hls(masterURL: URL)
    /// HLS + MP4 回退
    case hlsWithFallback(masterURL: URL, fallbackMP4URL: URL)
}

// MARK: - 清晰度选项

struct PlayerQualityOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let bitrate: Int?
}

// MARK: - 字幕选项

struct PlayerSubtitleOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let languageCode: String
}

// MARK: - 媒体条目

struct PlayerMediaItem: Identifiable, Hashable {
    let id: String
    let title: String
    let episodeNumber: Int?
    let coverURL: String
    let source: PlayerMediaSource
    let resumeTime: TimeInterval?
    /// 只有公开且已授权的媒体允许写入普通磁盘缓存。VIP 离线下载使用独立 DRM 流程。
    let allowsPersistentCache: Bool

    init(
        id: String,
        title: String,
        episodeNumber: Int?,
        coverURL: String,
        source: PlayerMediaSource,
        resumeTime: TimeInterval?,
        allowsPersistentCache: Bool = false
    ) {
        self.id = id
        self.title = title
        self.episodeNumber = episodeNumber
        self.coverURL = coverURL
        self.source = source
        self.resumeTime = resumeTime
        self.allowsPersistentCache = allowsPersistentCache
    }
}

// MARK: - 播放进度

struct PlayerProgress {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var bufferProgress: Double = 0
}

// MARK: - 播放诊断

struct PlayerDiagnostics: Equatable {
    var mediaID: String = "-"
    var sourceKind: String = "-"
    var playbackStrategy: String = "-"
    var preloadState: String = "-"
    var cacheSummary: String = "-"
    var ttffMs: Double = 0
    var moveTTFFMs: Double = 0
    var stateText: String = "-"
}

// MARK: - 播放器页面衔接上下文

struct PlayerHandoffContext: Hashable {
    let mediaID: String
    let dramaID: String?
    let episodeNumber: Int?
    let resumeTime: TimeInterval
    let duration: TimeInterval
    let wasPlaying: Bool
    let coverURL: String
    let createdAt: Date
}

// MARK: - 字幕 Cue

struct PlayerSubtitleCue: Sendable {
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}
