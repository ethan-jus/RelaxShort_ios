import SwiftUI
import AVKit
import Combine

// MARK: - 推荐页播放会话

/// 推荐页播放状态容器 — 由外层标签页持有，并注入推荐页
/// 解决导航入栈或出栈导致推荐页身份变化时状态清零的问题
@MainActor
final class RecommendSession: ObservableObject {
    let pool = PlayerPool()
    let controller = PlayerController()

    @Published var currentIndex = 0
    @Published var hasInitializedPool = false
    @Published var poolVersion = 0

    private var cancellables: Set<AnyCancellable> = []

    init() {
        controller.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

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
/// 池内三个播放器分别对应上一个、当前、下一个视频，滑动手势触发前进或后退
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

    /// 下翻：上一个←当前，当前←下一个，下一个←空
    @discardableResult
    func advance() -> AVPlayer? {
        pool[0]?.pause()
        pool[1]?.pause() // 暂停旧当前播放器，避免后台继续播放
        pool[0] = pool[1]
        pool[1] = pool[2]
        pool[2] = nil
        return pool[1]
    }

    /// 上翻：下一个←当前，当前←上一个，上一个←空
    @discardableResult
    func retreat() -> AVPlayer? {
        pool[2]?.pause()
        pool[1]?.pause() // 暂停旧当前播放器，避免后台继续播放
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

// MARK: - 暂停原因

enum PauseReason: Hashable {
    case none
    case user
    case system
}

// MARK: - 视频播放控制器

final class PlayerController: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var hasStartedPlayingOnce: Bool = false
    @Published var pauseReason: PauseReason = .none
    @Published var bufferProgress: Double = 0
    @Published var thumbnailImage: UIImage?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemEndObserver: Any?
    private var thumbnailGenerator: AVAssetImageGenerator?
    private var thumbnailTask: Task<Void, Never>?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var pendingPlay = false

    var onPlaybackFinished: (() -> Void)?

    /// 仅绑定播放器，不自动播放
    func attach(player: AVPlayer) {
        if self.player === player { return }
        detach()
        self.player = player
        isPlaying = player.timeControlStatus == .playing
        startObserving()
        if pendingPlay || pauseReason == .none {
            playWhenReady()
        }
    }

    /// 绑定后显式播放，仅由生命周期控制触发
    func playAfterAttach() {
        playWhenReady()
        hasStartedPlayingOnce = true
        pauseReason = .none
    }

    func detach() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
        if let obs = itemEndObserver { NotificationCenter.default.removeObserver(obs); itemEndObserver = nil }
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        player = nil
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            pauseByUser()
        } else {
            playWhenReady()
            hasStartedPlayingOnce = true
            pauseReason = .none
        }
    }

    func pauseForSystem() {
        pendingPlay = false
        player?.pause()
        if pauseReason != .user { pauseReason = .system }
        isPlaying = false
    }

    func pauseByUser() {
        pendingPlay = false
        player?.pause()
        pauseReason = .user
        isPlaying = false
    }

    func playFromSystemResume() {
        guard pauseReason != .user else { return }
        playWhenReady()
        pauseReason = .none
    }

    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    func seek(to fraction: Double) {
        guard let player = player, let item = player.currentItem,
              item.duration.isNumeric else { return }
        let clamped = max(0, min(1, fraction))
        let target = CMTime(seconds: clamped * item.duration.seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target.seconds
    }

    func generateThumbnail(at fraction: Double) {
        guard let player = player, let asset = player.currentItem?.asset else { return }
        if thumbnailGenerator == nil {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 336, height: 480)
            thumbnailGenerator = gen
        }
        guard let gen = thumbnailGenerator else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration > 0 else { return }
        let time = CMTime(seconds: CGFloat(fraction) * duration, preferredTimescale: 600)
        thumbnailTask?.cancel()
        thumbnailTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let (cgImage, _) = try await gen.image(at: time)
                self.thumbnailImage = UIImage(cgImage: cgImage)
            } catch { }
        }
    }

    func pause() { pauseForSystem() }
    func play() { playFromSystemResume() }

    /// 切换到新播放器前重置旧进度状态
    func resetForNewPlayer() {
        currentTime = 0
        duration = 0
        bufferProgress = 0
        thumbnailImage = nil
        hasStartedPlayingOnce = false
        isPlaying = false
    }

    func cleanup() {
        pendingPlay = false
        player?.pause()
        detach()
    }

    // MARK: - 私有方法

    private func startObserving() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
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
        }

        timeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak player] _, _ in
            DispatchQueue.main.async {
                guard let self, let player, self.player === player else { return }
                self.updatePlayingState(for: player)
            }
        }

        statusObserver = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if item.duration.isNumeric {
                    self.duration = item.duration.seconds
                }
                if item.status == .readyToPlay, self.pendingPlay, self.pauseReason != .user {
                    player.play()
                    self.pendingPlay = false
                    self.hasStartedPlayingOnce = true
                }
            }
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

    private func playWhenReady() {
        guard let player = player else {
            pendingPlay = true
            return
        }
        pendingPlay = true
        if player.currentItem?.status == .readyToPlay {
            player.play()
            pendingPlay = false
        } else if player.currentItem?.status == .unknown {
            player.play()
        } else if player.currentItem?.status == .failed {
            pendingPlay = false
        }
    }

    /// 同步当前播放器播放态，避免旧播放器异步回调覆盖封面显隐
    private func updatePlayingState(for player: AVPlayer) {
        isPlaying = player.timeControlStatus == .playing
    }

    deinit { cleanup() }
}

// MARK: - 视频播放视图

/// 视频播放层和封面兜底
/// - 有播放器和控制器：使用系统播放层播放，支持暂停和播放速度控制
/// - 无控制器：仅显示封面图（非当前视频）
struct VideoPlayerView: View {
    let coverURL: String
    let player: AVPlayer?
    var controller: PlayerController?
    var shouldPlay: Bool = false

    var body: some View {
        if let player, let controller {
            ActiveVideoPlayerView(
                coverURL: coverURL,
                player: player,
                controller: controller,
                shouldPlay: shouldPlay
            )
        } else {
            CoverOnlyVideoView(coverURL: coverURL)
        }
    }
}

// MARK: - 当前视频播放视图

/// 当前视频播放视图 — 直接订阅播放器控制器，播放态变化时立即刷新封面显隐
private struct ActiveVideoPlayerView: View {
    let coverURL: String
    let player: AVPlayer
    @ObservedObject var controller: PlayerController
    let shouldPlay: Bool

    @StateObject private var loader = ImageLoader()
    @State private var hasShownPlayback = false

    private var playerID: ObjectIdentifier {
        ObjectIdentifier(player)
    }

    var body: some View {
        ZStack {
            Color.black

            VideoPlayerLayer(
                player: player,
                controller: controller,
                shouldPlay: shouldPlay
            )

            if shouldShowCover {
                coverView
            }
        }
        .animation(.easeInOut(duration: 0.18), value: hasShownPlayback)
        .onChange(of: playerID) { _, _ in
            hasShownPlayback = false
        }
        .onChange(of: controller.isPlaying, initial: true) { _, isPlaying in
            if isPlaying {
                hasShownPlayback = true
            }
        }
        .task(id: coverURL) { await loader.load(coverURL) }
    }

    /// 是否应该显示封面 — 仅用于首次播放前遮住黑屏，暂停后不再显示
    private var shouldShowCover: Bool {
        !hasShownPlayback
    }

    /// 封面图 — 首次播放前显示，视频开始后不再盖回去
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

// MARK: - 非当前视频封面视图

/// 非当前页只显示封面，避免无关页面创建播放层
private struct CoverOnlyVideoView: View {
    let coverURL: String

    @StateObject private var loader = ImageLoader()

    var body: some View {
        ZStack {
            Color.black
            coverView
        }
        .task(id: coverURL) { await loader.load(coverURL) }
    }

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

// MARK: - 系统播放层桥接视图

/// 视频播放层 — 接收池提供的播放器，不自行创建
private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    let controller: PlayerController
    let shouldPlay: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.isUserInteractionEnabled = false
        (view.layer as? AVPlayerLayer)?.player = player
        (view.layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        context.coordinator.applyPlaybackIntent(controller: controller, player: player, shouldPlay: shouldPlay)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        let avLayer = uiView.layer as? AVPlayerLayer
        if avLayer?.player !== player {
            avLayer?.player = player
            avLayer?.videoGravity = .resizeAspectFill
        }
        context.coordinator.applyPlaybackIntent(controller: controller, player: player, shouldPlay: shouldPlay)
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: Coordinator) {
        coordinator.invalidate()
        (uiView.layer as? AVPlayerLayer)?.player = nil
    }

    final class Coordinator {
        private var lastPlayerID: ObjectIdentifier?
        private var lastShouldPlay: Bool?

        func applyPlaybackIntent(controller: PlayerController, player: AVPlayer, shouldPlay: Bool) {
            let playerID = ObjectIdentifier(player)
            guard lastPlayerID != playerID || lastShouldPlay != shouldPlay else { return }
            lastPlayerID = playerID
            lastShouldPlay = shouldPlay
            DispatchQueue.main.async {
                controller.attach(player: player)
                if shouldPlay {
                    controller.playAfterAttach()
                } else if controller.pauseReason != .user {
                    controller.pauseForSystem()
                }
            }
        }

        func invalidate() {
            lastPlayerID = nil
            lastShouldPlay = nil
        }
    }
}

// MARK: - 播放器视图

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let playerLayer = layer as? AVPlayerLayer else { return }
        playerLayer.frame = bounds
    }
}
