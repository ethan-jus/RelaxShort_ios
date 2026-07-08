import AVFoundation

// MARK: - 托管播放条目

/// 强持有 resourceLoaderDelegate，保证 MP4 缓存代理在 item 生命周期内不被释放
struct PlayerManagedItem {
    let item: AVPlayerItem
    let resourceLoaderDelegate: PlayerResourceLoaderDelegate?
}

// MARK: - 播放器 Item 工厂

enum PlayerItemFactory {
    private static let minimumPlayableLeadCacheBytes: Int64 = 1_048_576

    /// 创建 AVPlayerItem，MP4 走缓存 scheme + resourceLoaderDelegate
    static func makeManagedItem(from source: PlayerMediaSource) -> PlayerManagedItem {
        switch source {
        case .mp4(let url):
            let delegate = PlayerResourceLoaderDelegate(originalURL: url)
            let asset = AVURLAsset(url: url.withCacheScheme(), options: nil)
            asset.resourceLoader.setDelegate(delegate, queue: .global(qos: .utility))
            return PlayerManagedItem(item: AVPlayerItem(asset: asset), resourceLoaderDelegate: delegate)

        case .mp4WithExternalSubtitles(let videoURL, _):
            let delegate = PlayerResourceLoaderDelegate(originalURL: videoURL)
            let asset = AVURLAsset(url: videoURL.withCacheScheme(), options: nil)
            asset.resourceLoader.setDelegate(delegate, queue: .global(qos: .utility))
            return PlayerManagedItem(item: AVPlayerItem(asset: asset), resourceLoaderDelegate: delegate)

        case .mp4WithEmbeddedSubtitles(let url):
            let delegate = PlayerResourceLoaderDelegate(originalURL: url)
            let asset = AVURLAsset(url: url.withCacheScheme(), options: nil)
            asset.resourceLoader.setDelegate(delegate, queue: .global(qos: .utility))
            return PlayerManagedItem(item: AVPlayerItem(asset: asset), resourceLoaderDelegate: delegate)

        case .hls(let masterURL):
            return PlayerManagedItem(item: AVPlayerItem(url: masterURL), resourceLoaderDelegate: nil)
        case .hlsWithFallback(let masterURL, _):
            // HLS 优先，fallback URL 由 engine 在失败恢复时读取
            return PlayerManagedItem(item: AVPlayerItem(url: masterURL), resourceLoaderDelegate: nil)
        }
    }

    /// 创建主播放条目：MP4 一律直连，避免 relaxshort-cache:// 自定义 scheme 触发 CustomURLFlume 失败。
    /// Task24：旧 HTTP MP4 CDN 不支持通过 cache scheme 代理，强制直连保证首帧出画。
    /// 预加载仍通过 startWarmCache 提前下载首段到 HTTPRangeMediaCache，但不通过 scheme 代理播放。
    static func makePlaybackItem(from source: PlayerMediaSource) -> PlayerManagedItem {
        if let url = mp4URL(from: source) {
            let leadingBytes = HTTPRangeMediaCache.shared.leadingCachedBytes(for: url)
            print("[PlayerKit] makePlaybackItem source=\(sourceKind(source)) url=\(url.absoluteString) strategy=direct leading=\(leadingBytes)")
        }
        return makeDirectItem(from: source)
    }

    /// 创建直连播放条目：当前视频优先保证出画，缓存代理不能阻塞主播放链路
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
        if let url = mp4URL(from: source) {
            let leadingBytes = HTTPRangeMediaCache.shared.leadingCachedBytes(for: url)
            let mode = HTTPRangeMediaCache.shared.hasPlayableLeadCache(for: url, minimumBytes: minimumPlayableLeadCacheBytes)
                ? "cache-proxy"
                : "direct+warmed-cache"
            return "\(mode) lead=\(leadingBytes)"
        }
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

// MARK: - URL 缓存 Scheme 扩展

extension URL {
    /// 将 http/https URL 转换为缓存 scheme（relaxshort-cache://）
    func withCacheScheme() -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        comps.scheme = "relaxshort-cache"
        return comps.url ?? self
    }
}
