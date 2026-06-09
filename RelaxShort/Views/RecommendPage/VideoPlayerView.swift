import SwiftUI
import AVKit
import Network

// MARK: - 推荐页播放会话（迁移壳 — 委托给 ShortVideoPlayerEngine）

@MainActor final class RecommendSession: ObservableObject {
    let engine = ShortVideoPlayerEngine()
    let pool = PlayerPool()
    let controller = PlayerController()
    @Published var currentIndex = 0 { didSet { if oldValue != currentIndex { engine.move(to: currentIndex) } } }
    @Published var hasInitializedPool = false
    @Published var poolVersion = 0

    func initializePool(dramas: [DramaItem]) {
        guard !dramas.isEmpty else { return }
        let items = dramas.map { $0.toPlayerMediaItem() }
        engine.prepare(items: items, index: 0)
        hasInitializedPool = true; poolVersion &+= 1
    }
    func handleTransition(from old: Int, to new: Int, dramas: [DramaItem]) { poolVersion &+= 1 }
    func cleanup() { engine.cleanup() }
}

// MARK: - 兼容层（旧代码引用）

@MainActor final class PlayerPool {
    var current: AVPlayer? { nil }
    func setCurrent(url: URL) -> AVPlayer { AVPlayer(url: url) }
    func preloadNext(url: URL) {}
    func preloadPrevious(url: URL) {}
    func advance() -> AVPlayer? { nil }
    func retreat() -> AVPlayer? { nil }
    func cleanup() {}
}

@MainActor final class PlayerController: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var hasStartedPlayingOnce: Bool = false
    @Published var pauseReason: PlayerPauseReason = .none
    @Published var bufferProgress: Double = 0
    @Published var thumbnailImage: UIImage?
    var onPlaybackFinished: (() -> Void)?
    func attach(player: AVPlayer) {}
    func detach() {}
    func togglePlayPause() {}
    func pauseForSystem() {}
    func pauseByUser() {}
    func playFromSystemResume() {}
    func playAfterAttach() {}
    func pause() {}
    func play() {}
    func setRate(_ rate: Float) {}
    func resetForNewPlayer() {}
    func cleanup() {}
    func seek(to fraction: Double) {}
    func generateThumbnail(at fraction: Double) {}
}

// MARK: - 视频播放视图（旧兼容壳）

struct VideoPlayerView: View {
    let coverURL: String; let player: AVPlayer?; var controller: PlayerController?
    @StateObject private var l = ImageLoader()
    var body: some View {
        ShortVideoPlayerView(player: player, coverURL: coverURL, engine: ShortVideoPlayerEngine())
            .task { await l.load(coverURL) }
    }
}

// MARK: - DramaItem → PlayerMediaItem 映射

extension DramaItem {
    func toPlayerMediaItem() -> PlayerMediaItem {
        let source: PlayerMediaSource = videoURL.flatMap(URL.init).map { .mp4($0) } ?? .mp4(URL(string: "about:blank")!)
        return PlayerMediaItem(id: id, title: title, episodeNumber: currentEpisode, coverURL: coverURL, source: source, resumeTime: nil)
    }
}
