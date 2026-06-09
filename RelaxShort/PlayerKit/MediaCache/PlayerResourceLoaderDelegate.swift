import AVFoundation

// MARK: - 资源加载代理

/// AVAssetResourceLoaderDelegate：截获缓存 scheme 请求，优先返回缓存，未缓存时网络拉取并写入
final class PlayerResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    private let originalURL: URL; private let cache = HTTPRangeMediaCache.shared; private var session: URLSession?; private var tasks: [UUID: URLSessionDataTask] = [:]
    init(originalURL: URL) { self.originalURL = originalURL; super.init(); session = URLSession(configuration: .default) }

    func resourceLoader(_: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource r: AVAssetResourceLoadingRequest) -> Bool {
        guard let dr = r.dataRequest else { return false }
        let range = dr.requestedOffset...(dr.requestedOffset + Int64(dr.requestedLength) - 1)
        if let d = cache.cachedData(for: originalURL, range: range) { dr.respond(with: d); r.finishLoading(); return true }
        var req = URLRequest(url: originalURL); req.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        let t = session?.dataTask(with: req) { [weak self] d, resp, err in
            if let err { r.finishLoading(with: err); return }; guard let self, let d else { return }
            self.cache.write(data: d, for: self.originalURL, range: range, len: (resp as? HTTPURLResponse)?.expectedContentLength, mime: (resp as? HTTPURLResponse)?.mimeType)
            dr.respond(with: d); r.finishLoading()
        }; t?.resume(); return true
    }
    func resourceLoader(_: AVAssetResourceLoader, didCancel _: AVAssetResourceLoadingRequest) {}
}
