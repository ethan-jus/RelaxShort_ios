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
    @Published private(set) var engine = ShortVideoPlayerEngine()

    /// For You 声明播放权 — 同 item 不重建
    func claimForYou(items: [PlayerMediaItem], index: Int) {
        let targetID = items[safe: index]?.id ?? ""
        if owner == .forYou, engine.currentItem?.id == targetID {
            engine.play()
            return
        }
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
        owner = .series(dramaID: drama.id)
        let targetItemID = items[safe: startIndex]?.id ?? ""
        let currentMatches = engine.currentItem?.id == targetItemID

        if currentMatches {
            print("[PlayerKit] handoff reuse current player id=\(targetItemID)")
            return
        }

        print("[PlayerKit] handoff fallback prepare id=\(targetItemID)")
        engine.prepare(items: items, index: startIndex)

        if let handoff, handoff.resumeTime > 0 {
            let wasPlaying = handoff.wasPlaying
            let resumeTime = handoff.resumeTime
            let eng = engine
            Task { @MainActor in
                var didStart = false
                var obs: NSKeyValueObservation?
                obs = eng.currentPlayer?.currentItem?.observe(\.status, options: [.new]) { item, _ in
                    guard item.status == .readyToPlay else { return }
                    obs?.invalidate()
                    Task { @MainActor in
                        guard !didStart else { return }; didStart = true
                        eng.seekTime(resumeTime) { _ in if wasPlaying { eng.play() } }
                    }
                }
                // 如果已经 ready
                if !didStart, eng.currentPlayer?.currentItem?.status == .readyToPlay {
                    didStart = true
                    eng.seekTime(resumeTime) { _ in if wasPlaying { eng.play() } }
                }
                // 超时兜底
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !didStart {
                    didStart = true
                    eng.seekTime(resumeTime) { _ in if wasPlaying { eng.play() } }
                }
            }
        } else {
            engine.play()
        }
    }

    /// 释放播放权 — 返回 For You 时不清理，只改变 owner
    func release(_ owner: Owner) {
        if case .series = owner {
            // 从 Series 返回 → 恢复 For You 所有权，不清理 engine
            self.owner = .forYou
        } else if self.owner == owner {
            self.owner = nil
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
