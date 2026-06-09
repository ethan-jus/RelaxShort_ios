import SwiftUI
import AVFoundation

// MARK: - 短剧播放器引擎

/// 唯一播放决策中心 — For You 和 Series 共用
@MainActor
final class ShortVideoPlayerEngine: ObservableObject {

    // MARK: 公开状态

    @Published private(set) var state: PlayerPlaybackState = .idle
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentPlayer: AVPlayer?
    @Published private(set) var currentItem: PlayerMediaItem?
    @Published var progress = PlayerProgress()
    @Published var subtitleText: String?
    @Published private(set) var availableSubtitles: [PlayerSubtitleOption] = []
    @Published var selectedSubtitleID: String?
    @Published var isReadyForDisplay: Bool = false
    @Published var coverOpacity: Double = 1.0

    var metrics = PlayerMetricsLogger()
    var onPlaybackFinished: (() -> Void)?

    /// 强持有当前 ManagedItem（含 resourceLoaderDelegate），防止 delegate 被释放
    private var currentManagedItem: PlayerManagedItem?

    // MARK: 内部

    private var items: [PlayerMediaItem] = []
    private let slotPool = PlayerSlotPool()
    private var generation: Int = 0
    private var timeObserver: Any?
    private var itemEndObserver: Any?
    private var subtitleCues: [PlayerSubtitleCue] = []
    private let recoveryController = PlayerRecoveryController()
    private var preloadTasks: [Task<Void, Never>] = []
    private var subtitleTask: Task<Void, Never>?

    // TTFF 计时
    private var ttffStart: Double = 0

    init() {
        recoveryController.engine = self
        recoveryController.startMonitoring()
    }

    // MARK: - 公开 API

    func prepare(items: [PlayerMediaItem], index: Int) {
        guard !items.isEmpty, items.indices.contains(index) else { return }
        cancelAllPreloadTasks()

        self.items = items
        currentIndex = index
        currentItem = items[index]

        state = .preparing
        resetReadyState()
        generation &+= 1
        let gen = generation
        ttffStart = CACurrentMediaTime()

        slotPool.prepare(item: items[index], slot: .current, generation: gen) { [weak self] result in
            guard let self, self.generation == gen else {
                self?.metrics.logCanceledPreload(1)
                return
            }
            switch result {
            case .success(let player):
                self.attach(player: player)
                self.preloadAdjacent(gen: gen)
                self.logTTFF()
            case .failure:
                self.state = .failed(message: "加载失败")
            }
        }
    }

    func move(to index: Int) {
        guard items.indices.contains(index), index != currentIndex else { return }
        cancelAllPreloadTasks()

        let oldIndex = currentIndex
        currentIndex = index
        currentItem = items[index]

        state = .preparing
        resetReadyState()
        generation &+= 1
        let gen = generation
        ttffStart = CACurrentMediaTime()

        slotPool.move(from: oldIndex, to: index, items: items, generation: gen) { [weak self] result in
            guard let self, self.generation == gen else {
                self?.metrics.logCanceledPreload(1)
                return
            }
            switch result {
            case .success(let player):
                self.attach(player: player)
                self.preloadAdjacent(gen: gen)
                self.logTTFF()
            case .failure:
                self.state = .failed(message: "加载失败")
            }
        }
    }

    func play() {
        currentPlayer?.play()
        state = .playing
    }

    func playFromSystemResume() {
        guard state != .pausedByUser else { return }
        play()
    }

    func pause(reason: PlayerPauseReason) {
        currentPlayer?.pause()
        state = reason == .user ? .pausedByUser : .pausedBySystem
    }

    func setRate(_ rate: Float) {
        currentPlayer?.rate = rate
    }

    func seek(to fraction: Double) {
        guard let player = currentPlayer,
              let item = player.currentItem,
              item.duration.isNumeric else { return }
        let clamped = max(0, min(1, fraction))
        let target = CMTime(seconds: clamped * item.duration.seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        progress.currentTime = target.seconds
    }

    func seekTime(_ time: TimeInterval) {
        guard let player = currentPlayer else { return }
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        progress.currentTime = time
    }

    func selectSubtitle(_ id: String?) {
        selectedSubtitleID = id
    }

    func selectQuality(_ option: PlayerQualityOption?) {
        guard let player = currentPlayer,
              let item = player.currentItem else { return }
        if let bitrate = option?.bitrate, bitrate > 0 {
            // HLS: 设置峰值码率限制
            item.preferredPeakBitRate = Double(bitrate)
        } else {
            // nil 或无码率 → 恢复自适应
            item.preferredPeakBitRate = 0
        }
    }

    /// 由 ShortVideoPlayerView coordinator 回调：AVPlayerLayer 首帧可显示
    func markReadyForDisplay() {
        guard !isReadyForDisplay else { return }
        isReadyForDisplay = true
        withAnimation { self.coverOpacity = 0 }
    }

    /// 供 RecoveryController 访问：更新状态
    func updateState(_ newState: PlayerPlaybackState) {
        state = newState
    }

    /// 重建当前 item（弱网恢复用），强持有 managed item，重绑所有观察者
    func rebuildCurrentItem() {
        guard let item = currentItem, let player = currentPlayer else { return }
        resetReadyState()

        // 新建 managed item 并强持有到 engine
        let managed = PlayerItemFactory.makeManagedItem(from: item.source)
        currentManagedItem = managed

        player.replaceCurrentItem(with: managed.item)

        // 重建观察者绑定：end observer 绑新 item，recovery observer 重新 attach
        if let o = itemEndObserver {
            NotificationCenter.default.removeObserver(o)
            itemEndObserver = nil
        }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: managed.item, queue: .main
        ) { [weak self] _ in
            self?.state = .pausedBySystem
            self?.onPlaybackFinished?()
        }

        recoveryController.detachObservers()
        recoveryController.attachObservers(to: player)
    }

    /// 加载外挂字幕
    func loadExternalSubtitles(_ tracks: [PlayerSubtitleTrack]) {
        guard let track = tracks.first(where: { $0.isDefault }) ?? tracks.first else { return }
        subtitleTask?.cancel()
        subtitleTask = Task { [weak self] in
            let cues = await SubtitleParser().parse(url: track.url, format: track.format)
            guard let self, !Task.isCancelled else { return }
            self.subtitleCues = cues
        }
    }

    /// 生成缩略图
    func generateThumbnail(at fraction: Double, completion: @escaping (UIImage?) -> Void) {
        guard let player = currentPlayer, let asset = player.currentItem?.asset else {
            completion(nil)
            return
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        let dur = player.currentItem?.duration.seconds ?? 0
        guard dur > 0 else { completion(nil); return }

        let time = CMTime(seconds: CGFloat(fraction) * dur, preferredTimescale: 600)
        let task = Task {
            do {
                let (cg, _) = try await generator.image(at: time)
                guard !Task.isCancelled else { return }
                completion(UIImage(cgImage: cg))
            } catch {
                completion(nil)
            }
        }
    }

    func cleanup() {
        cancelAllPreloadTasks()
        subtitleTask?.cancel()
        removeObservers()
        recoveryController.detachObservers()
        slotPool.cleanup()
        currentManagedItem = nil
        currentPlayer = nil
        state = .idle
        generation &+= 1
    }

    // MARK: - 内部

    private func attach(player: AVPlayer) {
        removeObservers()
        currentPlayer = player
        startObserving()
        recoveryController.attachObservers(to: player)

        // 读取内封字幕
        if let asset = player.currentItem?.asset {
            availableSubtitles = PlayerItemFactory.embeddedSubtitles(from: asset)
        }

        state = .ready
    }

    private func preloadAdjacent(gen: Int) {
        let nextIdx = currentIndex + 1
        if nextIdx < items.count {
            let task = Task { [weak self] in
                guard let self else { return }
                self.slotPool.prepare(item: self.items[nextIdx], slot: .next, generation: gen) { _ in }
            }
            preloadTasks.append(task)
        }
        let prevIdx = currentIndex - 1
        if prevIdx >= 0 {
            let task = Task { [weak self] in
                guard let self else { return }
                self.slotPool.prepare(item: self.items[prevIdx], slot: .previous, generation: gen) { _ in }
            }
            preloadTasks.append(task)
        }
    }

    private func resetReadyState() {
        isReadyForDisplay = false
        coverOpacity = 1.0
    }

    private func cancelAllPreloadTasks() {
        for task in preloadTasks { task.cancel() }
        preloadTasks.removeAll()
    }

    private func logTTFF() {
        let ms = (CACurrentMediaTime() - ttffStart) * 1000
        metrics.logTTFF(ms)
    }

    // MARK: - 时间观察者

    private func startObserving() {
        guard let player = currentPlayer else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            guard let self, let player = self.currentPlayer else { return }
            self.progress.currentTime = time.seconds

            if let item = player.currentItem, item.duration.isNumeric {
                self.progress.duration = item.duration.seconds
                if let range = item.loadedTimeRanges.first?.timeRangeValue {
                    let buffered = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
                    self.progress.bufferProgress = self.progress.duration > 0
                        ? buffered / self.progress.duration : 0
                }
            }

            self.updateSubtitle(at: time.seconds)
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { [weak self] _ in
            self?.state = .pausedBySystem
            self?.onPlaybackFinished?()
        }
    }

    private func removeObservers() {
        if let o = timeObserver {
            currentPlayer?.removeTimeObserver(o)
            timeObserver = nil
        }
        if let o = itemEndObserver {
            NotificationCenter.default.removeObserver(o)
            itemEndObserver = nil
        }
    }

    // MARK: - 字幕更新

    private func updateSubtitle(at time: TimeInterval) {
        guard !subtitleCues.isEmpty else { return }
        if let cue = subtitleCues.first(where: { time >= $0.start && time <= $0.end }) {
            subtitleText = cue.text
        } else {
            subtitleText = nil
        }
    }

    private func withAnimation(_ block: @escaping () -> Void) {
        SwiftUI.withAnimation(.easeOut(duration: 0.18)) { block() }
    }
}
