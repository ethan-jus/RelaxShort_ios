import SwiftUI

// MARK: - Navigation Routes

/// 剧集播放导航目标（NavigationStack push 用）
struct SeriesPlayerNav: Hashable {
    let drama: DramaItem
    let startEpisode: Int
    let resumeTime: TimeInterval?
    let handoff: PlayerHandoffContext?

    init(drama: DramaItem, startEpisode: Int, resumeTime: TimeInterval? = nil, handoff: PlayerHandoffContext? = nil) {
        self.drama = drama
        self.startEpisode = startEpisode
        self.resumeTime = resumeTime
        self.handoff = handoff
    }
}
