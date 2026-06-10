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
    private let lock = NSLock()

    init(originalURL: URL) {
        self.originalURL = originalURL
        super.init()
        session = URLSession(configuration: .default)
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
        let upper = lower + Int64(dataRequest.requestedLength) - 1
        let range = lower...upper

        // 缓存命中
        if let result = cache.cachedData(for: originalURL, range: range) {
            let summary = cache.debugSummary(for: originalURL)
            print("[PlayerKit] cache hit url=\(originalURL.lastPathComponent) range=\(lower)-\(upper) source=\(result.source.rawValue) \(summary)")
            fillContentInfo(
                loadingRequest.contentInformationRequest,
                response: nil,
                totalLength: nil
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
                ?? httpResponse?.expectedContentLength

            self.fillContentInfo(
                loadingRequest.contentInformationRequest,
                response: httpResponse,
                totalLength: totalLength
            )

            self.cache.write(
                data: data,
                for: self.originalURL,
                range: range,
                len: totalLength,
                mime: httpResponse?.mimeType
            )

            dataRequest.respond(with: data)
            loadingRequest.finishLoading()
        }

        if let task {
            lock.lock()
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
        totalLength: Int64?
    ) {
        guard let info else { return }
        info.isByteRangeAccessSupported = true
        info.contentType = UTType(filenameExtension: originalURL.pathExtension)?.identifier
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
}
