import AVFoundation

// MARK: - 播放器 Item 工厂

enum PlayerItemFactory {
    /// 当前项和预加载项都使用 AVFoundation 原生直连条目。
    /// 相邻项的真实缓冲由共享 PlayerSlotPool 的 preroll 完成，不再维护一套播放器无法读取的旁路 Range 缓存。
    static func makePlaybackItem(from source: PlayerMediaSource) -> AVPlayerItem {
        return makeDirectItem(from: source)
    }

    /// 创建直连播放条目：当前视频优先保证出画，缓存代理不能阻塞主播放链路
    static func makeDirectItem(from source: PlayerMediaSource) -> AVPlayerItem {
        let url: URL
        switch source {
        case .mp4(let value), .mp4WithEmbeddedSubtitles(let value):
            url = value
        case .mp4WithExternalSubtitles(let videoURL, _):
            url = videoURL
        case .hls(let masterURL):
            url = masterURL
        case .hlsWithFallback(_, let fallbackMP4URL):
            // 当前播放链路优先 MP4 fallback，HLS 作为可恢复路径保留在 source 中。
            // 这样可以少一次 HLS master/segment 探测，提升短剧首帧速度。
            url = fallbackMP4URL
        }
        return AVPlayerItem(url: url)
    }

    static func mp4URL(from source: PlayerMediaSource) -> URL? {
        switch source {
        case .mp4(let url), .mp4WithEmbeddedSubtitles(let url):
            return url
        case .mp4WithExternalSubtitles(let videoURL, _):
            return videoURL
        case .hls, .hlsWithFallback:
            return nil
        }
    }

    static func hlsURL(from source: PlayerMediaSource) -> URL? {
        switch source {
        case .hls(let masterURL), .hlsWithFallback(let masterURL, _):
            return masterURL
        case .mp4, .mp4WithExternalSubtitles, .mp4WithEmbeddedSubtitles:
            return nil
        }
    }

    static func sourceKind(_ source: PlayerMediaSource) -> String {
        switch source {
        case .mp4:
            return "MP4"
        case .mp4WithExternalSubtitles:
            return "MP4+外挂字幕"
        case .mp4WithEmbeddedSubtitles:
            return "MP4+内封字幕"
        case .hls:
            return "HLS"
        case .hlsWithFallback:
            return "HLS+MP4 fallback"
        }
    }

    static func playbackStrategyDescription(for source: PlayerMediaSource) -> String {
        if mp4URL(from: source) != nil { return "native-direct-mp4" }
        if hlsURL(from: source) != nil {
            return "native-hls"
        }
        return "direct"
    }

    /// 读取内封字幕（异步）
    static func embeddedSubtitles(from asset: AVAsset) async -> [PlayerSubtitleOption] {
        guard let group = try? await asset.loadMediaSelectionGroup(for: .legible) else { return [] }
        return group.options.map {
            PlayerSubtitleOption(id: $0.displayName, displayName: $0.displayName, languageCode: $0.locale?.identifier ?? "")
        }
    }
}
