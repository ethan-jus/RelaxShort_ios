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
    private var stallTimeoutTask: Task<Void, Never>?

    deinit {
        recoveryTask?.cancel()
        stablePlaybackTask?.cancel()
        stallTimeoutTask?.cancel()
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
        ) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self, let player,
                      self.engine?.currentPlayer === player,
                      player.currentItem === item else { return }
                self.onFailed()
            }
        }

        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item, queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self, let player,
                      self.engine?.currentPlayer === player,
                      player.currentItem === item else { return }
                self.onStalled()
            }
        }

        // KVO 监听 timeControlStatus
        timeControlObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.engine?.currentPlayer === player else { return }
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    self.onWaiting()
                case .playing:
                    self.stallTimeoutTask?.cancel()
                    self.stallTimeoutTask = nil
                    // 播放状态只由 AVPlayer 的真实回调确认，不能由 play() 调用提前假定。
                    if let e = self.engine, e.wantsPlayback {
                        e.updateState(.playing)
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
        stallTimeoutTask?.cancel()
        stallTimeoutTask = nil
    }

    // MARK: - 取消挂起恢复

    func cancelPendingRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
        stablePlaybackTask?.cancel()
        stablePlaybackTask = nil
        stallTimeoutTask?.cancel()
        stallTimeoutTask = nil
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
        engine?.updateState(.failed(message: "player.playback_failed".localized))
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
        scheduleStallRecovery()
    }

    private func onWaiting() {
        snapshot()
        guard let e = engine,
              !wasUserPaused,
              e.state != .pausedByUser,
              e.state != .pausedBySystem else { return }

        e.updateState(isOnline ? .stalled : .waitingNetwork)
        if isOnline { scheduleStallRecovery() }
    }

    private func onNetworkChange(_ ok: Bool) {
        let recovered = !isOnline && ok
        isOnline = ok

        guard let engine else { return }

        // 断网时 snapshot 播放中的状态
        if !ok {
            stallTimeoutTask?.cancel()
            stallTimeoutTask = nil
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

    /// AVPlayer 可自行熬过短暂抖动；连续 8 秒仍无播放进度才重建当前 item。
    /// 这为 loading 提供确定的恢复出口，同时避免短卡顿频繁断链。
    private func scheduleStallRecovery() {
        // 同一轮 waiting/stalled 只从第一次事件起算，不能被 AVPlayer 的状态抖动
        // 反复延期；playing、切集、断网或 observer detach 会统一取消并清空。
        guard stallTimeoutTask == nil else { return }
        guard isOnline,
              let engine,
              let expectedItemID = engine.currentItem?.id,
              engine.wantsPlayback else { return }
        stallTimeoutTask = Task { @MainActor [weak self, weak engine] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) }
            catch { return }
            guard let self else { return }
            self.stallTimeoutTask = nil
            guard let engine,
                  !Task.isCancelled,
                  self.isOnline,
                  engine.wantsPlayback,
                  engine.currentItem?.id == expectedItemID,
                  engine.state == .stalled || engine.state == .waitingNetwork else { return }
            self.snapshot()
            self.attemptRecovery(reason: .stalledTimeout)
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
            engine.updateState(
                .failed(message: "player.recovery_failed".localizedFormat(count))
            )
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
                      engine.currentItem?.id == expectedItemID,
                      engine.currentPlayer === player,
                      player.currentItem === currentItem else { return }
            }

            guard self.recoveryGeneration == token,
                  currentItem.status == .readyToPlay,
                  engine.currentItem?.id == expectedItemID,
                  engine.currentPlayer === player,
                  player.currentItem === currentItem else {
                if self.recoveryGeneration == token,
                   engine.currentItem?.id == expectedItemID,
                   engine.currentPlayer === player,
                   player.currentItem === currentItem {
                    engine.updateState(.failed(message: "player.recovery_failed".localizedFormat(count)))
                    print("[PlayerKit] recovery failed reason=ready-timeout id=\(expectedItemID)")
                }
                return
            }

            print("[PlayerKit] recovery ready id=\(expectedItemID)")

            let target = CMTime(seconds: recoverTime, preferredTimescale: 600)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.recoveryGeneration == token,
                              engine.currentItem?.id == expectedItemID,
                              engine.currentPlayer === player,
                              player.currentItem === currentItem else {
                            continuation.resume(); return
                        }
                        print("[PlayerKit] recovery seek complete time=\(recoverTime) finished=\(finished)")
                        if finished, engine.wantsPlayback {
                            engine.play()
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
