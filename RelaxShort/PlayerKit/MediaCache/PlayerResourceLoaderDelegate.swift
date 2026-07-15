import AVFoundation
import UniformTypeIdentifiers

// MARK: - 资源加载代理

/// AVAssetResourceLoaderDelegate：MP4 cache scheme 代理
/// 填充 contentInformationRequest，支持 byte range，didCancel 取消 task，deinit 清理
final class PlayerResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    private let originalURL: URL
    private let cache = HTTPRangeMediaCache.shared
    private var session: URLSession?
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private var requestPriority: Float
    private let lock = NSLock()

    init(originalURL: URL, requestPriority: Float = URLSessionTask.defaultPriority) {
        self.originalURL = originalURL
        self.requestPriority = requestPriority
        super.init()
        session = URLSession(configuration: .default)
    }

    /// 相邻预加载升为当前播放时，正在进行的 Range 请求同步提升优先级。
    func promoteToPlaybackPriority() {
        lock.lock()
        requestPriority = PlayerPreloadPolicy.playbackNetworkPriority
        let currentTasks = Array(tasks.values)
        lock.unlock()
        currentTasks.forEach { $0.priority = PlayerPreloadPolicy.playbackNetworkPriority }
    }

    deinit {
        lock.lock()
        let currentTasks = tasks.values
        tasks.removeAll()
        lock.unlock()
        currentTasks.forEach { $0.cancel() }
        session?.invalidateAndCancel()
    }

    // MARK: - 加载请求

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let dataRequest = loadingRequest.dataRequest else { return false }

        let lower = dataRequest.requestedOffset
        guard dataRequest.requestedLength > 0 else {
            loadingRequest.finishLoading()
            return true
        }
        let upper = lower + Int64(dataRequest.requestedLength) - 1
        let range = lower...upper

        // 缓存命中
        if let result = cache.cachedData(for: originalURL, range: range) {
            let summary = cache.debugSummary(for: originalURL)
            let metadata = cache.metadata(for: originalURL)
            print("[PlayerKit] cache hit url=\(originalURL.lastPathComponent) range=\(lower)-\(upper) source=\(result.source.rawValue) \(summary)")
            fillContentInfo(
                loadingRequest.contentInformationRequest,
                response: nil,
                totalLength: metadata.len,
                mimeType: metadata.mime
            )
            dataRequest.respond(with: result.data)
            loadingRequest.finishLoading()
            return true
        }
        let summary = cache.debugSummary(for: originalURL)
        print("[PlayerKit] cache miss url=\(originalURL.lastPathComponent) range=\(lower)-\(upper) \(summary)")

        // 网络请求
        var request = URLRequest(url: originalURL)
        request.setValue(
            "bytes=\(range.lowerBound)-\(range.upperBound)",
            forHTTPHeaderField: "Range"
        )

        let key = ObjectIdentifier(loadingRequest)
        let task = session?.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            defer {
                self.lock.lock()
                self.tasks.removeValue(forKey: key)
                self.lock.unlock()
            }

            if let error {
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let data else {
                loadingRequest.finishLoading(
                    with: NSError(domain: "PlayerResourceLoader", code: -1)
                )
                return
            }

            let httpResponse = response as? HTTPURLResponse
            let totalLength = self.totalLength(from: httpResponse)
                ?? (httpResponse?.expectedContentLength).flatMap { $0 > 0 ? $0 : nil }

            let responseRange: ClosedRange<Int64>
            let responseData: Data
            if httpResponse?.statusCode == 206 {
                guard let parsedRange = self.contentRange(from: httpResponse),
                      parsedRange.upperBound - parsedRange.lowerBound + 1 == Int64(data.count) else {
                    loadingRequest.finishLoading(
                        with: NSError(domain: "PlayerResourceLoader", code: -2)
                    )
                    return
                }
                responseRange = parsedRange
                responseData = data
            } else if httpResponse?.statusCode == 200 {
                let fullRange: ClosedRange<Int64> = 0...Int64(data.count - 1)
                guard fullRange.lowerBound <= range.lowerBound,
                      fullRange.upperBound >= range.upperBound else {
                    loadingRequest.finishLoading(
                        with: NSError(domain: "PlayerResourceLoader", code: -3)
                    )
                    return
                }
                responseRange = fullRange
                let start = Int(range.lowerBound)
                let end = Int(range.upperBound) + 1
                responseData = data.subdata(in: start..<end)
            } else {
                loadingRequest.finishLoading(
                    with: NSError(domain: "PlayerResourceLoader", code: httpResponse?.statusCode ?? -4)
                )
                return
            }

            self.fillContentInfo(
                loadingRequest.contentInformationRequest,
                response: httpResponse,
                totalLength: totalLength,
                mimeType: httpResponse?.mimeType
            )

            self.cache.write(
                data: data,
                for: self.originalURL,
                range: responseRange,
                len: totalLength,
                mime: httpResponse?.mimeType
            )

            dataRequest.respond(with: responseData)
            loadingRequest.finishLoading()
        }

        if let task {
            lock.lock()
            task.priority = requestPriority
            tasks[key] = task
            lock.unlock()
            task.resume()
        }

        return true
    }

    // MARK: - 取消

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let key = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: key)
        lock.unlock()
        task?.cancel()
    }

    // MARK: - 私有辅助

    private func fillContentInfo(
        _ info: AVAssetResourceLoadingContentInformationRequest?,
        response: HTTPURLResponse?,
        totalLength: Int64?,
        mimeType: String? = nil
    ) {
        guard let info else { return }
        info.isByteRangeAccessSupported = true
        info.contentType = mimeType.flatMap { UTType(mimeType: $0)?.identifier }
            ?? UTType(filenameExtension: originalURL.pathExtension)?.identifier
            ?? UTType.mpeg4Movie.identifier
        if let totalLength, totalLength > 0 {
            info.contentLength = totalLength
        }
    }

    private func totalLength(from response: HTTPURLResponse?) -> Int64? {
        guard let contentRange = response?.value(forHTTPHeaderField: "Content-Range"),
              let slashIndex = contentRange.lastIndex(of: "/") else {
            return nil
        }
        return Int64(contentRange[contentRange.index(after: slashIndex)...])
    }

    private func contentRange(from response: HTTPURLResponse?) -> ClosedRange<Int64>? {
        guard let contentRange = response?.value(forHTTPHeaderField: "Content-Range") else {
            return nil
        }
        let parts = contentRange.components(separatedBy: "/")
        guard let byteRange = parts.first?.replacingOccurrences(of: "bytes ", with: ""),
              let dashIndex = byteRange.firstIndex(of: "-"),
              let lower = Int64(byteRange[..<dashIndex]),
              let upper = Int64(byteRange[byteRange.index(after: dashIndex)...]),
              upper >= lower else {
            return nil
        }
        return lower...upper
    }
}
