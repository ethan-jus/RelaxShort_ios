import SwiftUI

// MARK: - 播放协调器

/// 持有唯一的 ShortVideoPlayerEngine，管理 For You / Series 之间的播放权转移
@MainActor
final class PlayerCoordinator: ObservableObject {

    /// Series 播放申请使用稳定业务身份，不能只比较可能跨剧重复的 mediaID。
    private struct SeriesMediaIdentity: Equatable {
        let dramaID: String
        let episodeNumber: Int
        let mediaID: String
    }

    enum Owner: Hashable {
        case forYou
        case series(dramaID: String)
    }

    @Published private(set) var owner: Owner?
    @Published private(set) var engine: ShortVideoPlayerEngine

    private var seriesResumeTask: Task<Void, Never>?
    private var forYouPlaybackFinishedHandler: (@MainActor () -> Void)?
    private var seriesPlaybackFinishedHandler: (dramaID: String, action: @MainActor () -> Void)?
    private var claimGeneration: Int = 0
    private var currentSeriesIdentity: SeriesMediaIdentity?

    init() {
        self.engine = ShortVideoPlayerEngine()
        configurePlaybackFinishedRouting()
    }

    init(engine: ShortVideoPlayerEngine) {
        self.engine = engine
        configurePlaybackFinishedRouting()
    }

    private func configurePlaybackFinishedRouting() {
        engine.onPlaybackFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }
    }

    /// Series 在任何网络请求前先取得唯一播放权，阻止旧 For You 媒体继续播放。
    func beginSeries(dramaID: String) {
        invalidateCurrentClaim()
        currentSeriesIdentity = nil
        seriesPlaybackFinishedHandler = nil
        owner = .series(dramaID: dramaID)
        engine.deactivate()
    }

    /// Series 的结束动作只绑定当前剧，页面释放或 owner 切换后不会收到迟到回调。
    func setSeriesPlaybackFinishedHandler(
        dramaID: String,
        action: @escaping @MainActor () -> Void
    ) {
        guard owner == .series(dramaID: dramaID) else { return }
        seriesPlaybackFinishedHandler = (dramaID, action)
    }

    /// For You 页面常驻期间注册结束动作，Coordinator 仅在 For You 持有播放权时派发。
    func setForYouPlaybackFinishedHandler(
        action: @escaping @MainActor () -> Void
    ) {
        forYouPlaybackFinishedHandler = action
    }

    /// 只有 For You 仍持有播放权时，页面生命周期才允许暂停或恢复。
    func pauseForYou() {
        guard owner == .forYou else { return }
        engine.pause(reason: .system)
    }

    func resumeForYou() {
        guard owner == .forYou else { return }
        engine.playFromSystemResume()
    }

    /// Series 切集等待播放合同时只暂停当前媒体，不允许页面直接重置 Engine。
    func pauseSeriesForTransition(dramaID: String) {
        guard owner == .series(dramaID: dramaID) else { return }
        engine.pause(reason: .system)
    }

    /// For You 声明播放权 — 同 item 不重建
    func claimForYou(items: [PlayerMediaItem], index: Int) {
        let targetID = items[safe: index]?.id ?? ""
        if owner == .forYou, engine.currentItem?.id == targetID {
            engine.play(); return
        }
        invalidateCurrentClaim()
        currentSeriesIdentity = nil
        seriesPlaybackFinishedHandler = nil
        owner = .forYou
        engine.prepare(items: items, index: index)
        engine.play()
    }

    /// 纯函数：解析续播时间。
    /// - handoff > 0 优先。
    /// - 无 handoff 使用 backend。
    /// - ≤0 返回 nil（不 seek）。
    /// - duration - resume ≤ 3 返回 0（从头播放，避免尾帧）。
    static func resolveResumeTime(
        handoff: TimeInterval?,
        backend: TimeInterval?,
        duration: TimeInterval
    ) -> TimeInterval? {
        let raw: TimeInterval?
        if let h = handoff, h > 0 {
            raw = h
        } else if let b = backend, b > 0 {
            raw = b
        } else {
            return nil
        }

        guard let resume = raw, resume > 0 else { return nil }

        if duration > 0, duration - resume <= 3 {
            return 0
        }
        return resume
    }

    /// Series 声明播放权 — 同 item 接管，不同 item fallback。
    /// resume 优先级：显式 handoff > 当前 episode play asset 的 backendResumeTime。
    func claimSeries(
        drama: DramaItem,
        items: [PlayerMediaItem],
        startIndex: Int,
        handoff: PlayerHandoffContext?,
        backendResumeTime: TimeInterval? = nil
    ) {
        guard let targetItem = items[safe: startIndex] else { return }
        let seriesOwner = Owner.series(dramaID: drama.id)
        let targetIdentity = SeriesMediaIdentity(
            dramaID: drama.id,
            episodeNumber: targetItem.episodeNumber ?? max(1, drama.currentEpisode),
            mediaID: targetItem.id
        )

        // 同剧、同集、同媒体的重复申请必须幂等。即使 AVPlayer 尚未 attach，
        // Engine 已记录 currentItem 时也不能再次 deactivate/prepare。
        let isSameStableMedia = owner == seriesOwner
            && currentSeriesIdentity == targetIdentity
            && engine.currentItem?.id == targetItem.id
            && !engine.isPlaybackFailed
        if isSameStableMedia {
            Logger.player.debug("Series 同一稳定媒体重复申请，保留现有播放器")
            engine.play()
            return
        }

        if owner == seriesOwner {
            invalidateCurrentClaim()
            engine.deactivate()
        } else {
            beginSeries(dramaID: drama.id)
        }

        currentSeriesIdentity = targetIdentity
        let targetItemID = targetItem.id
        let token = claimGeneration

        Logger.player.debug("Series 准备新的稳定媒体")
        engine.prepare(items: items, index: startIndex)
        // Series 进入播放页必须立即产生播放意图，不能因为等待 resume/seek 而表现为默认暂停。
        // 如果需要续播，后续在 item ready 后再 seek；首屏体验优先保证快速开始播放。
        engine.play()

        // 确定 resume time：handoff 优先，否则使用后端 resumeTime
        let resolvedResume: TimeInterval?
        if let handoff, handoff.resumeTime > 0 {
            resolvedResume = handoff.resumeTime
        } else if let backend = backendResumeTime, backend > 0 {
            resolvedResume = backend
        } else {
            resolvedResume = nil
        }

        guard let resumeTime = resolvedResume, resumeTime > 0 else { return }

        let targetID = targetItemID
        let eng = engine

        seriesResumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(3)
            while (eng.state == .preparing ||
                   eng.currentPlayer?.currentItem?.status != .readyToPlay),
                  Date() < deadline {
                do { try await Task.sleep(nanoseconds: 100_000_000) }
                catch { return }
                guard !Task.isCancelled,
                      self.isCurrentSeriesClaim(owner: seriesOwner, token: token),
                      eng.currentItem?.id == targetID else { return }
            }
            guard self.isCurrentSeriesClaim(owner: seriesOwner, token: token),
                  eng.currentItem?.id == targetID,
                  eng.state != .preparing,
                  eng.currentPlayer?.currentItem?.status == .readyToPlay else { return }

            // 接近结尾（≤3s）从 0 开始，避免重进只看到尾帧
            let duration = eng.currentPlayer?.currentItem?.duration.seconds ?? 0
            let effectiveResume = Self.resolveResumeTime(
                handoff: handoff?.resumeTime,
                backend: backendResumeTime,
                duration: duration
            )

            if effectiveResume == nil || effectiveResume == 0 {
                eng.play()
            } else if let seekTo = effectiveResume {
                eng.seekTime(seekTo) { [weak self, weak eng] _ in
                    guard let self, let eng,
                          self.isCurrentSeriesClaim(owner: seriesOwner, token: token),
                          eng.currentItem?.id == targetID,
                          eng.state != .preparing else { return }
                    eng.play()
                }
            }
        }
    }

    /// 释放播放权：撤销播放意图并取消所有异步 handoff
    func release(_ owner: Owner) {
        guard self.owner == owner else { return }
        invalidateCurrentClaim()
        if case .series = owner {
            seriesPlaybackFinishedHandler = nil
        }
        currentSeriesIdentity = nil
        engine.deactivate()
        self.owner = nil
        Logger.player.debug("Player ownership released")
    }

    private func invalidateCurrentClaim() {
        seriesResumeTask?.cancel()
        seriesResumeTask = nil
        claimGeneration &+= 1
    }

    private func isCurrentSeriesClaim(owner: Owner, token: Int) -> Bool {
        self.owner == owner && claimGeneration == token
    }

    private func handlePlaybackFinished() {
        switch owner {
        case .forYou:
            if let forYouPlaybackFinishedHandler {
                forYouPlaybackFinishedHandler()
            } else {
                engine.pause(reason: .system)
                engine.seek(to: 0)
            }
        case .series(let dramaID):
            guard let handler = seriesPlaybackFinishedHandler,
                  handler.dramaID == dramaID else {
                engine.pause(reason: .system)
                return
            }
            handler.action()
        case nil:
            engine.deactivate()
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
