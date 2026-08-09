import Foundation

// MARK: - Media Preview Prefetcher

/// 首页视频首播预热：把头部卡片的预览 MP4 起始字节提前写入共享播放缓存。
///
/// 点进播放页时 PlayerResourceLoaderDelegate 的 Range 请求直接命中磁盘缓存，
/// 省掉冷启动时 CDN 首包往返，缩短首帧等待。只预热前几个公开预览卡片，
/// 后台 utility 优先级执行，失败静默放弃，不影响任何正常播放路径。
enum MediaPreviewPrefetcher {
    /// 约覆盖 MP4 头部与前几秒媒体数据。
    private static let leadBytes: Int64 = 1_500_000
    private static let cache = HTTPRangeMediaCache.shared

    static func prefetch(urls: [URL], maxCount: Int = 6) {
        let targets = Array(urls.prefix(maxCount))
        guard !targets.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in targets {
                guard !Task.isCancelled else { return }
                await prefetchLead(url)
            }
        }
    }

    private static func prefetchLead(_ url: URL) async {
        // 已有足够头部缓存时跳过；阈值放宽到一半，避免重复小流量回源。
        if cache.hasPlayableLeadCache(for: url, minimumBytes: leadBytes / 2) { return }

        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(leadBytes - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, !data.isEmpty else { return }
            // 只接受 206：源站忽略 Range 返回 200 时放弃预热，避免后台整文件下载。
            guard let http = response as? HTTPURLResponse, http.statusCode == 206 else { return }
            cache.write(
                data: data,
                for: url,
                range: 0...Int64(data.count - 1),
                len: totalLength(from: http),
                mime: http.mimeType ?? http.value(forHTTPHeaderField: "Content-Type")
            )
        } catch {
            return
        }
    }

    /// 从 Content-Range（形如 bytes 0-1499999/31234567）解析文件总长度。
    private static func totalLength(from response: HTTPURLResponse) -> Int64? {
        guard let contentRange = response.value(forHTTPHeaderField: "Content-Range") else { return nil }
        return Int64(contentRange.components(separatedBy: "/").last ?? "")
    }
}
