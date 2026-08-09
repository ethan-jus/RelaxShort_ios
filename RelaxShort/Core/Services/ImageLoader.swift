import UIKit
import Combine

// MARK: - ImageLoader

/// 异步图片加载器，内置内存缓存。
/// 使用 actor 隔离内部状态，避免 NSLock 并发问题。

final class ImageLoader: ObservableObject, @unchecked Sendable {

    @Published var image: UIImage?
    @Published private(set) var imageKey: String?

    /// 全局封面内存缓存。Home 卡片加载过的封面，进入播放器后可直接复用，减少二次白屏。
    private static let sharedCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

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
        await loadImage(from: url)
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
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return nil }
            guard let img = UIImage(data: data) else { return nil }
            let cost = Int(img.size.width * img.size.height * 4)
            cache.setObject(img, forKey: cacheKey, cost: cost)
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

// MARK: - Internal State Actor

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
