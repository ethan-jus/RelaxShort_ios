import SwiftUI

// MARK: - Navigation Routes

/// 剧集播放导航目标（NavigationStack push 用）
struct SeriesPlayerNav: Hashable {
    let drama: DramaItem
    let startEpisode: Int
}
