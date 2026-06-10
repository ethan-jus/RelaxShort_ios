import SwiftUI
import AVKit
import Network
import Combine

// MARK: - 推荐页播放会话（迁移壳 — 委托给 ShortVideoPlayerEngine）

// MARK: - 推荐页播放会话（唯一 engine，无旧 pool/controller）

@MainActor final class RecommendSession: ObservableObject {
    /// 共享 engine — 由 PlayerCoordinator 提供，不再自己创建
    private var _engine: ShortVideoPlayerEngine?
    var engine: ShortVideoPlayerEngine {
        get { _engine! }
        set {
            _engine = newValue
            // 订阅共享 engine 的变化，转发到 session 的 objectWillChange
            engineSink?.cancel()
            engineSink = newValue.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
    @Published var currentIndex = 0
    @Published var hasInitializedPool = false
    @Published var poolVersion = 0
    private var engineSink: AnyCancellable?

    func initializePool(dramas: [DramaItem]) {
        guard !dramas.isEmpty else { return }
        let items = dramas.map { $0.toPlayerMediaItem() }
        engine.prepare(items: items, index: 0)
        engine.play()
        hasInitializedPool = true; poolVersion &+= 1
    }

    func handleTransition(from old: Int, to new: Int, dramas: [DramaItem]) {
        guard old != new else { return }
        currentIndex = new
        engine.move(to: new)
        poolVersion &+= 1
    }

    func cleanup() {}
}

// MARK: - 视频播放视图（engine 壳 — 不允许内部 new engine）

struct VideoPlayerView: View {
    let coverURL: String; let engine: ShortVideoPlayerEngine; let isCurrent: Bool
    var body: some View {
        ShortVideoPlayerView(player: isCurrent ? engine.currentPlayer : nil, coverURL: coverURL, engine: engine)
    }
}

// MARK: - DramaItem → PlayerMediaItem 映射

extension PlayerMediaItem {
    /// 统一稳定 ID：For You 和 Series 使用同一规则
    static func stableID(dramaID: String, episodeNumber: Int) -> String {
        "\(dramaID)-\(episodeNumber)"
    }
}

extension DramaItem {
    func toPlayerMediaItem() -> PlayerMediaItem {
        let source: PlayerMediaSource = videoURL.flatMap(URL.init).map { .mp4($0) } ?? .mp4(URL(string: "about:blank")!)
        return PlayerMediaItem(
            id: PlayerMediaItem.stableID(dramaID: id, episodeNumber: currentEpisode),
            title: title, episodeNumber: currentEpisode,
            coverURL: coverURL, source: source, resumeTime: nil
        )
    }
}
