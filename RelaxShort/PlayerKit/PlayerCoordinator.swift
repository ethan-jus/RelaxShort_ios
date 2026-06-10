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

    /// For You 声明播放权
    func claimForYou(items: [PlayerMediaItem], index: Int) {
        owner = .forYou
        engine.prepare(items: items, index: index)
        engine.play()
    }

    /// Series 声明播放权 — handoff 场景：如果 engine 当前 item 匹配，直接接管不重建
    func claimSeries(
        drama: DramaItem,
        items: [PlayerMediaItem],
        startIndex: Int,
        handoff: PlayerHandoffContext?
    ) {
        owner = .series(dramaID: drama.id)

        // 接管判断：engine 当前 item id 与目标剧集匹配
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
                var obs: NSKeyValueObservation?
                obs = eng.currentPlayer?.currentItem?.observe(\.status, options: [.new]) { item, _ in
                    guard item.status == .readyToPlay else { return }
                    obs?.invalidate()
                    Task { @MainActor in
                        eng.seekTime(resumeTime) { _ in
                            if wasPlaying { eng.play() }
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                obs?.invalidate()
            }
        } else {
            engine.play()
        }
    }

    func release(_ owner: Owner) {
        if self.owner == owner { self.owner = nil }
        engine.cleanup()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
