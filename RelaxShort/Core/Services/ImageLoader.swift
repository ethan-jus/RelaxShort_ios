import UIKit
import Combine
import ImageIO
import CryptoKit

// MARK: - ImageLoader

/// 异步图片加载器：内存缓存 + 磁盘缓存 + ImageIO 降采样。
///
/// 首页封面慢的两个主因在这里处理：
/// 1. 原图全尺寸解码导致内存压力与解码卡顿 —— 统一降采样到展示所需像素；
/// 2. 冷启动全部重新走网络 —— 降采样结果写入 Caches 磁盘缓存，跨启动复用。
///
/// 使用 actor 隔离内部状态，避免 NSLock 并发问题。
final class ImageLoader: ObservableObject, @unchecked Sendable {

    @Published var image: UIImage?
    @Published private(set) var imageKey: String?

    /// 全局封面内存缓存。Home 卡片加载过的封面，进入播放器后可直接复用，减少二次白屏。
    /// 降采样后单张成本约 1.7MB（660px 上限），500 张远低于 80MB 上限。
    private static let sharedCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    /// 封面卡片展示最大边不超过 ~220pt；@3x 下 660px 足够清晰。
    private static let maxPixelSize: CGFloat = 660

    private static let diskCache = CoverDiskCache()

    private let cache = ImageLoader.sharedCache
    private let state = ImageLoaderState()

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func load(_ url: URL) async { await loadImage(from: url) }
    func load(_ urlString: String) async {
        guard let url = Self.canonicalURL(from: urlString) else {
            await setImage(nil, key: nil)
            return
        }
        await loadImage(from: url)
    }

    /// URL(string:) 会把封面路径中的空格规范化为 %20；UI 必须使用同一个规范化 key 判断图片是否已加载。
    static func canonicalURLString(_ value: String) -> String? {
        canonicalURL(from: value)?.absoluteString
    }

    func cancel() {
        Task { await state.cancelAll() }
    }

    func refresh(_ url: URL) async {
        cache.removeObject(forKey: url.absoluteString as NSString)
        await Self.diskCache.remove(for: url.absoluteString)
        await loadImage(from: url)
    }

    /// 首页数据到达后后台预热首屏封面；已命中内存/磁盘缓存的自动跳过。
    static func prefetch(_ urlStrings: [String]) {
        Task.detached(priority: .utility) {
            for raw in urlStrings {
                guard !Task.isCancelled else { return }
                guard let url = canonicalURL(from: raw) else { continue }
                let key = url.absoluteString
                if sharedCache.object(forKey: key as NSString) != nil { continue }
                if await diskCache.cachedImage(for: key) != nil { continue }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      !Task.isCancelled,
                      let image = downsample(data: data) else { continue }
                sharedCache.setObject(image, forKey: key as NSString, cost: image.cacheCost)
                await diskCache.store(image, for: key)
            }
        }
    }

    // MARK: - Private

    private static func canonicalURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return nil
        }
        return url
    }

    /// ImageIO 降采样：不解码原图到内存，直接生成展示尺寸缩略图。
    static func downsample(data: Data, maxPixelSize: CGFloat = ImageLoader.maxPixelSize) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func loadImage(from url: URL) async {
        let key = url.absoluteString
        let cacheKey = key as NSString
        await clearIfNeeded(for: key)
        if let cached = cache.object(forKey: cacheKey) {
            await setImage(cached, key: key)
            return
        }
        if let task = await state.existingTask(for: key) {
            if let img = try? await task.value { await setImage(img, key: key) }
            else { await setImage(nil, key: key) }
            return
        }
        let task = Task<UIImage?, Error> {
            defer { Task { await state.removeTask(for: key) } }
            if let diskImage = await Self.diskCache.cachedImage(for: key) {
                cache.setObject(diskImage, forKey: cacheKey, cost: diskImage.cacheCost)
                return diskImage
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return nil }
            guard let img = Self.downsample(data: data) else { return nil }
            cache.setObject(img, forKey: cacheKey, cost: img.cacheCost)
            await Self.diskCache.store(img, for: key)
            return img
        }
        await state.registerTask(task, for: key)
        do {
            if let img = try await task.value { await setImage(img, key: key) }
            else { await setImage(nil, key: key) }
        } catch {
            guard !(error is CancellationError) else { return }
            await setImage(nil, key: key)
        }
    }

    @MainActor private func clearIfNeeded(for key: String) {
        guard imageKey != key else { return }
        image = nil
        imageKey = key
    }

    @MainActor private func setImage(_ img: UIImage?, key: String?) {
        image = img
        imageKey = key
    }

    @objc private func handleMemoryWarning() {
        cache.removeAllObjects()
        Task { await state.cancelAll() }
    }
}

// MARK: - Cover Disk Cache

/// 封面降采样结果的磁盘缓存；只存缩略图 JPEG，体积小、跨启动复用。
private actor CoverDiskCache {
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("CoverImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cachedImage(for key: String) -> UIImage? {
        guard let data = try? Data(contentsOf: file(for: key)) else { return nil }
        return UIImage(data: data)
    }

    func store(_ image: UIImage, for key: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: file(for: key), options: .atomic)
    }

    func remove(for key: String) {
        try? FileManager.default.removeItem(at: file(for: key))
    }

    private func file(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).jpg")
    }
}

// MARK: - Helpers

private extension UIImage {
    /// NSCache 成本：按实际像素字节数估算。
    var cacheCost: Int {
        guard let cgImage else { return 1 }
        return cgImage.width * cgImage.height * 4
    }
}

private actor ImageLoaderState {
    private var inflight: [String: Task<UIImage?, Error>] = [:]

    func existingTask(for key: String) -> Task<UIImage?, Error>? { inflight[key] }
    func registerTask(_ task: Task<UIImage?, Error>, for key: String) { inflight[key] = task }
    func removeTask(for key: String) { inflight.removeValue(forKey: key) }

    func cancelAll() {
        inflight.forEach { $0.value.cancel() }
        inflight.removeAll()
    }
}
