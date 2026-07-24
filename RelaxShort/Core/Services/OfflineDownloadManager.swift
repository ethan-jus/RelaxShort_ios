import Combine
import Foundation

enum OfflineDownloadStatus: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

struct OfflineDownloadItem: Identifiable, Codable, Hashable {
    let id: UUID
    let dramaID: String
    let episodeID: String
    let dramaTitle: String
    let coverURL: String
    let episodeNumber: Int
    let totalEpisodes: Int
    let remoteURL: URL
    let createdAt: Date
    var updatedAt: Date
    var status: OfflineDownloadStatus
    var progress: Double
    var downloadedBytes: Int64
    var totalBytes: Int64?
    var bytesPerSecond: Int64
    var localFileName: String?
    var resumeFileName: String?
    var errorMessage: String?

    var isActive: Bool {
        status == .queued || status == .downloading || status == .paused
    }
}

struct OfflineDownloadRequest {
    let dramaID: String
    let episodeID: String
    let dramaTitle: String
    let coverURL: String
    let episodeNumber: Int
    let totalEpisodes: Int
    let remoteURL: URL
    let isProtected: Bool
}

enum OfflineDownloadStartError: LocalizedError {
    case protectedAssetUnavailable
    case duplicate
    case storageFull
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .protectedAssetUnavailable:
            return "downloads.error.protected_unavailable".localized
        case .duplicate:
            return "downloads.error.duplicate".localized
        case .storageFull:
            return "downloads.error.storage_full".localized
        case .invalidURL:
            return "downloads.error.invalid_url".localized
        }
    }
}

/// 公开视频离线下载队列。
///
/// 受保护内容必须等待后端提供 FairPlay 离线合同，禁止把 VIP/付费 MP4
/// 直接写入这个普通文件目录。
final class OfflineDownloadManager: NSObject, ObservableObject {
    static let shared = OfflineDownloadManager()
    static let maximumBytes: Int64 = 8 * 1024 * 1024 * 1024
    static let sessionIdentifier = "com.relaxshort.ios.offline-downloads"

    @Published private(set) var items: [OfflineDownloadItem] = []

    var backgroundSessionCompletionHandler: (() -> Void)?

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let metadataURL: URL
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var lastProgressSamples: [UUID: (date: Date, bytes: Int64)] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = UserDefaults.standard.bool(
            forKey: "offlineDownloadsCellularEnabled"
        )
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: .main
        )
    }()

    override private init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let root = applicationSupport.appendingPathComponent(
            "OfflineDownloads",
            isDirectory: true
        )
        rootURL = root
        metadataURL = root.appendingPathComponent("downloads.json")
        super.init()

        try? fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        markDirectoryExcludedFromBackup()

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-OfflineDownloadUIPreview") {
            items = Self.previewItems
            return
        }
#endif

        load()
        restoreBackgroundTasks()
    }

    var usedBytes: Int64 {
        items.reduce(0) { partial, item in
            partial + max(0, item.downloadedBytes)
        }
    }

    var availableBytes: Int64 {
        max(0, Self.maximumBytes - usedBytes)
    }

    var storageFraction: Double {
        min(1, Double(usedBytes) / Double(Self.maximumBytes))
    }

    var activeItems: [OfflineDownloadItem] {
        items
            .filter(\.isActive)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var completedItems: [OfflineDownloadItem] {
        items
            .filter { $0.status == .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func item(episodeID: String) -> OfflineDownloadItem? {
        items.first { $0.episodeID == episodeID }
    }

    func enqueue(_ request: OfflineDownloadRequest) throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !request.isProtected else {
            throw OfflineDownloadStartError.protectedAssetUnavailable
        }
        guard ["http", "https"].contains(request.remoteURL.scheme?.lowercased() ?? "") else {
            throw OfflineDownloadStartError.invalidURL
        }
        guard item(episodeID: request.episodeID) == nil else {
            throw OfflineDownloadStartError.duplicate
        }
        guard availableBytes > 0 else {
            throw OfflineDownloadStartError.storageFull
        }

        let item = OfflineDownloadItem(
            id: UUID(),
            dramaID: request.dramaID,
            episodeID: request.episodeID,
            dramaTitle: request.dramaTitle,
            coverURL: request.coverURL,
            episodeNumber: request.episodeNumber,
            totalEpisodes: request.totalEpisodes,
            remoteURL: request.remoteURL,
            createdAt: Date(),
            updatedAt: Date(),
            status: .queued,
            progress: 0,
            downloadedBytes: 0,
            totalBytes: nil,
            bytesPerSecond: 0,
            localFileName: nil,
            resumeFileName: nil,
            errorMessage: nil
        )
        items.insert(item, at: 0)
        persist()
        startTask(for: item.id, resumeData: nil)
    }

    func togglePause(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        switch item.status {
        case .downloading, .queued:
            pause(id)
        case .paused, .failed:
            resume(id)
        case .completed:
            break
        }
    }

    func pauseAll() {
        for item in activeItems where item.status != .paused {
            pause(item.id)
        }
    }

    func pause(_ id: UUID) {
#if DEBUG
        if isPreviewMode {
            update(id) {
                $0.status = .paused
                $0.bytesPerSecond = 0
            }
            return
        }
#endif
        guard let task = tasks[id] else { return }
        update(id) {
            $0.status = .paused
            $0.bytesPerSecond = 0
        }
        task.cancel { [weak self] data in
            guard let self, let data else { return }
            DispatchQueue.main.async {
                let fileName = "resume-\(id.uuidString).data"
                let url = self.rootURL.appendingPathComponent(fileName)
                do {
                    try data.write(to: url, options: .atomic)
                    self.update(id) { $0.resumeFileName = fileName }
                } catch {
                    self.update(id) { $0.errorMessage = error.localizedDescription }
                }
            }
        }
        tasks[id] = nil
    }

    func resume(_ id: UUID) {
#if DEBUG
        if isPreviewMode {
            update(id) {
                $0.status = .downloading
                $0.bytesPerSecond = 3_200_000
            }
            return
        }
#endif
        guard let item = items.first(where: { $0.id == id }) else { return }
        let resumeData: Data?
        if let resumeFileName = item.resumeFileName {
            let url = rootURL.appendingPathComponent(resumeFileName)
            resumeData = try? Data(contentsOf: url)
            try? fileManager.removeItem(at: url)
        } else {
            resumeData = nil
        }
        update(id) {
            $0.resumeFileName = nil
            $0.errorMessage = nil
            $0.status = .queued
        }
        startTask(for: id, resumeData: resumeData)
    }

    func remove(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        guard let item = items.first(where: { $0.id == id }) else { return }
        if let localFileName = item.localFileName {
            try? fileManager.removeItem(
                at: rootURL.appendingPathComponent(localFileName)
            )
        }
        if let resumeFileName = item.resumeFileName {
            try? fileManager.removeItem(
                at: rootURL.appendingPathComponent(resumeFileName)
            )
        }
        items.removeAll { $0.id == id }
        persist()
    }

    func removeSeries(_ dramaID: String) {
        let ids = items.filter { $0.dramaID == dramaID }.map(\.id)
        ids.forEach(remove)
    }

    func localURL(for item: OfflineDownloadItem) -> URL? {
        guard item.status == .completed,
              let localFileName = item.localFileName else { return nil }
        let url = rootURL.appendingPathComponent(localFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func startTask(for id: UUID, resumeData: Data?) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: item.remoteURL)
        }
        task.taskDescription = id.uuidString
        tasks[id] = task
        lastProgressSamples[id] = (Date(), item.downloadedBytes)
        update(id) {
            $0.status = .downloading
            $0.updatedAt = Date()
        }
        task.resume()
    }

    private func update(
        _ id: UUID,
        mutation: (inout OfflineDownloadItem) -> Void
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutation(&items[index])
        items[index].updatedAt = Date()
        persist()
    }

    private func restoreBackgroundTasks() {
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                var restoredIDs = Set<UUID>()
                for case let task as URLSessionDownloadTask in tasks {
                    guard let rawID = task.taskDescription,
                          let id = UUID(uuidString: rawID),
                          self.items.contains(where: { $0.id == id }) else {
                        task.cancel()
                        continue
                    }
                    self.tasks[id] = task
                    restoredIDs.insert(id)
                    self.update(id) { $0.status = .downloading }
                }
                for item in self.items
                    where item.status == .downloading && !restoredIDs.contains(item.id) {
                    self.update(item.id) {
                        $0.status = .paused
                        $0.bytesPerSecond = 0
                    }
                }
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode(
                [OfflineDownloadItem].self,
                from: data
              ) else { return }
        items = decoded.filter { item in
            guard item.status == .completed else { return true }
            return localURL(for: item) != nil
        }
    }

    private func persist() {
#if DEBUG
        if isPreviewMode { return }
#endif
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func markDirectoryExcludedFromBackup() {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = rootURL
        try? mutableRoot.setResourceValues(values)
    }

    private func id(for task: URLSessionTask) -> UUID? {
        task.taskDescription.flatMap(UUID.init(uuidString:))
    }

#if DEBUG
    private var isPreviewMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-OfflineDownloadUIPreview")
    }

    private static var previewItems: [OfflineDownloadItem] {
        let now = Date()
        let covers = MockData.dramas.prefix(3).map(\.coverURL)
        return [
            OfflineDownloadItem(
                id: UUID(),
                dramaID: "preview-active",
                episodeID: "preview-active-12",
                dramaTitle: "江南时节",
                coverURL: covers[safe: 0] ?? "",
                episodeNumber: 12,
                totalEpisodes: 60,
                remoteURL: URL(string: "https://example.com/episode-12.mp4")!,
                createdAt: now,
                updatedAt: now,
                status: .downloading,
                progress: 0.38,
                downloadedBytes: 1_160_000_000,
                totalBytes: 3_050_000_000,
                bytesPerSecond: 3_200_000,
                localFileName: nil,
                resumeFileName: nil,
                errorMessage: nil
            ),
            OfflineDownloadItem(
                id: UUID(),
                dramaID: "preview-complete-1",
                episodeID: "preview-complete-1-18",
                dramaTitle: "雪落今朝",
                coverURL: covers[safe: 1] ?? "",
                episodeNumber: 18,
                totalEpisodes: 18,
                remoteURL: URL(string: "https://example.com/episode-18.mp4")!,
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-3_600),
                status: .completed,
                progress: 1,
                downloadedBytes: 640_000_000,
                totalBytes: 640_000_000,
                bytesPerSecond: 0,
                localFileName: "preview-1.mp4",
                resumeFileName: nil,
                errorMessage: nil
            ),
            OfflineDownloadItem(
                id: UUID(),
                dramaID: "preview-complete-2",
                episodeID: "preview-complete-2-24",
                dramaTitle: "难逃",
                coverURL: covers[safe: 2] ?? "",
                episodeNumber: 24,
                totalEpisodes: 24,
                remoteURL: URL(string: "https://example.com/episode-24.mp4")!,
                createdAt: now.addingTimeInterval(-172_800),
                updatedAt: now.addingTimeInterval(-7_200),
                status: .completed,
                progress: 1,
                downloadedBytes: 820_000_000,
                totalBytes: 820_000_000,
                bytesPerSecond: 0,
                localFileName: "preview-2.mp4",
                resumeFileName: nil,
                errorMessage: nil
            )
        ]
    }
#endif
}

extension OfflineDownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = id(for: downloadTask) else { return }
        let now = Date()
        let previous = lastProgressSamples[id] ?? (now, 0)
        let elapsed = max(0.1, now.timeIntervalSince(previous.date))
        let speed = Int64(Double(totalBytesWritten - previous.bytes) / elapsed)
        lastProgressSamples[id] = (now, totalBytesWritten)

        if totalBytesExpectedToWrite > 0,
           usedBytes - currentBytes(for: id) + totalBytesExpectedToWrite
            > Self.maximumBytes {
            downloadTask.cancel()
            tasks[id] = nil
            update(id) {
                $0.status = .failed
                $0.bytesPerSecond = 0
                $0.errorMessage = OfflineDownloadStartError.storageFull.errorDescription
            }
            return
        }

        update(id) {
            $0.status = .downloading
            $0.downloadedBytes = totalBytesWritten
            $0.totalBytes = totalBytesExpectedToWrite > 0
                ? totalBytesExpectedToWrite
                : nil
            $0.progress = totalBytesExpectedToWrite > 0
                ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
                : 0
            $0.bytesPerSecond = max(0, speed)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = id(for: downloadTask),
              let item = items.first(where: { $0.id == id }) else { return }
        let fileExtension = item.remoteURL.pathExtension.isEmpty
            ? "mp4"
            : item.remoteURL.pathExtension
        let fileName = "\(id.uuidString).\(fileExtension)"
        let destination = rootURL.appendingPathComponent(fileName)
        do {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: location, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDestination = destination
            try? mutableDestination.setResourceValues(values)
            let bytes = (try? destination.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize).map(Int64.init) ?? item.downloadedBytes
            update(id) {
                $0.status = .completed
                $0.progress = 1
                $0.downloadedBytes = bytes
                $0.totalBytes = bytes
                $0.bytesPerSecond = 0
                $0.localFileName = fileName
                $0.resumeFileName = nil
                $0.errorMessage = nil
            }
        } catch {
            update(id) {
                $0.status = .failed
                $0.bytesPerSecond = 0
                $0.errorMessage = error.localizedDescription
            }
        }
        tasks[id] = nil
        lastProgressSamples[id] = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = id(for: task), let error else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled,
           items.first(where: { $0.id == id })?.status == .paused {
            return
        }
        guard items.first(where: { $0.id == id })?.status != .completed else {
            return
        }
        tasks[id] = nil
        update(id) {
            $0.status = .failed
            $0.bytesPerSecond = 0
            $0.errorMessage = error.localizedDescription
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = backgroundSessionCompletionHandler
        backgroundSessionCompletionHandler = nil
        completion?()
    }

    private func currentBytes(for id: UUID) -> Int64 {
        items.first(where: { $0.id == id })?.downloadedBytes ?? 0
    }
}
