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

    /// Task24: 每个 media item 连续恢复失败计数，防止无限 recovery
    private var failureCounts: [String: Int] = [:]
    private let maxRecoveryAttempts = 3
    private var recoveryGeneration = 0

    // observer tokens — 可 detach
    private var failObserver: Any?
    private var stallObserver: Any?
    private var timeControlObs: NSKeyValueObservation?
    private var recoveryTask: Task<Void, Never>?
    private var stablePlaybackTask: Task<Void, Never>?

    deinit {
        recoveryTask?.cancel()
        stablePlaybackTask?.cancel()
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
                    // 只有稳定播放一段时间后才清除失败计数。
                    // AVPlayer 可能短暂进入 playing 后立即 failed，过早清零会让 attempt 永远停在 1/3。
                    if let id = self.engine?.currentItem?.id {
                        self.scheduleStablePlaybackReset(for: id)
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
        stablePlaybackTask?.cancel()
        stablePlaybackTask = nil
    }

    // MARK: - 取消挂起恢复

    func cancelPendingRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
        stablePlaybackTask?.cancel()
        stablePlaybackTask = nil
        wasPlaying = false
        wasUserPaused = false
        lastItem = nil
        recoveryGeneration &+= 1
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
            attemptRecovery(reason: .itemFailed)
        } else {
            print("[PlayerKit] recovery skipped reason=userPaused")
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
        guard let engine, let item = lastItem, wasPlaying else { return }

        let count = (failureCounts[item.id] ?? 0) + 1
        failureCounts[item.id] = count
        if count > maxRecoveryAttempts {
            print("[PlayerKit] recovery capped id=\(item.id) failures=\(count) max=\(maxRecoveryAttempts)")
            engine.updateState(.failed(message: "连续恢复失败(\(count)次)"))
            return
        }

        recoveryTask?.cancel()
        recoveryGeneration &+= 1
        let token = recoveryGeneration
        let expectedItemID = item.id
        let startTime = CACurrentMediaTime()
        let recoverTime = lastTime
        print("[PlayerKit] recovery start id=\(item.id) time=\(recoverTime) reason=\(reason.rawValue) attempt=\(count)/\(maxRecoveryAttempts)")

        engine.updateState(.recovering)
        engine.rebuildCurrentItem(autoplay: false)

        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await Task.sleep(nanoseconds: 300_000_000) }
            catch { return }
            guard self.recoveryGeneration == token, !Task.isCancelled else { return }
            guard let player = engine.currentPlayer,
                  let currentItem = player.currentItem,
                  engine.currentItem?.id == expectedItemID else {
                print("[PlayerKit] recovery failed reason=no-player-or-stale")
                return
            }

            // 等待 item readyToPlay
            let deadline = Date().addingTimeInterval(5)
            while currentItem.status != .readyToPlay, Date() < deadline {
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { return }
                guard self.recoveryGeneration == token, !Task.isCancelled,
                      engine.currentItem?.id == expectedItemID else { return }
            }

            guard self.recoveryGeneration == token,
                  currentItem.status == .readyToPlay,
                  engine.currentItem?.id == expectedItemID else { return }

            print("[PlayerKit] recovery ready id=\(expectedItemID)")

            let target = CMTime(seconds: recoverTime, preferredTimescale: 600)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.recoveryGeneration == token,
                              engine.currentItem?.id == expectedItemID,
                              engine.currentPlayer === player else {
                            continuation.resume(); return
                        }
                        print("[PlayerKit] recovery seek complete time=\(recoverTime) finished=\(finished)")
                        if finished, engine.wantsPlayback {
                            player.play(); engine.updateState(.playing)
                            print("[PlayerKit] recovery play resumed")
                        }
                        continuation.resume()
                    }
                }
            }

            let durationMs = (CACurrentMediaTime() - startTime) * 1000
            engine.metrics.logRecovery(ms: durationMs)
            if self.recoveryGeneration == token { self.recoveryTask = nil }
        }
    }

    private func scheduleStablePlaybackReset(for itemID: String) {
        stablePlaybackTask?.cancel()
        stablePlaybackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.engine?.currentItem?.id == itemID,
                  self.engine?.state == .playing else { return }
            self.failureCounts.removeValue(forKey: itemID)
            print("[PlayerKit] recovery counter reset id=\(itemID) reason=stablePlayback")
        }
    }
}
