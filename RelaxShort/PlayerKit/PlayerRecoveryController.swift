import AVFoundation
import Network

// MARK: - 恢复原因

enum RecoveryReason: String { case networkRestored, itemFailed, stalledTimeout }

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
        ) { [weak self] _ in
            Task { @MainActor in self?.onFailed() }
        }

        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onStalled() }
        }

        // KVO 监听 timeControlStatus
        timeControlObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                guard let self else { return }
                switch status {
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
        wasPlaying = engine.wantsPlayback && engine.state != .pausedByUser
        wasUserPaused = engine.state == .pausedByUser
    }

    // MARK: - 事件处理

    private func onFailed() {
        snapshot()
        print("[PlayerKit] item failed at time=\(lastTime)")
        engine?.updateState(.failed(message: "播放失败"))
        if let e = engine, e.wantsPlayback, !wasUserPaused {
            print("[PlayerKit] recovery start id=\(lastItem?.id ?? "?") time=\(lastTime) reason=itemFailed")
            attemptRecovery(reason: .itemFailed)
        }
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
    func attemptRecovery(reason: RecoveryReason = .networkRestored) {
        guard let engine, let _ = lastItem, wasPlaying else { return }

        let startTime = CACurrentMediaTime()
        let recoverTime = lastTime
        print("[PlayerKit] recovery start id=\(lastItem?.id ?? "?") time=\(recoverTime) reason=\(reason.rawValue)")

        engine.updateState(.recovering)
        engine.rebuildCurrentItem()

        // 等待新 item ready 后再 seek
        Task { @MainActor in
            // 给 item 一点时间加载
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            guard let player = engine.currentPlayer, let item = player.currentItem else {
                print("[PlayerKit] recovery failed reason=no-player")
                engine.updateState(.failed(message: "恢复失败"))
                return
            }

            // 等待 item readyToPlay
            let deadline = Date().addingTimeInterval(5)
            while item.status != .readyToPlay, Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            guard item.status == .readyToPlay else {
                print("[PlayerKit] recovery seek complete time=\(recoverTime) finished=false")
                engine.updateState(.failed(message: "恢复超时"))
                return
            }

            // seek 到断点
            let target = CMTime(seconds: recoverTime, preferredTimescale: 600)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                    print("[PlayerKit] recovery seek complete time=\(recoverTime) finished=\(finished)")
                    if finished, engine.wantsPlayback {
                        player.play()
                        engine.updateState(.playing)
                        print("[PlayerKit] recovery play resumed")
                    }
                    continuation.resume()
                }
            }

            let durationMs = (CACurrentMediaTime() - startTime) * 1000
            engine.metrics.logRecovery(ms: durationMs)
        }
    }
}
