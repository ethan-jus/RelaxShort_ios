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
    @Published private(set) var hasVisiblePlaybackStarted: Bool = false
    @Published private(set) var diagnostics = PlayerDiagnostics()

    var metrics = PlayerMetricsLogger()
    var onPlaybackFinished: (() -> Void)?

    /// 仅供协调器和定向测试核对当前播放列表；页面不得据此直接修改引擎。
    var playlistItemIDs: [String] { items.map(\.id) }

    /// 播放意图：即使 player 还没准备好，我们也记住了用户想播放
    internal var wantsPlayback = false

    // MARK: 内部

    private var items: [PlayerMediaItem] = []
    private let slotPool = PlayerSlotPool()
    private var generation: Int = 0
    private var timeObserver: Any?
    private var itemEndObserver: Any?
    private var subtitleCues: [PlayerSubtitleCue] = []
    private var desiredPlaybackRate: Float = 1
    private var adaptiveQualityPolicy: PlayerAdaptiveQualityPolicy = .standard
    private let subtitleLanguagePreferenceKey = "player.preferredSubtitleLanguage"
    private let subtitlesDisabledPreferenceKey = "player.subtitlesDisabled"
    private let recoveryController = PlayerRecoveryController()
    private var preloadTasks: [Task<Void, Never>] = []
    private var subtitleTask: Task<Void, Never>?

    // TTFF 计时
    private var ttffStart: Double = 0
    // move TTFF 计时
    private var moveTTFFStart: Double = 0
    // item status KVO
    private var itemStatusObs: NSKeyValueObservation?
    // 预加载升 current 的超时检测
    private var readinessTimeoutTask: Task<Void, Never>?
    // 单个媒体只做一次直连降级，避免坏缓存和坏网络之间反复重建
    private var directFallbackMediaIDs = Set<String>()
    /// Task36B-2: 当前会话播放诊断追踪
    private var playbackTrace: PlaybackDiagnosticsTrace?
    /// 记录当前 prepare/move 对应的 index，供首帧和 Move 区分
    private var traceCurrentIndex: Int = -1
    /// 同一集先使用预览源、后拿到正式 /play 源时的待升级条目。
    /// 仅替换 AVPlayerItem，绝不能销毁当前 AVPlayer 或重置已展示的首帧状态。
    private var pendingCurrentSourceUpgrade: PlayerMediaItem?
    private var isCurrentSourceUpgradePending = false
    private var sourceUpgradeResumeTime: TimeInterval = 0
    /// replaceCurrentItem 不经过 SlotPool，需由引擎强持有缓存代理。
    private var replacementResourceLoaderDelegate: PlayerResourceLoaderDelegate?

    init() {
        recoveryController.engine = self
        recoveryController.startMonitoring()
        log("引擎初始化")
    }

    // MARK: - 公开 API

    /// Task36B-2: 开始播放诊断追踪（由 RecommendSession 或 SeriesPlayerView 调用）
    func startPlaybackTrace(_ trace: PlaybackDiagnosticsTrace) {
        playbackTrace = trace
        traceCurrentIndex = trace.targetIndex ?? currentIndex
    }
    /// 在诊断追踪中记录一个阶段
    func markTrace(_ name: String) {
        playbackTrace?.mark(name)
    }
    /// 完成诊断追踪并输出汇总日志。termination 传终止原因（完成/锁集阻断/播放源失败/网络失败）。
    func finishTrace(termination: String = "完成") {
        playbackTrace?.finish(termination: termination)
        playbackTrace = nil
    }

    /// Task36A: 追加新播放条目到现有列表末尾，不中断当前播放。
    /// 用于分页加载后同步播放器内部 items，确保后续 move(to:) 能索引到新条目。
    func appendItems(_ newItems: [PlayerMediaItem]) {
        guard !newItems.isEmpty else { return }
        let before = items.count
        items.append(contentsOf: newItems)
        log("appendItems: \(before) → \(items.count)")
    }

    /// Series 获取到下一集播放合同后，只更新共享引擎的同一条播放列表。
    /// 当前 AVPlayer 不重建；若首帧已出现，则由唯一槽位池开始预加载新的 next。
    func updatePlaylistKeepingCurrent(_ newItems: [PlayerMediaItem]) {
        guard let currentID = currentItem?.id,
              let newIndex = newItems.firstIndex(where: { $0.id == currentID }) else { return }
        cancelAllPreloadTasks()
        let previousItem = newItems[safe: newIndex - 1]
        let nextItem = newItems[safe: newIndex + 1]
        let keepsPreparedPrevious = previousItem.map {
            slotPool.contains(item: $0, in: .previous)
        } ?? false
        let keepsPreparedNext = nextItem.map { slotPool.contains(item: $0, in: .next) } ?? false
        if !keepsPreparedPrevious {
            slotPool.cancel(.previous)
        }
        if !keepsPreparedNext {
            slotPool.cancel(.next)
        }
        items = newItems
        currentIndex = newIndex
        log("播放列表已同步: 当前=\(currentID) 数量=\(newItems.count)")
        if hasVisiblePlaybackStarted, !keepsPreparedNext {
            schedulePreloadAdjacent(gen: generation, delayMs: 0)
        }
    }

    /// 将同一媒体从预览源原地升级为正式播放源。
    /// 这里有意不调用 prepare / deactivate / beginContentTransition：它们会清空进度和首帧可见状态，
    /// 导致 Series 首播在正式播放源返回后重新出现封面或黑屏。
    @discardableResult
    func upgradeCurrentSource(to item: PlayerMediaItem) -> Bool {
        guard let currentItem, currentItem.id == item.id, currentItem.source != item.source else {
            return false
        }

        self.currentItem = item
        if items.indices.contains(currentIndex), items[currentIndex].id == item.id {
            items[currentIndex] = item
        }
        updateDiagnostics(for: item, stateText: "official-source-upgrade")

        guard let player = currentPlayer else {
            pendingCurrentSourceUpgrade = item
            log("正式播放源升级已排队: 当前播放器尚未挂载 id=\(item.id)")
            return true
        }

        replaceCurrentItemForSourceUpgrade(item, on: player)
        return true
    }

    /// 提交已经开始的异步内容切换。优先提升共享池中按媒体 ID 匹配的 preroll 槽，
    /// 未命中时才在同一个槽位池中创建当前播放器。
    func commitContentTransition(
        items newItems: [PlayerMediaItem],
        index: Int,
        autoplay: Bool
    ) {
        guard newItems.indices.contains(index) else {
            endContentTransitionWithoutMedia()
            return
        }
        if currentPlayer != nil {
            beginContentTransition(autoplay: autoplay)
        }
        clearCurrentSourceUpgrade()
        cancelAllPreloadTasks()
        let oldIndex = currentIndex
        items = newItems
        currentIndex = index
        currentItem = newItems[index]
        wantsPlayback = autoplay
        state = .preparing
        resetProgress()
        resetReadyState()
        updateDiagnostics(for: newItems[index], stateText: "commit-transition")
        generation &+= 1
        let gen = generation
        ttffStart = CACurrentMediaTime()
        markTrace("AVPlayer准备")

        let attachResult: (Result<AVPlayer, Error>) -> Void = { [weak self] result in
            guard let self, self.generation == gen else { return }
            switch result {
            case .success(let player):
                self.attach(player: player)
                self.markTrace("attach播放器")
            case .failure(let error):
                self.log("内容切换提交失败: \(error.localizedDescription)")
                self.endContentTransitionWithoutMedia()
            }
        }

        // Series 的异步切集也必须走与 For You 相同的三槽旋转：命中时提升相邻槽，
        // 未命中时把旧 current 停放到反向槽，保证用户回滑不会重新建链。
        slotPool.move(
            from: oldIndex,
            to: index,
            items: newItems,
            generation: gen,
            adaptiveQualityPolicy: adaptiveQualityPolicy,
            completion: attachResult
        )
    }

    func prepare(items: [PlayerMediaItem], index: Int) {
        guard !items.isEmpty, items.indices.contains(index) else { return }
        cancelAllPreloadTasks()
        clearCurrentSourceUpgrade()
        // 全量 prepare 代表新播放列表，旧相邻槽不得跨 owner 或跨剧残留。
        slotPool.cleanup()

        self.items = items
        currentIndex = index
        currentItem = items[index]

        state = .preparing
        updateDiagnostics(for: items[index], stateText: "prepare")
        resetProgress()
        resetReadyState()
        generation &+= 1
        let gen = generation
        ttffStart = CACurrentMediaTime()

        log("prepare: idx=\(index) id=\(items[index].id) gen=\(gen) url=\(String(describing: items[index].source))")
        markTrace("AVPlayer准备")

        slotPool.prepare(
            item: items[index], slot: .current, generation: gen,
            adaptiveQualityPolicy: adaptiveQualityPolicy
        ) { [weak self] result in
            guard let self, self.generation == gen else {
                self?.log("prepare: gen过期 idx=\(index) gen=\(gen)")
                self?.metrics.logCanceledPreload(1)
                return
            }
            switch result {
            case .success(let player):
                self.log("prepare: 成功 attach player gen=\(gen)")
                self.attach(player: player)
                self.markTrace("attach播放器")
            case .failure(let err):
                self.log("prepare: 失败 err=\(err.localizedDescription)")
                self.rebuildCurrentThroughPool(for: items[index], gen: gen)
            }
        }
    }

    func move(to index: Int, autoplay: Bool = true) {
        guard items.indices.contains(index), index != currentIndex else { return }
        // Task36B-2 返工：每次 move 启动新的诊断 trace，记录本次滑动的完整链路
        startPlaybackTrace(PlaybackDiagnosticsTrace(scene: "for_you_move", targetIndex: index))
        let oldIndex = currentIndex
        beginContentTransition(autoplay: autoplay)
        currentIndex = index
        currentItem = items[index]

        updateDiagnostics(for: items[index], stateText: "move")
        generation &+= 1
        let gen = generation
        ttffStart = CACurrentMediaTime()

        log("move: \(oldIndex)→\(index) gen=\(gen)")
        moveTTFFStart = CACurrentMediaTime()
        markTrace("AVPlayer准备")

        slotPool.move(
            from: oldIndex, to: index, items: items, generation: gen,
            adaptiveQualityPolicy: adaptiveQualityPolicy
        ) { [weak self] result in
            guard let self, self.generation == gen else {
                self?.log("move: gen过期 gen=\(gen)")
                self?.metrics.logCanceledPreload(1)
                return
            }
            switch result {
            case .success(let player):
                self.log("move: 成功 attach player gen=\(gen)")
                self.attach(player: player)
                self.markTrace("attach播放器")
                // 预加载升 current 超时检测：800ms 未 ready 则重建
                self.startReadinessTimeout(gen: gen, index: index)
            case .failure(let err):
                self.log("move: 失败 err=\(err.localizedDescription)")
                self.rebuildCurrentThroughPool(for: items[index], gen: gen)
            }
        }
    }

    func play() {
        wantsPlayback = true
        log("play: wantsPlayback=\(wantsPlayback) hasPlayer=\(currentPlayer != nil)")

        if let player = currentPlayer {
            if state == .pausedByUser || state == .pausedBySystem { state = .ready }
            startPlayback(player)
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
            if state == .pausedBySystem { state = .ready }
            startPlayback(player)
            log("playFromSystemResume: 恢复播放")
        }
    }

    func pause(reason: PlayerPauseReason) {
        if reason == .user { wantsPlayback = false }
        currentPlayer?.pause()
        state = reason == .user ? .pausedByUser : .pausedBySystem
        log("pause: reason=\(reason) wantsPlayback=\(wantsPlayback)")
    }

    /// 开始切换到另一条内容时，原子撤销旧媒体的可见与可听状态。
    /// 页面在等待下一条播放源期间只能看到封面，不能继续持有或恢复旧 AVPlayer。
    func beginContentTransition(autoplay: Bool) {
        generation &+= 1
        cancelAllPreloadTasks()
        subtitleTask?.cancel()
        subtitleTask = nil
        recoveryController.cancelPendingRecovery()
        recoveryController.detachObservers()
        clearCurrentSourceUpgrade()

        currentPlayer?.pause()
        removeObservers()
        itemStatusObs?.invalidate()
        itemStatusObs = nil

        currentPlayer = nil
        currentItem = nil
        subtitleText = nil
        subtitleCues.removeAll()
        availableSubtitles = []
        resetProgress()
        resetReadyState()

        wantsPlayback = autoplay
        state = .preparing
        log("内容切换开始: 旧媒体已静音并解绑 autoplay=\(autoplay) gen=\(generation)")
    }

    /// 新内容暂不可播放（锁集、网络失败或空源）时结束加载态。
    /// 保持 currentPlayer 为空，避免任何 UI 操作重新启动旧媒体。
    func endContentTransitionWithoutMedia() {
        guard currentPlayer == nil else { return }
        wantsPlayback = false
        state = .pausedBySystem
        log("内容切换结束: 当前无可播放媒体")
    }

    /// 释放播放所有权：撤销播放意图，取消所有异步任务，使进行中的 prepare 失效
    func deactivate() {
        beginContentTransition(autoplay: false)
        slotPool.cleanup()
        items.removeAll()
        currentIndex = 0
        state = .pausedBySystem
        log("deactivate: 已释放全部播放器槽位和播放列表 gen=\(generation)")
    }

    func setRate(_ rate: Float) {
        desiredPlaybackRate = rate
        if wantsPlayback {
            currentPlayer?.rate = rate
        }
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

    /// seek 带 completion 确认（handoff 场景使用），completion 在 MainActor 回调
    func seekTime(_ time: TimeInterval, completion: @escaping @MainActor (Bool) -> Void) {
        guard let player = currentPlayer,
              let item = player.currentItem else { completion(false); return }
        let observedGeneration = generation
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            Task { @MainActor [weak self] in
                guard let self,
                      self.generation == observedGeneration,
                      self.currentPlayer === player,
                      player.currentItem === item else {
                    completion(false)
                    return
                }
                var nextProgress = self.progress
                nextProgress.currentTime = time
                self.progress = nextProgress
                completion(finished)
            }
        }
    }

    func selectSubtitle(_ id: String?) {
        selectedSubtitleID = id
        if let tracks = currentItem?.externalSubtitles, !tracks.isEmpty {
            guard let id,
                  let track = tracks.first(where: { $0.id == id }) else {
                UserDefaults.standard.set(true, forKey: subtitlesDisabledPreferenceKey)
                subtitleTask?.cancel()
                subtitleCues.removeAll()
                subtitleText = nil
                return
            }
            UserDefaults.standard.set(false, forKey: subtitlesDisabledPreferenceKey)
            UserDefaults.standard.set(track.languageCode, forKey: subtitleLanguagePreferenceKey)
            loadExternalSubtitle(track)
            return
        }
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

    /// 生成页面衔接上下文（For You → Series handoff）
    func makeHandoffContext(dramaID: String? = nil, episodeNumber: Int? = nil) -> PlayerHandoffContext {
        return PlayerHandoffContext(
            mediaID: currentItem?.id ?? "unknown",
            dramaID: dramaID,
            episodeNumber: episodeNumber,
            resumeTime: progress.currentTime,
            duration: progress.duration,
            wasPlaying: state == .playing,
            coverURL: currentItem?.coverURL ?? "",
            createdAt: Date()
        )
    }

    func selectQuality(_ option: PlayerQualityOption?) {
        guard let item = currentPlayer?.currentItem else { return }
        if let bitrate = option?.bitrate, bitrate > 0 {
            item.preferredPeakBitRate = Double(bitrate)
        } else {
            item.preferredPeakBitRate = 0
        }
        if let maximumResolution = option?.maximumResolution {
            item.preferredMaximumResolution = maximumResolution
        } else {
            item.preferredMaximumResolution = adaptiveQualityPolicy.maximumResolution
        }
    }

    /// Auto 模式只提高或降低 ABR 上限；不覆盖用户手动选择的固定清晰度。
    func setAdaptiveQualityPolicy(_ policy: PlayerAdaptiveQualityPolicy) {
        guard adaptiveQualityPolicy != policy else { return }
        adaptiveQualityPolicy = policy
        guard let currentItem,
              let playerItem = currentPlayer?.currentItem,
              PlayerItemFactory.hlsURL(from: currentItem.source) != nil else { return }
        playerItem.preferredMaximumResolution = policy.maximumResolution
        playerItem.preferredPeakBitRate = 0
        log("Auto画质上限更新: \(Int(policy.maximumResolution.height))P")
    }

    func applyAutomaticQualityPolicy() {
        guard let currentItem,
              let playerItem = currentPlayer?.currentItem,
              PlayerItemFactory.hlsURL(from: currentItem.source) != nil else { return }
        playerItem.preferredPeakBitRate = 0
        playerItem.preferredMaximumResolution = adaptiveQualityPolicy.maximumResolution
    }

    /// 只接受当前 AVPlayerLayer 对应 player 的首帧回调。
    /// SwiftUI 快速切页时旧 layer 可能迟到回调，必须过滤，否则会提前隐藏当前封面造成黑屏。
    func markReadyForDisplay(from player: AVPlayer) {
        guard currentPlayer === player else {
            log("markReadyForDisplay: 忽略旧 player 回调")
            return
        }
        guard !isReadyForDisplay else { return }
        isReadyForDisplay = true
        diagnostics.stateText = "first-frame"
        logTTFF()
        markTrace("首帧可见")
        finishTrace()
        // 媒资探测只能由开发者显式触发；首帧热路径不再自动发送 HEAD/Range 请求抢占带宽。
        if moveTTFFStart > 0 {
            let ms = (CACurrentMediaTime() - moveTTFFStart) * 1000
            diagnostics.moveTTFFMs = ms
            log("moveTTFF: \(String(format: "%.0f", ms))ms")
            moveTTFFStart = 0
        }
    }

    func updateState(_ newState: PlayerPlaybackState) {
        state = newState
        switch newState {
        case .waitingNetwork, .stalled, .recovering:
            // 当前播放一旦发生网络压力，立即释放相邻预加载带宽。
            cancelAllPreloadTasks()
            slotPool.cancelPreparingAdjacent()
            diagnostics.preloadState = "paused-for-current"
        case .playing where hasVisiblePlaybackStarted:
            schedulePreloadAdjacent(gen: generation, delayMs: 0)
        default:
            break
        }
        log("updateState: \(newState)")
    }

    func rebuildCurrentItem(autoplay: Bool = true) {
        guard let item = currentItem, let player = currentPlayer else { return }
        resetReadyState()
        log("rebuildItem: id=\(item.id)")

        removeObservers()
        itemStatusObs?.invalidate()
        itemStatusObs = nil
        recoveryController.detachObservers()

        let managedItem = PlayerItemFactory.makePlaybackItem(
            from: item,
            adaptiveQualityPolicy: adaptiveQualityPolicy
        )
        replacementResourceLoaderDelegate = managedItem.resourceLoaderDelegate
        let replacementItem = managedItem.item
        player.replaceCurrentItem(with: replacementItem)
        slotPool.updateCurrentMetadata(
            player: player,
            playerItem: replacementItem,
            mediaItem: item,
            resourceLoaderDelegate: managedItem.resourceLoaderDelegate
        )

        recoveryController.attachObservers(to: player)
        setupItemStatusKVO(player)
        startObserving()

        if autoplay, wantsPlayback {
            startPlayback(player)
            log("rebuildItem: 恢复播放")
        }
    }

    func loadExternalSubtitles(_ tracks: [PlayerSubtitleTrack]) {
        availableSubtitles = tracks.map {
            PlayerSubtitleOption(id: $0.id, displayName: $0.displayName, languageCode: $0.languageCode)
        }
        if UserDefaults.standard.bool(forKey: subtitlesDisabledPreferenceKey) {
            selectedSubtitleID = nil
            subtitleCues.removeAll()
            subtitleText = nil
            return
        }
        let preferredLanguage = UserDefaults.standard.string(forKey: subtitleLanguagePreferenceKey)
        guard let track = tracks.first(where: {
            $0.languageCode.caseInsensitiveCompare(preferredLanguage ?? "") == .orderedSame
        }) ?? tracks.first(where: { $0.isDefault }) ?? tracks.first else { return }
        selectedSubtitleID = track.id
        loadExternalSubtitle(track)
    }

    private func loadExternalSubtitle(_ track: PlayerSubtitleTrack) {
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
        currentPlayer = nil
        state = .idle
        generation &+= 1
        log("cleanup")
    }

    // MARK: - 统一槽位兜底

    /// 失败重建仍由唯一 PlayerSlotPool 创建 AVPlayer，禁止出现池外播放器实例。
    private func rebuildCurrentThroughPool(for item: PlayerMediaItem, gen: Int) {
        guard generation == gen else { return }
        slotPool.rebuildCurrent(
            item: item, generation: gen,
            adaptiveQualityPolicy: adaptiveQualityPolicy
        ) { [weak self] result in
            guard let self, self.generation == gen else { return }
            switch result {
            case .success(let player):
                self.log("统一槽位重建成功 id=\(item.id)")
                self.attach(player: player)
            case .failure(let error):
                self.state = .failed(message: error.localizedDescription)
            }
        }
    }

    // MARK: - 内部

    private func attach(player: AVPlayer) {
        removeObservers()
        resetReadyState()
        currentPlayer = player
        setupItemStatusKVO(player)
        startObserving()
        recoveryController.attachObservers(to: player)

        // 让 AVPlayer 基于当前吞吐量决定首帧缓冲；相邻集由槽位池预热保障秒开。
        // 禁止用关闭自动等待来换取表面速度，否则弱网下会 ready 但实际停在 paused。
        player.currentItem?.preferredForwardBufferDuration = 0
        player.automaticallyWaitsToMinimizeStalling = true

        // 自动加载字幕。播放合同中的外挂字幕优先于媒体内封字幕。
        if let item = currentItem {
            if !item.externalSubtitles.isEmpty {
                loadExternalSubtitles(item.externalSubtitles)
            } else {
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
        }

        state = .ready
        log("attach: status=\(statusString(player.currentItem?.status)) timeControl=\(tcsString(player.timeControlStatus))")

        // 若同一集在挂载前已拿到正式播放源，原地替换 item；没有旧首帧时才允许 attach 的常规重置。
        if let pendingItem = pendingCurrentSourceUpgrade {
            replaceCurrentItemForSourceUpgrade(pendingItem, on: player)
        } else if wantsPlayback {
            startPlayback(player)
            log("attach: 自动播放（wantsPlayback=true）")
        }
    }

    /// 同一 AVPlayer 内替换播放源。保留播放意图、进度、播放器实例与已展示首帧，避免 UI 退回封面。
    private func replaceCurrentItemForSourceUpgrade(_ item: PlayerMediaItem, on player: AVPlayer) {
        guard currentPlayer === player else {
            pendingCurrentSourceUpgrade = item
            return
        }

        pendingCurrentSourceUpgrade = nil
        isCurrentSourceUpgradePending = true
        sourceUpgradeResumeTime = max(0, progress.currentTime)

        removeObservers()
        itemStatusObs?.invalidate()
        itemStatusObs = nil
        recoveryController.detachObservers()

        let managedItem = PlayerItemFactory.makePlaybackItem(
            from: item,
            adaptiveQualityPolicy: adaptiveQualityPolicy
        )
        replacementResourceLoaderDelegate = managedItem.resourceLoaderDelegate
        let replacementItem = managedItem.item
        player.replaceCurrentItem(with: replacementItem)
        slotPool.updateCurrentMetadata(
            player: player,
            playerItem: replacementItem,
            mediaItem: item,
            resourceLoaderDelegate: managedItem.resourceLoaderDelegate
        )
        recoveryController.attachObservers(to: player)
        setupItemStatusKVO(player)
        startObserving()

        state = .preparing
        if !item.externalSubtitles.isEmpty {
            loadExternalSubtitles(item.externalSubtitles)
        }
        markTrace("正式播放源升级")
        log("正式播放源升级: id=\(item.id) 保留进度=\(String(format: "%.2f", sourceUpgradeResumeTime))s")
        if wantsPlayback {
            startPlayback(player)
        }
    }

    private func restoreSourceUpgradeProgressIfNeeded(on player: AVPlayer) {
        guard isCurrentSourceUpgradePending,
              currentPlayer === player,
              let expectedItem = player.currentItem else { return }
        let expectedGeneration = generation
        isCurrentSourceUpgradePending = false
        let resumeTime = sourceUpgradeResumeTime
        sourceUpgradeResumeTime = 0

        let resume = CMTime(seconds: resumeTime, preferredTimescale: 600)
        player.seek(to: resume, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] finished in
            Task { @MainActor in
                guard let self, let player,
                      self.generation == expectedGeneration,
                      self.currentPlayer === player,
                      player.currentItem === expectedItem else { return }
                if finished {
                    var nextProgress = self.progress
                    nextProgress.currentTime = resumeTime
                    self.progress = nextProgress
                }
                if self.wantsPlayback {
                    self.startPlayback(player)
                }
                self.log("正式播放源升级完成: 续播=\(String(format: "%.2f", resumeTime))s 成功=\(finished)")
            }
        }
    }

    private func clearCurrentSourceUpgrade() {
        pendingCurrentSourceUpgrade = nil
        isCurrentSourceUpgradePending = false
        sourceUpgradeResumeTime = 0
    }

    /// 监听 AVPlayerItem.status，failed 时触发 fallback
    private func setupItemStatusKVO(_ player: AVPlayer) {
        itemStatusObs?.invalidate()
        let observedGeneration = generation
        itemStatusObs = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.generation == observedGeneration,
                      self.currentPlayer === player,
                      player.currentItem === item else { return }
                if item.status == .readyToPlay {
                    if self.isCurrentSourceUpgradePending {
                        self.restoreSourceUpgradeProgressIfNeeded(on: player)
                    } else if self.wantsPlayback,
                              self.state != .pausedByUser,
                              self.state != .pausedBySystem,
                              self.state != .recovering,
                              player.timeControlStatus != .playing {
                        // playImmediately 在 item 仍为 unknown 时可能不会保留播放意图：
                        // item 后续虽已 ready，player 仍会无错误地停在 paused，UI 因而永久转圈。
                        // ready 后补发一次播放命令，同时尊重用户/系统暂停状态。
                        self.startPlayback(player)
                        self.log("itemStatusKVO: ready 后恢复播放")
                    }
                    return
                }
                guard item.status == .failed else { return }
                let err = item.error?.localizedDescription ?? "未知错误"
                self.log("itemStatusKVO: failed err=\(err)")
                guard let cur = self.currentItem else { return }
                if case .hlsWithFallback(_, let mp4URL) = cur.source {
                    self.log("itemStatusKVO: HLS→MP4 fallback url=\(mp4URL)")
                    replacementResourceLoaderDelegate = nil
                    let fallbackItem = PlayerItemFactory.makeDirectItem(from: .mp4(mp4URL)).item
                    self.removeObservers()
                    self.recoveryController.detachObservers()
                    player.replaceCurrentItem(with: fallbackItem)
                    self.slotPool.updateCurrentMetadata(
                        player: player,
                        playerItem: fallbackItem,
                        mediaItem: cur,
                        resourceLoaderDelegate: nil
                    )
                    self.recoveryController.attachObservers(to: player)
                    self.setupItemStatusKVO(player)
                    self.startObserving()
                    if self.wantsPlayback { self.startPlayback(player) }
                } else {
                    if !self.directFallbackMediaIDs.contains(cur.id) {
                        self.directFallbackMediaIDs.insert(cur.id)
                        self.log("itemStatusKVO: 降级直连重建 id=\(cur.id)")
                        self.rebuildCurrentItem(autoplay: true)
                        return
                    }
                    self.recoveryController.detachObservers()
                    self.recoveryController.snapshot()
                    self.recoveryController.attemptRecovery()
                }
            }
        }
    }

    private func startPlayback(_ player: AVPlayer) {
        player.playImmediately(atRate: desiredPlaybackRate)
    }

    private func preloadAdjacent(gen: Int) {
        let nextIdx = currentIndex + 1
        if nextIdx < items.count {
            let nextItem = items[nextIdx]
            guard !slotPool.contains(item: nextItem, in: .next) else { return }
            log("preload: start next=\(nextIdx)")
            diagnostics.preloadState = "preparing:next:\(nextItem.id)"
            let task = Task { [weak self] in
                guard let self else { return }
                self.slotPool.prepare(
                    item: nextItem, slot: .next, generation: gen,
                    adaptiveQualityPolicy: self.adaptiveQualityPolicy
                ) { result in
                    if case .success = result {
                        Task { @MainActor in
                            self.diagnostics.preloadState = "ready:next:\(nextItem.id)"
                        }
                    } else {
                        Task { @MainActor in
                            self.diagnostics.preloadState = "failed:next:\(nextItem.id)"
                        }
                    }
                }
            }
            preloadTasks.append(task)
        }
    }

    /// 延后启动预加载，先把当前视频的首帧和播放请求让出去。
    /// DramaBox 类短剧体验的核心是“当前点击优先”：封面兜底 + 立即 play + 首帧后再轻量预热下一条。
    private func schedulePreloadAdjacent(gen: Int, delayMs: UInt64) {
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            guard let self, !Task.isCancelled, self.generation == gen else { return }
            self.preloadAdjacent(gen: gen)
        }
        preloadTasks.append(task)
    }

    private func resetReadyState() {
        isReadyForDisplay = false
        hasVisiblePlaybackStarted = false
    }

    private func resetProgress() {
        progress = PlayerProgress()
    }

    /// 预加载升 current 的慢启动诊断。慢 CDN 不能因为固定 800ms 阈值被强制重建，
    /// 否则会丢弃即将成功的请求并从零开始，实际等待反而更长。
    private func startReadinessTimeout(gen: Int, index: Int) {
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000) // 800ms
            guard let self, self.generation == gen else {
                print("[PlayerKit] current readiness timeout canceled gen=\(gen)")
                return
            }
            let item = self.currentPlayer?.currentItem
            let isPlayingReadyItem = item?.status == .readyToPlay
                && self.currentPlayer?.timeControlStatus == .playing
            guard !self.isReadyForDisplay, !isPlayingReadyItem else { return }
            print("[PlayerKit] 当前媒体启动较慢 idx=\(index) gen=\(gen)，继续等待原请求，不重复建链")
        }
    }

    private func cancelAllPreloadTasks() {
        readinessTimeoutTask?.cancel(); readinessTimeoutTask = nil
        for task in preloadTasks { task.cancel() }
        preloadTasks.removeAll()
    }

    private func logTTFF() {
        let ms = (CACurrentMediaTime() - ttffStart) * 1000
        diagnostics.ttffMs = ms
        metrics.logTTFF(ms)
    }

    private func updateDiagnostics(for item: PlayerMediaItem, stateText: String) {
        diagnostics.mediaID = item.id
        diagnostics.sourceKind = PlayerItemFactory.sourceKind(item.source)
        diagnostics.playbackStrategy = PlayerItemFactory.playbackStrategyDescription(for: item.source)
        diagnostics.stateText = stateText
        diagnostics.cacheSummary = "AVFoundation 原生流缓存"
    }

    // MARK: - 时间观察者

    private func startObserving() {
        guard let player = currentPlayer,
              let observedItem = player.currentItem else { return }
        let observedGeneration = generation

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self,
                      self.generation == observedGeneration,
                      self.currentPlayer === player,
                      player.currentItem === observedItem else { return }
                // 正式源替换尚未完成 seek 时，不能让新 item 的 0 秒回调覆盖页面上的续播进度。
                guard !self.isCurrentSourceUpgradePending else { return }
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
                if self.isReadyForDisplay,
                   !self.hasVisiblePlaybackStarted,
                   player.timeControlStatus == .playing,
                   time.seconds > 0.05 {
                    self.hasVisiblePlaybackStarted = true
                    self.diagnostics.stateText = "visible-playback"
                    // 当前视频确认已经前进后再预热 next，避免与首个 HLS 分片争抢带宽。
                    self.schedulePreloadAdjacent(gen: self.generation, delayMs: 0)
                    let totalMs = (CACurrentMediaTime() - self.ttffStart) * 1000
                    self.log("首帧可见: 播放进度=\(String(format: "%.2f", time.seconds))s 总耗时=\(String(format: "%.0f", totalMs))ms")
                }
            }
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: observedItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.generation == observedGeneration,
                      self.currentPlayer === player,
                      player.currentItem === observedItem else { return }
                self.state = .pausedBySystem
                self.onPlaybackFinished?()
            }
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

// MARK: - 播放诊断追踪模型 (Task36B-2 返工)

/// 记录一次播放启动链路的阶段耗时，供 For You 和 Series 复用。
public struct PlaybackDiagnosticsTrace {
    public let traceID: String; public let scene: String
    public let seriesID: String?; public let episodeNumber: Int?; public let targetIndex: Int?
    public let startedAt: CFTimeInterval; private(set) public var marks: [PlaybackDiagnosticsMark] = []

    public init(scene: String, seriesID: String? = nil, episodeNumber: Int? = nil, targetIndex: Int? = nil) {
        self.traceID = Self.shortID(); self.scene = scene
        self.seriesID = seriesID; self.episodeNumber = episodeNumber; self.targetIndex = targetIndex
        self.startedAt = CACurrentMediaTime()
    }
    public mutating func mark(_ name: String) {
        let elapsed = Int((CACurrentMediaTime() - startedAt) * 1000)
        marks.append(PlaybackDiagnosticsMark(name: name, elapsedMs: elapsed))
        #if DEBUG
        let ep = episodeNumber.map { " 集=\($0)" } ?? ""
        let sid = seriesID.map { " 剧=\($0.prefix(12))" } ?? ""
        print("[播放诊断] trace=\(traceID) 场景=\(scene)\(sid)\(ep) 阶段=\(name) 耗时=\(elapsed)ms")
        #endif
    }
    public func finish(termination: String = "完成") {
        #if DEBUG
        let ep = episodeNumber.map { " 集=\($0)" } ?? ""
        let sid = seriesID.map { " 剧=\($0.prefix(12))" } ?? ""
        let segs = marks.map { "\($0.name):\($0.elapsedMs)" }.joined(separator: ", ")
        let total = marks.last?.elapsedMs ?? 0
        print("[播放诊断] trace=\(traceID) 场景=\(scene)\(sid)\(ep) 终止=\(termination) 首帧总耗时=\(total)ms 分段=\(segs)")
        #endif
    }
    private static func shortID() -> String {
        String((0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined().prefix(8))
    }
}
public struct PlaybackDiagnosticsMark: Equatable { public let name: String; public let elapsedMs: Int }

// MARK: - 媒体 URL 轻量检查 (Task36B-2 返工 v4：复用 StreamedRangeFetcher，修正日志)

public enum MediaURLProbe {
    private static let probeBytes = 262_144
    public static func probe(_ url: URL, label: String = "播放源") {
        #if DEBUG
        Task(priority: .background) {
            let short = sanitizedURL(url); var r = "[媒资检查]"
            var hs = "?", hm = 0, sR = false, cl: Int64 = 0
            do {
                var req = URLRequest(url: url); req.httpMethod = "HEAD"; req.timeoutInterval = 10
                let t0 = CACurrentMediaTime()
                let (_, resp) = try await URLSession.shared.data(for: req)
                hm = Int((CACurrentMediaTime() - t0) * 1000)
                let h = resp as? HTTPURLResponse; hs = "\(h?.statusCode ?? 0)"
                sR = (h?.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased() == "bytes"
                if let v = h?.value(forHTTPHeaderField: "Content-Length") { cl = Int64(v) ?? 0 }
            } catch { hs = "失败" }
            r += " URL=\(short) HEAD状态=\(hs) HEAD耗时=\(hm)ms 支持Range=\(sR) 长度=\(cl)"

            let t0 = CACurrentMediaTime()
            let result = await StreamedRangeFetcher.fetch(url: url, requestedRange: 0...Int64(probeBytes - 1), maxBytes: probeBytes)
            let ms = Int((CACurrentMediaTime() - t0) * 1000)
            switch result {
            case .success(let data, _): r += " Range状态=206 Range耗时=\(ms)ms 字节=\(data.count)"
            case .truncated(let data, _): r += " Range状态=206-主动截断 Range耗时=\(ms)ms 字节=\(data.count) 截断=超过\(probeBytes)字节已主动取消"
            case .notRange(let code, let data): r += " Range状态=非206-\(code) Range耗时=\(ms)ms 字节=\(data?.count ?? 0)" + (code == 200 ? " 警告=源站忽略Range(返回200)" : "")
            case .failed(let e): r += " Range状态=失败 Range耗时=\(ms)ms 错误=\(e.localizedDescription.prefix(40))"
            }
            print(r)
        }
        #endif
    }
    private static func sanitizedURL(_ url: URL) -> String {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), let h = c.host
        else { return url.absoluteString }
        return "\(h)/\(c.path.split(separator: "/").last.map(String.init) ?? c.path)"
    }
}

// MARK: - 共享流式 Range 请求 (Task36B-2 返工 v4)

/// 流式 Range：URLSessionDataTask+delegate，非206立刻cancel不读body，
/// 206验证Content-Range与请求范围一致，累计maxBytes立刻cancel。供warmCache/MediaURLProbe复用。
public enum StreamedRangeFetcher {
    public enum FetchResult {
        case success(data: Data, totalLength: Int64?)
        case truncated(data: Data, totalLength: Int64?)
        case notRange(statusCode: Int, data: Data?)
        case failed(Error)
    }
    /// 测试可注入 URLProtocol 配置；真实请求始终由本次 fetch 专属 delegate 管理。
    static var testConfiguration: URLSessionConfiguration?

    public static func fetch(url: URL, requestedRange: ClosedRange<Int64>, maxBytes: Int) async -> FetchResult {
        await withCheckedContinuation { cc in
            let d = FD(reqRange: requestedRange, maxB: maxBytes) { cc.resume(returning: $0) }
            var req = URLRequest(url: url)
            req.setValue("bytes=\(requestedRange.lowerBound)-\(requestedRange.upperBound)", forHTTPHeaderField: "Range")
            req.timeoutInterval = 10
            let configuration = testConfiguration ?? .ephemeral
            let s = URLSession(configuration: configuration, delegate: d, delegateQueue: nil)
            d.session = s; d.task = s.dataTask(with: req); d.task?.resume()
        }
    }
    private final class FD: NSObject, URLSessionDataDelegate {
        let reqRange: ClosedRange<Int64>; let maxB: Int; let cb: (FetchResult) -> Void
        var session: URLSession?; var task: URLSessionDataTask?
        var chunks: [Data] = []; var total = 0; var code = 0; var crHeader: String?
        init(reqRange: ClosedRange<Int64>, maxB: Int, cb: @escaping (FetchResult) -> Void) {
            self.reqRange = reqRange; self.maxB = maxB; self.cb = cb
        }
        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            if let http = response as? HTTPURLResponse {
                code = http.statusCode
                crHeader = http.value(forHTTPHeaderField: "Content-Range")
            }
            if code != 206 {
                task?.cancel()
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            total += data.count
            if total > maxB {
                session.invalidateAndCancel()
                task?.cancel()
                return
            }
            chunks.append(data)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let data = chunks.reduce(into: Data()) { $0.append($1) }
            if code != 206 { session.invalidateAndCancel(); cb(.notRange(statusCode: code, data: data.isEmpty ? nil : data)); return }
            if total > maxB {
                let tl = crHeader?.components(separatedBy: "/").last.flatMap { Int64($0) }
                session.invalidateAndCancel(); cb(.truncated(data: data, totalLength: tl)); return
            }
            if let error, (error as NSError).code != NSURLErrorCancelled {
                session.invalidateAndCancel(); cb(.failed(error)); return
            }
            // 校验 Content-Range 与请求范围一致
            guard let cr = crHeader,
                  let br = cr.components(separatedBy: "/").first?.replacingOccurrences(of: "bytes ", with: ""),
                  let di = br.firstIndex(of: "-") else {
                session.invalidateAndCancel(); cb(.failed(NSError(domain: "SRF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Content-Range缺失"]))); return
            }
            let loS = String(br[..<di]); let hiS = String(br[br.index(after: di)...])
            guard let lo = Int64(loS), let hi = Int64(hiS),
                  lo == reqRange.lowerBound,
                  hi <= reqRange.upperBound,
                  hi - lo + 1 == Int64(data.count) else {
                session.invalidateAndCancel(); cb(.failed(NSError(domain: "SRF", code: -2, userInfo: [NSLocalizedDescriptionKey: "Content-Range不匹配: \(br)"]))); return
            }
            let tl = cr.components(separatedBy: "/").last.flatMap { Int64($0) }
            session.invalidateAndCancel(); cb(.success(data: data, totalLength: tl))
        }
    }
}
