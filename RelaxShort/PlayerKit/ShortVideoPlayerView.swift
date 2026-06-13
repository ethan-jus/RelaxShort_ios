import SwiftUI
import AVFoundation

// MARK: - 短剧播放器视图

/// 播放器 UI 层：AVPlayerLayer + 封面 + loading + 播放按钮 + 字幕
struct ShortVideoPlayerView: View {
    let player: AVPlayer?
    let coverURL: String
    let isActive: Bool
    @ObservedObject var engine: ShortVideoPlayerEngine
    @StateObject private var imageLoader = ImageLoader()

    init(player: AVPlayer?, coverURL: String, engine: ShortVideoPlayerEngine, isActive: Bool = true) {
        self.player = player
        self.coverURL = coverURL
        self.engine = engine
        self.isActive = isActive
    }

    var body: some View {
        ZStack {
            Color.black

            // AVPlayerLayer（coordinator 监听 isReadyForDisplay）
            if let player {
                PlayerLayerViewRepresentable(player: player, engine: engine)
            }

            // 封面：只有首帧未就绪时才显示
            if showCover {
                coverView
            }

            // loading 状态
            if engine.state == .preparing
                || engine.state == .waitingNetwork
                || engine.state == .recovering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }

            // 用户暂停：显示播放按钮，不显示封面
            // 只有当前 active player 且首帧就绪时才显示，避免非当前页残留按钮
            if player != nil, isActive, engine.state == .pausedByUser, engine.isReadyForDisplay {
                Image(systemName: "play.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.black.opacity(0.42)))
            }

            // 字幕
            if let text = engine.subtitleText, !text.isEmpty {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 60)
                }
            }
        }
        .task { await imageLoader.load(coverURL) }
    }

    // MARK: - 封面逻辑

    /// 封面显示条件：无播放器，或首帧尚未就绪
    private var showCover: Bool {
        if player == nil { return true }
        if !engine.isReadyForDisplay { return true }
        return false
    }

    @ViewBuilder
    private var coverView: some View {
        if let image = imageLoader.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#2D1B69"), Color(hex: "#1a1a3e")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        }
    }
}

// MARK: - PlayerLayer UIViewRepresentable（含 coordinator 监听首帧）

private struct PlayerLayerViewRepresentable: UIViewRepresentable {
    let player: AVPlayer
    let engine: ShortVideoPlayerEngine

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        let layer = view.layer as? AVPlayerLayer
        layer?.player = player
        layer?.videoGravity = .resizeAspectFill
        context.coordinator.startObserving(layer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        let layer = uiView.layer as? AVPlayerLayer
        if layer?.player !== player {
            layer?.player = player
            layer?.videoGravity = .resizeAspectFill
            context.coordinator.startObserving(layer)
        }
    }

    static func dismantleUIView(_ uiView: PlayerLayerUIView, coordinator: Coordinator) {
        coordinator.stopObserving()
        (uiView.layer as? AVPlayerLayer)?.player = nil
    }

    // MARK: - Coordinator：监听 AVPlayerLayer.isReadyForDisplay

    final class Coordinator {
        private weak var engine: ShortVideoPlayerEngine?
        private var observation: NSKeyValueObservation?

        init(engine: ShortVideoPlayerEngine) {
            self.engine = engine
        }

        func startObserving(_ layer: AVPlayerLayer?) {
            stopObserving()
            observation = layer?.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                guard let self, layer.isReadyForDisplay else { return }
                Task { @MainActor in
                    self.engine?.markReadyForDisplay()
                }
            }
        }

        func stopObserving() {
            observation?.invalidate()
            observation = nil
        }
    }
}

private final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        (layer as? AVPlayerLayer)?.frame = bounds
    }
}
