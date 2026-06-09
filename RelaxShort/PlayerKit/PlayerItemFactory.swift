import AVFoundation

// MARK: - 托管播放条目

/// 强持有 resourceLoaderDelegate，保证 MP4 缓存代理在 item 生命周期内不被释放
struct PlayerManagedItem {
    let item: AVPlayerItem
    let resourceLoaderDelegate: PlayerResourceLoaderDelegate?
}

// MARK: - 播放器 Item 工厂

enum PlayerItemFactory {

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
        case .hlsWithFallback(let masterURL, let fallbackMP4URL):
            // HLS 优先，携带 fallbackURL 备用（由 engine tryDirectFallback 使用）
            return PlayerManagedItem(item: AVPlayerItem(url: masterURL), resourceLoaderDelegate: nil)
        }
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
