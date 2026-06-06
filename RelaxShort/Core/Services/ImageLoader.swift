import UIKit
import Combine

// MARK: - ImageLoader

/// 异步图片加载器，内置内存缓存。
/// 使用 actor 隔离内部状态，避免 NSLock 并发问题。

final class ImageLoader: ObservableObject, @unchecked Sendable {

    @Published var image: UIImage?

    private let cache = NSCache<NSString, UIImage>()
    private let state = ImageLoaderState()

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func load(_ url: URL) async { await loadImage(from: url) }
    func load(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        await loadImage(from: url)
    }

    func cancel() {
        Task { await state.cancelAll() }
    }

    func refresh(_ url: URL) async {
        cache.removeObject(forKey: url.absoluteString as NSString)
        await loadImage(from: url)
    }

    // MARK: - Private

    private func loadImage(from url: URL) async {
        let cacheKey = url.absoluteString as NSString
        if let cached = cache.object(forKey: cacheKey) {
            await setImage(cached)
            return
        }
        if let task = await state.existingTask(for: url.absoluteString) {
            if let img = try? await task.value { await setImage(img) }
            else { await setImage(nil) }
            return
        }
        let task = Task<UIImage?, Error> {
            defer { Task { await state.removeTask(for: url.absoluteString) } }
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return nil }
            guard let img = UIImage(data: data) else { return nil }
            let cost = Int(img.size.width * img.size.height * 4)
            cache.setObject(img, forKey: cacheKey, cost: cost)
            return img
        }
        await state.registerTask(task, for: url.absoluteString)
        do {
            if let img = try await task.value { await setImage(img) }
            else { await setImage(nil) }
        } catch {
            guard !(error is CancellationError) else { return }
            await setImage(nil)
        }
    }

    @MainActor private func setImage(_ img: UIImage?) { image = img }

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
