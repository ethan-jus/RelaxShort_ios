import SwiftUI

// MARK: - 播放协调器

/// 持有唯一的 ShortVideoPlayerEngine，管理 For You / Series 之间的播放权转移
@MainActor
final class PlayerCoordinator: ObservableObject {

    enum Owner: Hashable {
        case forYou
        case series(dramaID: String)
    }

    @Published private(set) var owner: Owner?
    @Published private(set) var engine: ShortVideoPlayerEngine

    /// Series 同集复用不仅要比较 mediaID；跨剧 ID 冲突或切集后的迟到回调都不能接管当前播放器。
    private struct SeriesMediaIdentity: Equatable {
        let dramaID: String
        let episodeNumber: Int?
        let mediaID: String
    }

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
        seriesPlaybackFinishedHandler = nil
        currentSeriesIdentity = nil
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

    /// For You 分页只能在其持有播放权时追加到共享引擎。
    /// Series 播放期间页面仍可能收到分页回调，此时只更新页面模型，不得污染 Series 队列。
    func appendForYouItems(_ items: [PlayerMediaItem]) {
        guard owner == .forYou else { return }
        engine.appendItems(items)
    }

    /// For You 翻页的唯一入口。所有权校验保证 Series 当前媒体不会被后台页面替换。
    func moveForYou(to index: Int, autoplay: Bool) {
        guard owner == .forYou else { return }
        engine.move(to: index, autoplay: autoplay)
    }

    /// Series 切集的统一起点。先让旧媒体彻底失效，再返回本次请求令牌。
    /// 手势、选集和自动下一集都必须使用该入口。
    func beginSeriesEpisodeTransition(dramaID: String) -> Int? {
        let seriesOwner = Owner.series(dramaID: dramaID)
        guard owner == seriesOwner else { return nil }
        invalidateCurrentClaim()
        currentSeriesIdentity = nil
        engine.beginContentTransition(autoplay: true)
        return claimGeneration
    }

    /// 异步播放源返回前校验请求令牌，防止旧请求覆盖用户后来选择的剧集。
    func isCurrentSeriesEpisodeTransition(dramaID: String, token: Int?) -> Bool {
        guard let token else { return false }
        return isCurrentSeriesClaim(owner: .series(dramaID: dramaID), token: token)
    }

    /// 只有当前最新切集请求可以提交播放器，迟到请求不得覆盖新目标。
    @discardableResult
    func commitSeriesEpisodeTransition(
        drama: DramaItem,
        items: [PlayerMediaItem],
        startIndex: Int,
        handoff: PlayerHandoffContext?,
        backendResumeTime: TimeInterval? = nil,
        token: Int
    ) -> Bool {
        guard isCurrentSeriesEpisodeTransition(dramaID: drama.id, token: token) else {
            Logger.player.debug("忽略迟到的 Series 切集提交 剧ID=\(drama.id)")
            return false
        }
        guard let targetItem = items[safe: startIndex] else { return false }
        currentSeriesIdentity = SeriesMediaIdentity(
            dramaID: drama.id,
            episodeNumber: targetItem.episodeNumber,
            mediaID: targetItem.id
        )
        engine.commitContentTransition(
            items: items,
            index: startIndex,
            autoplay: true
        )
        scheduleSeriesResume(
            owner: .series(dramaID: drama.id),
            token: token,
            targetID: targetItem.id,
            handoff: handoff,
            backendResumeTime: backendResumeTime
        )
        return true
    }

    /// Series 页面只负责提前取得播放合同；媒体预加载统一交给共享 Engine/SlotPool。
    func updateSeriesPlaylist(dramaID: String, items: [PlayerMediaItem]) {
        guard owner == .series(dramaID: dramaID) else { return }
        engine.updatePlaylistKeepingCurrent(items)
    }

    /// For You 声明播放权 — 同 item 不重建
    func claimForYou(items: [PlayerMediaItem], index: Int) {
        guard let targetItem = items[safe: index] else { return }
        let targetID = targetItem.id
        if owner == .forYou, engine.currentItem?.id == targetID {
            engine.play(); return
        }
        invalidateCurrentClaim()
        seriesPlaybackFinishedHandler = nil
        if owner != .forYou {
            engine.deactivate()
        }
        owner = .forYou
        engine.prepare(items: items, index: index)
        engine.play()
    }

    /// For You feed 整体替换的唯一入口。
    /// 即使当前媒体 ID 未变化，也必须替换 Engine 的完整 playlist，避免新 UI feed
    /// 与旧 Engine items 混用。该语义不同于 resume 场景的 claimForYou 同媒体复用。
    func replaceForYouPlaylist(items: [PlayerMediaItem], index: Int, autoplay: Bool) {
        guard items.indices.contains(index) else { return }

        invalidateCurrentClaim()
        seriesPlaybackFinishedHandler = nil
        if owner != .forYou {
            engine.deactivate()
        }
        owner = .forYou
        engine.prepare(items: items, index: index)
        if autoplay {
            engine.play()
        }
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
        let alreadyOwnedSeries = owner == seriesOwner
        let targetIdentity = SeriesMediaIdentity(
            dramaID: drama.id,
            episodeNumber: targetItem.episodeNumber,
            mediaID: targetItem.id
        )

        // 同一剧、同一集、同一媒体可以复用 AVPlayer；若随后拿到正式 /play 源，
        // 引擎只替换 AVPlayerItem，不重建 player、不清空首帧和进度状态。
        if alreadyOwnedSeries,
           currentSeriesIdentity == targetIdentity,
           engine.currentItem?.id == targetItem.id {
            let upgraded = engine.upgradeCurrentSource(to: targetItem)
            engine.updatePlaylistKeepingCurrent(items)
            if upgraded {
                Logger.player.debug("Series 同集已升级为正式播放源，保留当前播放器与续播进度")
            } else {
                Logger.player.debug("Series 同一集继续复用当前播放器")
            }
            engine.play()
            return
        }

        Logger.player.debug("Series 准备新的播放媒体")
        if alreadyOwnedSeries {
            invalidateCurrentClaim()
            engine.deactivate()
        }
        if !alreadyOwnedSeries {
            beginSeries(dramaID: drama.id)
        }
        currentSeriesIdentity = targetIdentity
        let token = claimGeneration
        engine.prepare(items: items, index: startIndex)
        // Series 进入播放页必须立即产生播放意图，不能因为等待 resume/seek 而表现为默认暂停。
        // 如果需要续播，后续在 item ready 后再 seek；首屏体验优先保证快速开始播放。
        engine.play()

        scheduleSeriesResume(
            owner: seriesOwner,
            token: token,
            targetID: targetItem.id,
            handoff: handoff,
            backendResumeTime: backendResumeTime
        )
    }

    private func scheduleSeriesResume(
        owner seriesOwner: Owner,
        token: Int,
        targetID: String,
        handoff: PlayerHandoffContext?,
        backendResumeTime: TimeInterval?
    ) {
        let hasResumeTime = (handoff?.resumeTime ?? 0) > 0 || (backendResumeTime ?? 0) > 0
        guard hasResumeTime else { return }
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
            currentSeriesIdentity = nil
        }
        engine.deactivate()
        self.owner = nil
        Logger.player.debug("播放器所有权已释放")
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
