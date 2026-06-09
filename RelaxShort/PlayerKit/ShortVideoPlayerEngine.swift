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

    var metrics = PlayerMetricsLogger()
    var onPlaybackFinished: (() -> Void)?

    /// 强持有当前 ManagedItem（含 resourceLoaderDelegate），防止 delegate 被释放
    private var currentManagedItem: PlayerManagedItem?

    /// 播放意图：即使 player 还没准备好，我们也记住了用户想播放
    private var wantsPlayback = false

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
    // item status KVO
    private var itemStatusObs: NSKeyValueObservation?

    init() {
        recoveryController.engine = self
        recoveryController.startMonitoring()
        log("引擎初始化")
    }

    // MARK: - 公开 API

    func prepare(items: [PlayerMediaItem], index: Int) {
        guard !items.isEmpty, items.indices.contains(index) else { return }
        cancelAllPreloadTasks()

        self.items = items
        currentIndex = index
        currentItem = items[index]

        state = .preparing
        resetProgress()
        resetReadyState()
        generation &+= 1
        let gen = generation
        ttffStart = CACurrentMediaTime()

        log("prepare: idx=\(index) id=\(items[index].id) gen=\(gen) url=\(String(describing: items[index].source))")

        slotPool.prepare(item: items[index], slot: .current, generation: gen) { [weak self] result in
            guard let self, self.generation == gen else {
                self?.log("prepare: gen过期 idx=\(index) gen=\(gen)")
                self?.metrics.logCanceledPreload(1)
                return
            }
            switch result {
            case .success(let player):
                self.log("prepare: 成功 attach player gen=\(gen)")
                self.attach(player: player)
                self.preloadAdjacent(gen: gen)
                self.logTTFF()
            case .failure(let err):
                self.log("prepare: 失败 err=\(err.localizedDescription)")
                self.tryDirectFallback(for: items[index], gen: gen)
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
        resetProgress()
        resetReadyState()
        generation &+= 1
        let gen = generation
        ttffStart = CACurrentMediaTime()

        log("move: \(oldIndex)→\(index) gen=\(gen)")

        slotPool.move(from: oldIndex, to: index, items: items, generation: gen) { [weak self] result in
            guard let self, self.generation == gen else {
                self?.log("move: gen过期 gen=\(gen)")
                self?.metrics.logCanceledPreload(1)
                return
            }
            switch result {
            case .success(let player):
                self.log("move: 成功 attach player gen=\(gen)")
                self.attach(player: player)
                self.preloadAdjacent(gen: gen)
                self.logTTFF()
            case .failure(let err):
                self.log("move: 失败 err=\(err.localizedDescription)")
                self.tryDirectFallback(for: items[index], gen: gen)
            }
        }
    }

    func play() {
        wantsPlayback = true
        log("play: wantsPlayback=\(wantsPlayback) hasPlayer=\(currentPlayer != nil)")

        if let player = currentPlayer {
            player.play()
            state = .playing
            log("play: player.play() called rate=\(player.rate) status=\(statusString(player.currentItem?.status))")
        }
        // else: 等 attach 后由 wantsPlayback 驱动自动播放
    }

    func playFromSystemResume() {
        guard state != .pausedByUser else {
            log("playFromSystemResume: 跳过（用户暂停中）")
            return
        }
        wantsPlayback = true
        if let player = currentPlayer {
            player.play()
            state = .playing
            log("playFromSystemResume: 恢复播放")
        }
    }

    func pause(reason: PlayerPauseReason) {
        if reason == .user { wantsPlayback = false }
        currentPlayer?.pause()
        state = reason == .user ? .pausedByUser : .pausedBySystem
        log("pause: reason=\(reason) wantsPlayback=\(wantsPlayback)")
    }

    func setRate(_ rate: Float) {
        currentPlayer?.rate = rate
        log("setRate: \(rate)")
    }

    func seek(to fraction: Double) {
        guard let player = currentPlayer, let item = player.currentItem, item.duration.isNumeric else { return }
        let clamped = max(0, min(1, fraction))
        let target = CMTime(seconds: clamped * item.duration.seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        var nextProgress = progress
        nextProgress.currentTime = target.seconds
        progress = nextProgress
    }

    func seekTime(_ time: TimeInterval) {
        guard let player = currentPlayer else { return }
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        var nextProgress = progress
        nextProgress.currentTime = time
        progress = nextProgress
    }

    func selectSubtitle(_ id: String?) {
        selectedSubtitleID = id
        guard let item = currentPlayer?.currentItem else { return }
        Task {
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                if let id, let option = group.options.first(where: { $0.displayName == id }) {
                    item.select(option, in: group)
                } else {
                    item.select(nil, in: group)
                }
            }
        }
    }

    func selectQuality(_ option: PlayerQualityOption?) {
        guard let _ = currentPlayer, let item = currentPlayer?.currentItem else { return }
        if let bitrate = option?.bitrate, bitrate > 0 {
            item.preferredPeakBitRate = Double(bitrate)
        } else {
            item.preferredPeakBitRate = 0
        }
    }

    func markReadyForDisplay() {
        guard !isReadyForDisplay else { return }
        isReadyForDisplay = true
        log("isReadyForDisplay = true")
    }

    func updateState(_ newState: PlayerPlaybackState) {
        state = newState
        log("updateState: \(newState)")
    }

    func rebuildCurrentItem() {
        guard let item = currentItem, let player = currentPlayer else { return }
        resetReadyState()
        log("rebuildItem: id=\(item.id)")

        let managed = PlayerItemFactory.makeDirectItem(from: item.source)
        currentManagedItem = managed

        player.replaceCurrentItem(with: managed.item)

        if let o = itemEndObserver {
            NotificationCenter.default.removeObserver(o); itemEndObserver = nil
        }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: managed.item, queue: .main
        ) { [weak self] _ in
            self?.state = .pausedBySystem; self?.onPlaybackFinished?()
        }

        recoveryController.detachObservers()
        recoveryController.attachObservers(to: player)

        if wantsPlayback {
            player.play()
            state = .playing
            log("rebuildItem: 恢复播放")
        }
    }

    func loadExternalSubtitles(_ tracks: [PlayerSubtitleTrack]) {
        guard let track = tracks.first(where: { $0.isDefault }) ?? tracks.first else { return }
        subtitleTask?.cancel()
        subtitleTask = Task { [weak self] in
            let cues = await SubtitleParser().parse(url: track.url, format: track.format)
            guard let self, !Task.isCancelled else { return }
            self.subtitleCues = cues
        }
    }

    func generateThumbnail(at fraction: Double, completion: @escaping (UIImage?) -> Void) {
        guard let player = currentPlayer, let asset = player.currentItem?.asset else {
            completion(nil); return
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        let dur = player.currentItem?.duration.seconds ?? 0
        guard dur > 0 else { completion(nil); return }
        let time = CMTime(seconds: CGFloat(fraction) * dur, preferredTimescale: 600)
        Task {
            do {
                let (cg, _) = try await generator.image(at: time)
                guard !Task.isCancelled else { return }
                completion(UIImage(cgImage: cg))
            } catch { completion(nil) }
        }
    }

    func cleanup() {
        wantsPlayback = false
        itemStatusObs?.invalidate(); itemStatusObs = nil
        cancelAllPreloadTasks()
        subtitleTask?.cancel()
        removeObservers()
        recoveryController.detachObservers()
        slotPool.cleanup()
        currentManagedItem = nil
        currentPlayer = nil
        state = .idle
        generation &+= 1
        log("cleanup")
    }

    // MARK: - 直连兜底

    private func tryDirectFallback(for item: PlayerMediaItem, gen: Int) {
        guard let url = directURL(from: item.source) else {
            state = .failed(message: "缓存和直连均失败")
            return
        }
        log("fallback: 直连播放 url=\(url)")
        let player = AVPlayer(url: url)
        currentManagedItem = nil // 直连不需要 cache delegate
        // 强持有到 local
        let _player = player
        self.attach(player: _player)
    }

    private func directURL(from source: PlayerMediaSource) -> URL? {
        switch source {
        case .mp4(let url), .mp4WithEmbeddedSubtitles(let url):
            return url
        case .mp4WithExternalSubtitles(let videoURL, _):
            return videoURL
        case .hls(let masterURL):
            return masterURL
        case .hlsWithFallback(_, let fallbackMP4URL):
            // HLS 失败 → 回退到 MP4
            log("fallback: HLS→MP4 url=\(fallbackMP4URL)")
            return fallbackMP4URL
        }
    }

    // MARK: - 内部

    private func attach(player: AVPlayer) {
        removeObservers()
        currentPlayer = player
        setupItemStatusKVO(player)
        startObserving()
        recoveryController.attachObservers(to: player)

        // 设置播放策略：current 优先稳定播放
        player.currentItem?.preferredForwardBufferDuration = 4.0
        player.automaticallyWaitsToMinimizeStalling = true

        // 自动加载字幕（按 source 类型）
        if let item = currentItem {
            switch item.source {
            case .mp4WithExternalSubtitles(_, let subtitles):
                loadExternalSubtitles(subtitles)
            case .mp4WithEmbeddedSubtitles, .hls, .hlsWithFallback:
                if let asset = player.currentItem?.asset {
                    Task { [weak self] in
                        let subs = await PlayerItemFactory.embeddedSubtitles(from: asset)
                        self?.availableSubtitles = subs
                    }
                }
            default: break
            }
        }

        state = .ready
        log("attach: status=\(statusString(player.currentItem?.status)) timeControl=\(tcsString(player.timeControlStatus))")

        // 如果有播放意图，attach 后立即播放
        if wantsPlayback {
            player.play()
            state = .playing
            log("attach: 自动播放（wantsPlayback=true）")
        }
    }

    /// 监听 AVPlayerItem.status，failed 时触发 fallback
    private func setupItemStatusKVO(_ player: AVPlayer) {
        itemStatusObs?.invalidate()
        itemStatusObs = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, change in
            guard let self, self.currentPlayer === player else { return }
            guard item.status == .failed else { return }
            let err = item.error?.localizedDescription ?? "未知错误"
            self.log("itemStatusKVO: failed err=\(err)")
            // 只对当前 current item 做 fallback
            guard let cur = self.currentItem else { return }
            // HLS fallback
            if case .hlsWithFallback(_, let mp4URL) = cur.source {
                self.log("itemStatusKVO: HLS→MP4 fallback url=\(mp4URL)")
                let fallback = PlayerItemFactory.makeDirectItem(from: .mp4(mp4URL))
                self.currentManagedItem = fallback
                player.replaceCurrentItem(with: fallback.item)
                if self.wantsPlayback { player.play(); self.state = .playing }
            } else {
                self.recoveryController.detachObservers()
                self.recoveryController.snapshot()
                self.recoveryController.attemptRecovery()
            }
        }
    }

    private func preloadAdjacent(gen: Int) {
        let nextIdx = currentIndex + 1
        if nextIdx < items.count {
            log("preload: start next=\(nextIdx)")
            let task = Task { [weak self] in
                guard let self else { return }
                self.slotPool.prepare(item: self.items[nextIdx], slot: .next, generation: gen) { _ in }
            }
            preloadTasks.append(task)
        }
        let prevIdx = currentIndex - 1
        if prevIdx >= 0 {
            log("preload: start prev=\(prevIdx)")
            let task = Task { [weak self] in
                guard let self else { return }
                self.slotPool.prepare(item: self.items[prevIdx], slot: .previous, generation: gen) { _ in }
            }
            preloadTasks.append(task)
        }
    }

    private func resetReadyState() {
        isReadyForDisplay = false
    }

    private func resetProgress() {
        progress = PlayerProgress()
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
            var nextProgress = self.progress
            nextProgress.currentTime = time.seconds
            if let item = player.currentItem, item.duration.isNumeric {
                nextProgress.duration = item.duration.seconds
                if let range = item.loadedTimeRanges.first?.timeRangeValue {
                    let buffered = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
                    nextProgress.bufferProgress = nextProgress.duration > 0
                        ? buffered / nextProgress.duration : 0
                }
            }
            self.progress = nextProgress
            self.updateSubtitle(at: time.seconds)
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { [weak self] _ in
            self?.state = .pausedBySystem; self?.onPlaybackFinished?()
        }
    }

    private func removeObservers() {
        if let o = timeObserver { currentPlayer?.removeTimeObserver(o); timeObserver = nil }
        if let o = itemEndObserver { NotificationCenter.default.removeObserver(o); itemEndObserver = nil }
    }

    private func updateSubtitle(at time: TimeInterval) {
        guard !subtitleCues.isEmpty else { return }
        if let cue = subtitleCues.first(where: { time >= $0.start && time <= $0.end }) {
            subtitleText = cue.text
        } else {
            subtitleText = nil
        }
    }

    // MARK: - 诊断日志

    private func log(_ msg: String) {
        #if DEBUG
        print("[PlayerKit] \(msg)")
        #endif
    }

    private func statusString(_ status: AVPlayerItem.Status?) -> String {
        guard let status else { return "nil" }
        switch status {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "other"
        }
    }

    private func tcsString(_ tcs: AVPlayer.TimeControlStatus) -> String {
        switch tcs {
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate: return "waiting"
        case .playing: return "playing"
        @unknown default: return "unknown"
        }
    }
}
