import SwiftUI
import AVKit

// MARK: - 推荐页播放会话

/// 推荐页播放状态容器 — 由 MainTabView 持有，RecommendView 注入
/// 解决 NavigationStack push/pop 导致 RecommendView 失去 identity 时状态清零的问题
@MainActor
final class RecommendSession: ObservableObject {
    let pool = PlayerPool()
    let controller = PlayerController()

    @Published var currentIndex = 0
    @Published var hasInitializedPool = false
    @Published var poolVersion = 0

    func initializePool(dramas: [DramaItem]) {
        guard !dramas.isEmpty else { return }
        if let url = dramas[0].videoURL.flatMap(URL.init) {
            pool.setCurrent(url: url)
        }
        preloadAdjacent(for: 0, dramas: dramas)
        hasInitializedPool = true
        poolVersion &+= 1
    }

    func handleTransition(from oldIndex: Int, to newIndex: Int, dramas: [DramaItem]) {
        let count = dramas.count
        guard count > 1 else { return }
        if newIndex > oldIndex { pool.advance() }
        else if newIndex < oldIndex { pool.retreat() }
        preloadAdjacent(for: newIndex, dramas: dramas)
        poolVersion &+= 1
    }

    private func preloadAdjacent(for index: Int, dramas: [DramaItem]) {
        let count = dramas.count
        let nextIdx = index + 1
        if nextIdx < count, let url = dramas[nextIdx].videoURL.flatMap(URL.init) {
            pool.preloadNext(url: url)
        }
        let prevIdx = index - 1
        if prevIdx >= 0, let url = dramas[prevIdx].videoURL.flatMap(URL.init) {
            pool.preloadPrevious(url: url)
        }
    }

    func cleanup() {
        controller.cleanup()
        pool.cleanup()
    }
}

// MARK: - 三实例播放器池

/// 预加载上一个/下一个视频，支持无缝切换
/// 池内 3 个 AVPlayer：[prev, current, next]，滑动手势触发 advance/retreat
final class PlayerPool {
    private var pool: [AVPlayer?] = [nil, nil, nil]

    var current: AVPlayer? { pool[1] }
    var hasNext: Bool { pool[2] != nil }
    var hasPrevious: Bool { pool[0] != nil }

    @discardableResult
    func setCurrent(url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)
        pool[1] = player
        return player
    }

    func preloadNext(url: URL) {
        pool[2]?.pause()
        pool[2] = AVPlayer(url: url)
    }

    func preloadPrevious(url: URL) {
        pool[0]?.pause()
        pool[0] = AVPlayer(url: url)
    }

    /// 下翻：prev←current, current←next, next←nil
    @discardableResult
    func advance() -> AVPlayer? {
        pool[0]?.pause()
        pool[1]?.pause() // 暂停旧 current，避免后台继续播放
        pool[0] = pool[1]
        pool[1] = pool[2]
        pool[2] = nil
        return pool[1]
    }

    /// 上翻：next←current, current←prev, prev←nil
    @discardableResult
    func retreat() -> AVPlayer? {
        pool[2]?.pause()
        pool[1]?.pause() // 暂停旧 current，避免后台继续播放
        pool[2] = pool[1]
        pool[1] = pool[0]
        pool[0] = nil
        return pool[1]
    }

    func cleanup() {
        for p in pool { p?.pause() }
        pool = [nil, nil, nil]
    }

    deinit { cleanup() }
}

// MARK: - 视频播放控制器

/// 视频播放状态管理器 — 管理 AVPlayer，暴露播放状态给 SwiftUI
/// 与 PlayerPool 协作：attach 绑定池的 current 播放器，池 rotate 后重新 attach
final class PlayerController: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var hasStartedPlayingOnce: Bool = false
    @Published var isUserPaused: Bool = false
    @Published var bufferProgress: Double = 0
    @Published var thumbnailImage: UIImage?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemEndObserver: Any?
    private var thumbnailGenerator: AVAssetImageGenerator?
    private var thumbnailTask: Task<Void, Never>?

    /// 播放结束回调 — 用于自动连播
    var onPlaybackFinished: (() -> Void)?

    /// 绑定播放器实例（由 VideoPlayerLayer 调用）
    func attach(player: AVPlayer) {
        detach()
        self.player = player
        player.play()
        hasStartedPlayingOnce = true
        isUserPaused = false
        startObserving()
    }

    /// 仅移除观察者，不暂停播放器（池 rotate 时使用）
    func detach() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
        if let obs = itemEndObserver { NotificationCenter.default.removeObserver(obs); itemEndObserver = nil }
        player = nil
    }

    /// 切换播放 / 暂停
    func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isUserPaused = true
        } else {
            player.play()
            isUserPaused = false
        }
    }

    /// 设置播放倍速
    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    /// 拖动跳转到指定进度 (0~1)
    func seek(to fraction: Double) {
        guard let player = player, let item = player.currentItem,
              item.duration.isNumeric else { return }
        let clamped = max(0, min(1, fraction))
        let target = CMTime(seconds: clamped * item.duration.seconds,
                            preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target.seconds
    }

    /// 异步生成指定进度位置的缩略图 (0~1)，结果写入 thumbnailImage
    func generateThumbnail(at fraction: Double) {
        guard let player = player, let asset = player.currentItem?.asset else { return }
        let clamped = max(0, min(1, fraction))
        if thumbnailGenerator == nil {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 128, height: 72)
            thumbnailGenerator = gen
        }
        guard let gen = thumbnailGenerator else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration > 0 else { return }
        let time = CMTime(seconds: clamped * duration, preferredTimescale: 600)
        thumbnailTask?.cancel()
        thumbnailTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let (cgImage, _) = try await gen.image(at: time)
                self.thumbnailImage = UIImage(cgImage: cgImage)
            } catch {
                // Cancellation or generation failure — ignore
            }
        }
    }

    /// 仅暂停播放，保留观察者和播放器引用（Tab 切换时使用）
    func pause() {
        player?.pause()
        isUserPaused = true
    }

    /// 恢复播放（Tab 切回时使用）
    func play() {
        player?.play()
        isUserPaused = false
    }

    /// 释放播放器资源
    func cleanup() {
        player?.pause()
        detach()
    }

    // MARK: - 私有方法

    private func startObserving() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, let player = self.player else { return }
            self.currentTime = time.seconds
            if let item = player.currentItem, item.duration.isNumeric {
                self.duration = item.duration.seconds
                if let range = item.loadedTimeRanges.first?.timeRangeValue {
                    let buffered = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
                    self.bufferProgress = self.duration > 0 ? buffered / self.duration : 0
                }
            }
            self.isPlaying = player.timeControlStatus == .playing
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.onPlaybackFinished?()
        }
    }

    deinit { cleanup() }
}

// MARK: - 视频播放视图

/// 视频播放层 + 封面 fallback
/// - 有播放器 + 有控制器：AVPlayerLayer 播放，支持暂停/播放速度控制
/// - 无控制器：仅显示封面图（非当前视频）
struct VideoPlayerView: View {
    let coverURL: String
    let player: AVPlayer?
    var controller: PlayerController?

    @StateObject private var loader = ImageLoader()

    var body: some View {
        ZStack {
            Color.black

            // 视频播放层（仅当有控制器且有播放器时）
            if let player, let controller {
                VideoPlayerLayer(player: player, controller: controller)
            }

            // 封面层 — 播放器未开始播放或没有播放器时始终显示
            if shouldShowCover {
                coverView
                    .transition(.opacity)
            }

            // 暂停图标 — ZStack 顶层，确保不被封面/视频层遮挡
            if let controller, controller.hasStartedPlayingOnce && controller.isUserPaused {
                Image(systemName: "play.circle.fill")
                    .font(DT.Font.largeTitle(60))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(color: .black.opacity(0.4), radius: 8)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: shouldShowCover)
        .animation(.easeInOut(duration: 0.2), value: controller?.isUserPaused)
        .task { await loader.load(coverURL) }
    }

    /// 是否应该显示封面 — 无播放器时或尚未开始播放时
    private var shouldShowCover: Bool {
        if player == nil { return true }
        if let controller, !controller.hasStartedPlayingOnce { return true }
        return false
    }

    /// 封面图 — 无视频时或有视频但尚未开始播放时显示
    @ViewBuilder
    private var coverView: some View {
        if let image = loader.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [DT.Color.bgCoverPlaceholderStart, DT.Color.bgCoverPlaceholderEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    ProgressView().tint(DT.Color.textSecondary)
                )
        }
    }
}

// MARK: - AVPlayerLayer UIViewRepresentable

/// 视频播放层 — 接收池提供的 AVPlayer，不自行创建
private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    let controller: PlayerController

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.isUserInteractionEnabled = false
        (view.layer as? AVPlayerLayer)?.player = player
        (view.layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        controller.attach(player: player)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        let avLayer = uiView.layer as? AVPlayerLayer
        if avLayer?.player !== player {
            avLayer?.player = player
            avLayer?.videoGravity = .resizeAspectFill
            controller.attach(player: player)
        }
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        (uiView.layer as? AVPlayerLayer)?.player = nil
    }
}

// MARK: - Player UIView

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let playerLayer = layer as? AVPlayerLayer else { return }
        playerLayer.frame = bounds
    }
}
