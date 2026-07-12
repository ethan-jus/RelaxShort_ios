import AVFoundation

/// 强持有 resourceLoaderDelegate，保证缓存请求在 AVPlayerItem 生命周期内有效。
struct PlayerManagedItem {
    let item: AVPlayerItem
    let resourceLoaderDelegate: PlayerResourceLoaderDelegate?
}

// MARK: - 播放器 Item 工厂

enum PlayerItemFactory {
    /// 公开 MP4 使用资源加载代理，已读取的 Range 会被写入 2GB LRU 磁盘缓存。
    /// HLS 与受保护内容不走普通文件缓存。
    static func makePlaybackItem(from item: PlayerMediaItem) -> PlayerManagedItem {
        guard item.allowsPersistentCache,
              PlayerMediaCacheSettings.isEnabled,
              let url = mp4URL(from: item.source) else {
            return makeDirectItem(from: item.source)
        }
        let delegate = PlayerResourceLoaderDelegate(originalURL: url)
        let asset = AVURLAsset(url: url.withPlayerCacheScheme())
        asset.resourceLoader.setDelegate(delegate, queue: .global(qos: .utility))
        return PlayerManagedItem(item: AVPlayerItem(asset: asset), resourceLoaderDelegate: delegate)
    }

    static func makeDirectItem(from source: PlayerMediaSource) -> PlayerManagedItem {
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
        return PlayerManagedItem(item: AVPlayerItem(url: url), resourceLoaderDelegate: nil)
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

private extension URL {
    func withPlayerCacheScheme() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.scheme = "relaxshort-cache"
        return components.url ?? self
    }
}
