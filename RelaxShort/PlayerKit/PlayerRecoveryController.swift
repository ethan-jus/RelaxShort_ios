import AVFoundation
import Network

// MARK: - 播放器恢复控制器

/// 监听 AVPlayerItem 失败、卡顿和网络变化，自动恢复播放
/// observer 可重复 attach/detach，不堆积
@MainActor
final class PlayerRecoveryController {
    weak var engine: ShortVideoPlayerEngine?

    private var lastTime: TimeInterval = 0
    private var lastItem: PlayerMediaItem?
    private var wasPlaying = false
    private var wasUserPaused = false

    private let monitor = NWPathMonitor()
    private var isOnline = true

    // observer tokens — 可 detach
    private var failObserver: Any?
    private var stallObserver: Any?
    private var waitingObserver: Any?

    deinit {
        monitor.cancel()
    }

    // MARK: - 网络监控

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.onNetworkChange(path.status == .satisfied)
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    // MARK: - 观察者管理

    func attachObservers(to player: AVPlayer) {
        detachObservers()

        guard let item = player.currentItem else { return }

        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in self?.onFailed() }

        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item, queue: .main
        ) { [weak self] _ in self?.onStalled() }
    }

    func detachObservers() {
        if let o = failObserver { NotificationCenter.default.removeObserver(o); failObserver = nil }
        if let o = stallObserver { NotificationCenter.default.removeObserver(o); stallObserver = nil }
        if let o = waitingObserver { NotificationCenter.default.removeObserver(o); waitingObserver = nil }
    }

    // MARK: - 状态快照

    private func snapshot() {
        guard let engine else { return }
        lastTime = engine.progress.currentTime
        lastItem = engine.currentItem
        wasPlaying = engine.state == .playing
        wasUserPaused = engine.state == .pausedByUser
    }

    // MARK: - 事件处理

    private func onFailed() {
        snapshot()
        print("[PlayerKit] item failed at time=\(lastTime)")
        engine?.updateState(.failed(message: "播放失败"))
    }

    private func onStalled() {
        snapshot()
        print("[PlayerKit] playback stalled at time=\(lastTime)")
        engine?.updateState(.stalled)
    }

    private func onNetworkChange(_ ok: Bool) {
        let wasOffline = !isOnline && ok
        isOnline = ok

        guard wasOffline, let engine else { return }

        switch engine.state {
        case .failed, .stalled, .waitingNetwork:
            if !wasUserPaused && wasPlaying {
                attemptRecovery()
            }
        default:
            break
        }
    }

    // MARK: - 恢复逻辑

    private func attemptRecovery() {
        guard let engine, let _ = lastItem, wasPlaying else { return }

        let startTime = CACurrentMediaTime()
        print("[PlayerKit] recovery: item=\(lastItem?.id ?? "?") time=\(lastTime)")

        engine.updateState(.recovering)
        engine.rebuildCurrentItem()
        engine.seekTime(lastTime)
        engine.play()

        let durationMs = (CACurrentMediaTime() - startTime) * 1000
        print("[PlayerKit] recovery complete, duration=\(String(format: "%.0f", durationMs))ms")
        engine.metrics.logRecovery(ms: durationMs)
    }
}
