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

    private var seriesResumeTask: Task<Void, Never>?
    private var forYouPlaybackFinishedHandler: (@MainActor () -> Void)?
    private var seriesPlaybackFinishedHandler: (dramaID: String, action: @MainActor () -> Void)?
    private var claimGeneration: Int = 0

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

    /// For You 声明播放权 — 同 item 不重建
    func claimForYou(items: [PlayerMediaItem], index: Int) {
        let targetID = items[safe: index]?.id ?? ""
        if owner == .forYou, engine.currentItem?.id == targetID {
            engine.play(); return
        }
        invalidateCurrentClaim()
        seriesPlaybackFinishedHandler = nil
        owner = .forYou
        engine.prepare(items: items, index: index)
        engine.play()
    }

    /// Series 声明播放权 — 同 item 接管，不同 item fallback
    func claimSeries(
        drama: DramaItem,
        items: [PlayerMediaItem],
        startIndex: Int,
        handoff: PlayerHandoffContext?
    ) {
        let seriesOwner = Owner.series(dramaID: drama.id)
        if owner == seriesOwner {
            invalidateCurrentClaim()
        } else {
            beginSeries(dramaID: drama.id)
        }
        let targetItemID = items[safe: startIndex]?.id ?? ""
        let targetItem = items[safe: startIndex]
        let currentMatches = engine.currentItem == targetItem
        let token = claimGeneration

        if currentMatches, engine.currentPlayer != nil, engine.state != .preparing {
            Logger.player.debug("Series reuses current media item")
            engine.play(); return
        }

        Logger.player.debug("Series prepares a new media item")
        engine.deactivate()
        engine.prepare(items: items, index: startIndex)

        guard let handoff, handoff.resumeTime > 0 else {
            engine.play(); return
        }

        let resumeTime = handoff.resumeTime
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

            eng.seekTime(resumeTime) { [weak self, weak eng] _ in
                guard let self, let eng,
                      self.isCurrentSeriesClaim(owner: seriesOwner, token: token),
                      eng.currentItem?.id == targetID,
                      eng.state != .preparing else { return }
                eng.play()
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
