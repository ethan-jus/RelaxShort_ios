import SwiftUI

// MARK: - Navigation Routes

/// 剧集播放导航目标（NavigationStack push 用）
struct SeriesPlayerNav: Hashable {
    let drama: DramaItem
    let startEpisode: Int
    let episodeID: String?
    let resumeTime: TimeInterval?
    let handoff: PlayerHandoffContext?
    let sourceScene: String

    init(
        drama: DramaItem,
        startEpisode: Int,
        episodeID: String? = nil,
        resumeTime: TimeInterval? = nil,
        handoff: PlayerHandoffContext? = nil,
        sourceScene: String = "unknown"
    ) {
        self.drama = drama
        self.startEpisode = startEpisode
        // 普通卡片导航默认保留后端 preview_episode_id；历史/收藏显式指定时仍以显式值优先。
        self.episodeID = episodeID ?? drama.previewEpisodeID
        self.resumeTime = resumeTime
        self.handoff = handoff
        self.sourceScene = sourceScene
    }
}
