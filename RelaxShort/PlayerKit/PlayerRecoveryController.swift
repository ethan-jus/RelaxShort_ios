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
    private var timeControlObs: NSKeyValueObservation?

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

        // KVO 监听 timeControlStatus
        timeControlObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            switch player.timeControlStatus {
            case .waitingToPlayAtSpecifiedRate:
                self.onWaiting()
            case .playing:
                // 从 waiting/stalled/recovering 恢复为正常播放
                if let e = self.engine {
                    switch e.state {
                    case .waitingNetwork, .stalled, .recovering:
                        e.updateState(.playing)
                    default: break
                    }
                }
            default: break
            }
        }
    }

    func detachObservers() {
        if let o = failObserver { NotificationCenter.default.removeObserver(o); failObserver = nil }
        if let o = stallObserver { NotificationCenter.default.removeObserver(o); stallObserver = nil }
        timeControlObs?.invalidate()
        timeControlObs = nil
    }

    // MARK: - 状态快照

    /// 公开 — engine item status KVO 需要快照
    func snapshot() {
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

    private func onWaiting() {
        snapshot()
        guard let e = engine,
              !wasUserPaused,
              e.state != .pausedByUser,
              e.state != .pausedBySystem else { return }

        e.updateState(isOnline ? .stalled : .waitingNetwork)
    }

    private func onNetworkChange(_ ok: Bool) {
        let recovered = !isOnline && ok
        isOnline = ok

        guard let engine else { return }

        // 断网时 snapshot 播放中的状态
        if !ok {
            if engine.state == .playing {
                snapshot()
                engine.updateState(.waitingNetwork)
            }
            return
        }

        // 网络恢复
        guard recovered else { return }

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

    /// 公开 — engine item status failed 时调用
    func attemptRecovery() {
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
