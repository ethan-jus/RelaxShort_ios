import SwiftUI
import AVKit
import Network

// MARK: - PlayerKit 媒体模型

enum PlayerPlaybackState: Equatable { case idle, preparing, ready, playing, pausedByUser, pausedBySystem, waitingNetwork, stalled, recovering, failed(message: String?) }
enum PlayerPauseReason: Equatable { case none, user, system }
enum PlayerSubtitleFormat: Hashable { case vtt, srt }

struct PlayerSubtitleTrack: Identifiable, Hashable { let id: String; let languageCode: String; let displayName: String; let url: URL; let format: PlayerSubtitleFormat; let isDefault: Bool }
enum PlayerMediaSource: Hashable { case mp4(URL); case mp4WithExternalSubtitles(videoURL: URL, subtitles: [PlayerSubtitleTrack]); case mp4WithEmbeddedSubtitles(URL); case hls(masterURL: URL); case hlsWithFallback(masterURL: URL, fallbackMP4URL: URL) }
struct PlayerQualityOption: Identifiable, Hashable { let id: String; let displayName: String; let bitrate: Int? }
struct PlayerSubtitleOption: Identifiable, Hashable { let id: String; let displayName: String; let languageCode: String }
struct PlayerMediaItem: Identifiable, Hashable { let id: String; let title: String; let episodeNumber: Int?; let coverURL: String; let source: PlayerMediaSource; let resumeTime: TimeInterval? }
struct PlayerProgress { var currentTime: TimeInterval = 0; var duration: TimeInterval = 0; var bufferProgress: Double = 0 }
struct PlayerSubtitleCue: Sendable { let index: Int; let start: TimeInterval; let end: TimeInterval; let text: String }

// MARK: - PlayerKit 三槽池

enum PlayerSlot: Int, Sendable { case previous = 0, current = 1, next = 2 }

final class PlayerSlotPool {
    private var players: [AVPlayer?] = [nil, nil, nil]
    func prepare(item: PlayerMediaItem, slot: PlayerSlot, generation: Int, completion: @escaping (Result<AVPlayer, Error>) -> Void) {
        players[slot.rawValue]?.pause(); players[slot.rawValue] = nil
        let item = PlayerItemFactory.makeItem(from: item.source); let p = AVPlayer(playerItem: item)
        players[slot.rawValue] = p; completion(.success(p))
    }
    func move(from oldIndex: Int, to newIndex: Int, items: [PlayerMediaItem], generation: Int, completion: @escaping (Result<AVPlayer, Error>) -> Void) {
        if newIndex > oldIndex { players[0]?.pause(); players[0] = players[1]; players[1] = players[2]; players[2] = nil }
        else { players[2]?.pause(); players[2] = players[1]; players[1] = players[0]; players[0] = nil }
        if let c = players[1] { completion(.success(c)) }
        else { let newItem = PlayerItemFactory.makeItem(from: items[newIndex].source); let p = AVPlayer(playerItem: newItem); players[1] = p; completion(.success(p)) }
    }
    func cleanup() { for i in 0..<3 { players[i]?.pause(); players[i] = nil } }
    deinit { cleanup() }
}

// MARK: - PlayerKit Item Factory

enum PlayerItemFactory {
    static func makeItem(from source: PlayerMediaSource) -> AVPlayerItem {
        switch source {
        case .mp4(let url), .mp4WithEmbeddedSubtitles(let url):
            let d = PlayerResourceLoaderDelegate(originalURL: url)
            let a = AVURLAsset(url: url.withCacheScheme(), options: nil)
            a.resourceLoader.setDelegate(d, queue: .global(qos: .utility))
            return AVPlayerItem(asset: a)
        case .mp4WithExternalSubtitles(let videoURL, _):
            let d = PlayerResourceLoaderDelegate(originalURL: videoURL)
            let a = AVURLAsset(url: videoURL.withCacheScheme(), options: nil)
            a.resourceLoader.setDelegate(d, queue: .global(qos: .utility))
            return AVPlayerItem(asset: a)
        case .hls(let masterURL), .hlsWithFallback(let masterURL, _):
            return AVPlayerItem(url: masterURL)
        }
    }
}

extension URL { func withCacheScheme() -> URL { guard var c = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }; c.scheme = "relaxshort-cache"; return c.url ?? self } }

// MARK: - PlayerKit 恢复控制器

@MainActor final class PlayerRecoveryController {
    weak var engine: ShortVideoPlayerEngine?
    private var lastTime: TimeInterval = 0; private var lastItem: PlayerMediaItem?
    private var wasPlaying = false; private let monitor = NWPathMonitor(); private var isOnline = true

    deinit { monitor.cancel() }
    func startMonitoring() { monitor.pathUpdateHandler = { [weak self] p in Task { @MainActor in self?.onNet(p.status == .satisfied) } }; monitor.start(queue: .global(qos: .utility)) }
    func startObserving(player: AVPlayer) {
        _ = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in self?.onFail() }
        _ = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: player.currentItem, queue: .main) { [weak self] _ in self?.onStall() }
    }
    private func snap() { guard let e = engine else { return }; lastTime = e.progress.currentTime; lastItem = e.currentItem; wasPlaying = e.state == .playing }
    private func onFail() { snap(); print("[PlayerKit] item failed"); engine?.updateState(.failed(message: "播放失败")) }
    private func onStall() { snap(); print("[PlayerKit] stalled"); engine?.updateState(.stalled) }
    private func onNet(_ ok: Bool) { let was = !isOnline && ok; isOnline = ok; guard was, let e = engine, case .failed = e.state else { return }; recover() }
    private func recover() { guard let e = engine, let _ = lastItem, wasPlaying else { return }; print("[PlayerKit] recovery: time=\(lastTime)"); e.rebuildCurrentItem() }
}

// MARK: - PlayerKit 引擎

@MainActor final class ShortVideoPlayerEngine: ObservableObject {
    @Published private(set) var state: PlayerPlaybackState = .idle
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentPlayer: AVPlayer?
    @Published private(set) var currentItem: PlayerMediaItem?
    @Published var progress = PlayerProgress()
    @Published var subtitleText: String?
    @Published private(set) var availableSubtitles: [PlayerSubtitleOption] = []
    @Published var selectedSubtitleID: String?
    @Published var isReadyForDisplay: Bool = false
    var metrics = PlayerMetricsLogger(); var onPlaybackFinished: (() -> Void)?

    private var items: [PlayerMediaItem] = []; private let slotPool = PlayerSlotPool(); private var generation: Int = 0
    private var timeObserver: Any?; private var itemEndObserver: Any?; private var subtitleCues: [PlayerSubtitleCue] = []
    private let recoveryController = PlayerRecoveryController()

    init() { recoveryController.engine = self; recoveryController.startMonitoring() }

    func prepare(items: [PlayerMediaItem], index: Int) {
        guard !items.isEmpty, items.indices.contains(index) else { return }
        self.items = items; currentIndex = index; currentItem = items[index]; state = .preparing; generation &+= 1; let gen = generation
        slotPool.prepare(item: items[index], slot: .current, generation: gen) { [weak self] r in
            guard let self, self.generation == gen else { self?.metrics.logCanceledPreload(1); return }
            switch r { case .success(let p): self.attach(player: p); self.preloadAdjacent(gen: gen); case .failure: self.state = .failed(message: "加载失败") }
        }
    }
    func move(to index: Int) {
        guard items.indices.contains(index), index != currentIndex else { return }
        let old = currentIndex; currentIndex = index; currentItem = items[index]; generation &+= 1; let gen = generation; state = .preparing
        slotPool.move(from: old, to: index, items: items, generation: gen) { [weak self] r in
            guard let self, self.generation == gen else { self?.metrics.logCanceledPreload(1); return }
            switch r { case .success(let p): self.attach(player: p); self.preloadAdjacent(gen: gen); case .failure: self.state = .failed(message: "加载失败") }
        }
    }
    func play() { currentPlayer?.play(); state = .playing }
    func pause(reason: PlayerPauseReason) { currentPlayer?.pause(); state = reason == .user ? .pausedByUser : .pausedBySystem }
    func setRate(_ rate: Float) { currentPlayer?.rate = rate }
    func cleanup() { removeObservers(); slotPool.cleanup(); currentPlayer = nil; state = .idle; generation &+= 1 }
    func selectSubtitle(_ id: String?) { selectedSubtitleID = id }
    func selectQuality(_: PlayerQualityOption?) {}
    func updateState(_ s: PlayerPlaybackState) { state = s }
    func rebuildCurrentItem() { guard let item = currentItem else { return }; state = .recovering; let pi = PlayerItemFactory.makeItem(from: item.source); currentPlayer?.replaceCurrentItem(with: pi); seekTime(progress.currentTime); play(); metrics.logRecovery(ms: 0) }

    func seek(to fraction: Double) { guard let p = currentPlayer, let i = p.currentItem, i.duration.isNumeric else { return }; let t = CMTime(seconds: max(0, min(1, fraction)) * i.duration.seconds, preferredTimescale: 600); p.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero); progress.currentTime = t.seconds }
    func seekTime(_ time: TimeInterval) { currentPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600)); progress.currentTime = time }
    func generateThumbnail(at fraction: Double, completion: @escaping (UIImage?) -> Void) { guard let p = currentPlayer, let a = p.currentItem?.asset else { completion(nil); return }; let g = AVAssetImageGenerator(asset: a); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 320, height: 180); let d = p.currentItem?.duration.seconds ?? 0; guard d > 0 else { completion(nil); return }; Task { do { let (cg, _) = try await g.image(at: CMTime(seconds: CGFloat(fraction) * d, preferredTimescale: 600)); completion(UIImage(cgImage: cg)) } catch { completion(nil) } } }

    func loadExternalSubtitles(_ tracks: [PlayerSubtitleTrack]) { guard let t = tracks.first(where: { $0.isDefault }) ?? tracks.first else { return }; Task { subtitleCues = await SubtitleParser().parse(url: t.url, format: t.format) } }

    private func attach(player: AVPlayer) { removeObservers(); currentPlayer = player; startObserving(); recoveryController.startObserving(player: player); isReadyForDisplay = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.isReadyForDisplay = true }; state = .ready; metrics.logTTFF(0) }
    private func preloadAdjacent(gen: Int) { let n = currentIndex + 1; if n < items.count { slotPool.prepare(item: items[n], slot: .next, generation: gen) { _ in } }; let p = currentIndex - 1; if p >= 0 { slotPool.prepare(item: items[p], slot: .previous, generation: gen) { _ in } } }
    private func startObserving() { guard let player = currentPlayer else { return }; timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in guard let self else { return }; self.progress.currentTime = t.seconds; if let i = player.currentItem, i.duration.isNumeric { self.progress.duration = i.duration.seconds; if let r = i.loadedTimeRanges.first?.timeRangeValue { self.progress.bufferProgress = self.progress.duration > 0 ? (CMTimeGetSeconds(r.start) + CMTimeGetSeconds(r.duration)) / self.progress.duration : 0 } }; self.updateSub(at: t.seconds) }; itemEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in self?.state = .pausedBySystem; self?.onPlaybackFinished?() } }
    private func removeObservers() { if let o = timeObserver { currentPlayer?.removeTimeObserver(o); timeObserver = nil }; if let o = itemEndObserver { NotificationCenter.default.removeObserver(o); itemEndObserver = nil } }
    private func updateSub(at time: TimeInterval) { guard !subtitleCues.isEmpty else { return }; if let c = subtitleCues.first(where: { time >= $0.start && time <= $0.end }) { subtitleText = c.text } else { subtitleText = nil } }
}

// MARK: - 推荐页播放会话 (保持兼容)

@MainActor final class RecommendSession: ObservableObject {
    let playerEngine = ShortVideoPlayerEngine()
    let pool = PlayerPool()
    let controller = PlayerController()
    @Published var currentIndex = 0
    @Published var hasInitializedPool = false
    @Published var poolVersion = 0

    func initializePool(dramas: [DramaItem]) { guard !dramas.isEmpty else { return }; if let u = dramas[0].videoURL.flatMap(URL.init) { pool.setCurrent(url: u) }; preloadAdjacent(for: 0, dramas: dramas); hasInitializedPool = true; poolVersion &+= 1 }
    func handleTransition(from old: Int, to new: Int, dramas: [DramaItem]) { guard dramas.count > 1 else { return }; if new > old { pool.advance() } else if new < old { pool.retreat() }; preloadAdjacent(for: new, dramas: dramas); poolVersion &+= 1 }
    private func preloadAdjacent(for i: Int, dramas: [DramaItem]) { let n = i + 1; if n < dramas.count, let u = dramas[n].videoURL.flatMap(URL.init) { pool.preloadNext(url: u) }; let p = i - 1; if p >= 0, let u = dramas[p].videoURL.flatMap(URL.init) { pool.preloadPrevious(url: u) } }
    func cleanup() { controller.cleanup(); pool.cleanup() }
}

// MARK: - 旧播放器池 (保持兼容)

final class PlayerPool { private var pool: [AVPlayer?] = [nil, nil, nil]; var current: AVPlayer? { pool[1] }
    func setCurrent(url: URL) -> AVPlayer { let p = AVPlayer(url: url); pool[1] = p; return p }
    func preloadNext(url: URL) { pool[2]?.pause(); pool[2] = AVPlayer(url: url) }
    func preloadPrevious(url: URL) { pool[0]?.pause(); pool[0] = AVPlayer(url: url) }
    func advance() -> AVPlayer? { pool[0]?.pause(); pool[1]?.pause(); pool[0] = pool[1]; pool[1] = pool[2]; pool[2] = nil; return pool[1] }
    func retreat() -> AVPlayer? { pool[2]?.pause(); pool[1]?.pause(); pool[2] = pool[1]; pool[1] = pool[0]; pool[0] = nil; return pool[1] }
    func cleanup() { for p in pool { p?.pause() }; pool = [nil, nil, nil] }
    deinit { cleanup() }
}

// MARK: - 旧播放控制器 (保持兼容)

final class PlayerController: ObservableObject {
    @Published var currentTime: Double = 0; @Published var duration: Double = 0; @Published var isPlaying: Bool = false; @Published var hasStartedPlayingOnce: Bool = false; @Published var pauseReason: PlayerPauseReason = .none; @Published var bufferProgress: Double = 0; @Published var thumbnailImage: UIImage?
    private var player: AVPlayer?; private var timeObserver: Any?; private var itemEndObserver: Any?; private var gen: AVAssetImageGenerator?; private var thumbTask: Task<Void, Never>?
    var onPlaybackFinished: (() -> Void)?

    func attach(player: AVPlayer) { detach(); self.player = player; startObserving() }
    func detach() { if let o = timeObserver { player?.removeTimeObserver(o); timeObserver = nil }; if let o = itemEndObserver { NotificationCenter.default.removeObserver(o); itemEndObserver = nil }; player = nil }
    func togglePlayPause() { guard let p = player else { return }; if p.timeControlStatus == .playing { pauseByUser() } else { p.play(); isPlaying = true; hasStartedPlayingOnce = true; pauseReason = .none } }
    func pauseForSystem() { player?.pause(); if pauseReason != .user { pauseReason = .system }; isPlaying = false }
    func pauseByUser() { player?.pause(); pauseReason = .user; isPlaying = false }
    func playFromSystemResume() { guard pauseReason != .user else { return }; player?.play(); pauseReason = .none; isPlaying = true }
    func playAfterAttach() { player?.play(); isPlaying = true; hasStartedPlayingOnce = true; pauseReason = .none }
    func pause() { pauseForSystem() }; func play() { playFromSystemResume() }
    func setRate(_ rate: Float) { player?.rate = rate }
    func resetForNewPlayer() { currentTime = 0; duration = 0; bufferProgress = 0; thumbnailImage = nil }
    func cleanup() { player?.pause(); detach() }
    func seek(to fraction: Double) { guard let p = player, let i = p.currentItem, i.duration.isNumeric else { return }; let t = CMTime(seconds: max(0, min(1, fraction)) * i.duration.seconds, preferredTimescale: 600); p.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero); currentTime = t.seconds }
    func generateThumbnail(at fraction: Double) { guard let p = player, let a = p.currentItem?.asset else { return }; if gen == nil { let g = AVAssetImageGenerator(asset: a); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 320, height: 180); gen = g }; guard let g = gen else { return }; let d = p.currentItem?.duration.seconds ?? 0; guard d > 0 else { return }; thumbTask?.cancel(); thumbTask = Task { @MainActor [weak self] in guard let self else { return }; do { let (cg, _) = try await g.image(at: CMTime(seconds: CGFloat(fraction) * d, preferredTimescale: 600)); self.thumbnailImage = UIImage(cgImage: cg) } catch {} } }
    private func startObserving() { guard let p = player else { return }; timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in guard let self, let p = self.player else { return }; self.currentTime = t.seconds; if let i = p.currentItem, i.duration.isNumeric { self.duration = i.duration.seconds; if let r = i.loadedTimeRanges.first?.timeRangeValue { self.bufferProgress = self.duration > 0 ? (CMTimeGetSeconds(r.start) + CMTimeGetSeconds(r.duration)) / self.duration : 0 } }; self.isPlaying = p.timeControlStatus == .playing }; itemEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in self?.isPlaying = false; self?.onPlaybackFinished?() } }
}

// MARK: - 视频播放视图 (简化壳)

struct VideoPlayerView: View { let coverURL: String; let player: AVPlayer?; var controller: PlayerController?
    @StateObject private var loader = ImageLoader()
    var body: some View { ZStack { Color.black; if let player, let controller { VPViewLayer(player: player, controller: controller) }; if showCover { coverView.transition(.opacity) }; if let c = controller, c.hasStartedPlayingOnce, c.pauseReason == .user { Image(systemName: "play.circle.fill").font(.system(size: 60)).foregroundColor(.white.opacity(0.7)).shadow(color: .black.opacity(0.4), radius: 8).transition(.scale.combined(with: .opacity)).zIndex(10) } }.animation(.easeInOut(duration: 0.3), value: showCover).task { await loader.load(coverURL) } }
    private var showCover: Bool { player == nil || (controller != nil && !controller!.hasStartedPlayingOnce) }
    @ViewBuilder private var coverView: some View { if let i = loader.image { Image(uiImage: i).resizable().scaledToFill().clipped() } else { Rectangle().fill(LinearGradient(colors: [Color(hex: "#2D1B69"), Color(hex: "#1a1a3e")], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay(ProgressView().tint(.gray)) } }
}
private struct VPViewLayer: UIViewRepresentable { let player: AVPlayer; let controller: PlayerController
    func makeUIView(context: Context) -> VPUIView { let v = VPUIView(); (v.layer as? AVPlayerLayer)?.player = player; (v.layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill; controller.attach(player: player); return v }
    func updateUIView(_ v: VPUIView, context: Context) { if (v.layer as? AVPlayerLayer)?.player !== player { (v.layer as? AVPlayerLayer)?.player = player; (v.layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill; controller.attach(player: player) } }
    static func dismantleUIView(_ v: VPUIView, coordinator: ()) { (v.layer as? AVPlayerLayer)?.player = nil }
}
private final class VPUIView: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self }; override func layoutSubviews() { super.layoutSubviews(); (layer as? AVPlayerLayer)?.frame = bounds } }
