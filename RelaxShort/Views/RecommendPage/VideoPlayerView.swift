import SwiftUI
import AVKit
import Network

// MARK: - 推荐页播放会话（迁移壳 — 委托给 ShortVideoPlayerEngine）

// MARK: - 推荐页播放会话（唯一 engine，无旧 pool/controller）

@MainActor final class RecommendSession: ObservableObject {
    let engine = ShortVideoPlayerEngine()
    @Published var currentIndex = 0
    @Published var hasInitializedPool = false
    @Published var poolVersion = 0

    func initializePool(dramas: [DramaItem]) {
        guard !dramas.isEmpty else { return }
        let items = dramas.map { $0.toPlayerMediaItem() }
        engine.prepare(items: items, index: 0)
        engine.play()  // 设置播放意图，prepare 异步完成后自动播放
        hasInitializedPool = true; poolVersion &+= 1
    }

    func handleTransition(from old: Int, to new: Int, dramas: [DramaItem]) {
        guard old != new else { return }
        currentIndex = new
        engine.move(to: new)
        poolVersion &+= 1
    }

    func cleanup() { engine.cleanup() }
}

// MARK: - 视频播放视图（engine 壳 — 不允许内部 new engine）

struct VideoPlayerView: View {
    let coverURL: String; let engine: ShortVideoPlayerEngine; let isCurrent: Bool
    var body: some View {
        ShortVideoPlayerView(player: isCurrent ? engine.currentPlayer : nil, coverURL: coverURL, engine: engine)
    }
}

// MARK: - DramaItem → PlayerMediaItem 映射

extension DramaItem {
    func toPlayerMediaItem() -> PlayerMediaItem {
        let source: PlayerMediaSource = videoURL.flatMap(URL.init).map { .mp4($0) } ?? .mp4(URL(string: "about:blank")!)
        return PlayerMediaItem(id: id, title: title, episodeNumber: currentEpisode, coverURL: coverURL, source: source, resumeTime: nil)
    }
}
