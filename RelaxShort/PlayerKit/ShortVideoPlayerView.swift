import SwiftUI
import AVFoundation

// MARK: - 短剧播放器视图

/// 播放器 UI 层：AVPlayerLayer + 封面 + loading + 播放按钮 + 字幕
struct ShortVideoPlayerView: View {
    let player: AVPlayer?
    let coverURL: String
    let isActive: Bool
    let showsSystemPlaybackButton: Bool
    @ObservedObject var engine: ShortVideoPlayerEngine
    @StateObject private var imageLoader = ImageLoader()

    init(
        player: AVPlayer?,
        coverURL: String,
        engine: ShortVideoPlayerEngine,
        isActive: Bool = true,
        showsSystemPlaybackButton: Bool = true
    ) {
        self.player = player
        self.coverURL = coverURL
        self.engine = engine
        self.isActive = isActive
        self.showsSystemPlaybackButton = showsSystemPlaybackButton
    }

    var body: some View {
        ZStack {
            Color.black

            // AVPlayerLayer（coordinator 监听 isReadyForDisplay）
            if let player {
                PlayerLayerViewRepresentable(player: player, engine: engine)
            }

            // 封面：视频真正开始出画前一直保留，避免 layer ready 与首帧播放之间露出黑屏
            if showCover {
                coverView
            }

            // 真实首帧出现前持续显示加载反馈。.playing 只由 AVPlayer 的真实状态确认，
            // 但状态已 playing 仍不等于画面已经显示，不能因此提前撤掉加载动画。
            if shouldShowLoading {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.25)
                    Text(L10n.loading)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 14))
            }

            // 用户暂停：显示播放按钮，不显示封面
            // 只有当前 active player 且首帧就绪时才显示，避免非当前页残留按钮
            if showsSystemPlaybackButton,
               player != nil,
               isActive,
               engine.state == .pausedByUser,
               engine.isReadyForDisplay {
                Image(systemName: "play.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.black.opacity(0.42)))
            }

            // 字幕
            if let text = engine.subtitleText, !text.isEmpty {
                PlayerSubtitleOverlay(text: text)
                    .transition(.opacity)
            }

            #if DEBUG
            if isActive, PlayerDiagnosticsOverlay.isEnabled {
                PlayerDiagnosticsOverlay(diagnostics: engine.diagnostics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 70)
                    .padding(.leading, 12)
            }
            #endif
        }
        .task(id: coverURL) {
            await imageLoader.load(coverURL)
        }
    }

    // MARK: - 封面逻辑

    /// 封面显示条件：无播放器，或可见播放尚未开始。
    /// 只用 AVPlayerLayer.isReadyForDisplay 会在部分网络/切换场景中过早撤封面，造成黑屏。
    private var showCover: Bool {
        if player == nil { return true }
        return !engine.hasVisiblePlaybackStarted
    }

    private var shouldShowLoading: Bool {
        guard isActive else { return false }
        switch engine.state {
        case .failed, .idle, .pausedByUser, .pausedBySystem:
            return false
        case .preparing, .ready, .playing, .waitingNetwork, .stalled, .recovering:
            return !engine.hasVisiblePlaybackStarted
                || engine.state == .waitingNetwork
                || engine.state == .stalled
                || engine.state == .recovering
        }
    }

    @ViewBuilder
    private var coverView: some View {
        if imageLoader.imageKey == ImageLoader.canonicalURLString(coverURL), let image = imageLoader.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#161616"), Color(hex: "#09090B")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        }
    }
}

/// 外挂字幕使用独立覆盖层，避开底部手势区、播放控件和剧集操作区。
/// 字号随播放器宽度轻微缩放，但限制在移动端可读范围内，避免小屏过小或大屏过度抢画面。
private struct PlayerSubtitleOverlay: View {
    let text: String

    var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer(minLength: 0)

                Text(text)
                    .font(
                        .system(
                            size: min(21, max(17, proxy.size.width * 0.046)),
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
                    .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
                    .frame(maxWidth: min(max(0, proxy.size.width - 32), 640))
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomClearance(in: proxy))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func bottomClearance(in proxy: GeometryProxy) -> CGFloat {
        let adaptive = proxy.size.height >= 600
            ? proxy.size.height * 0.17
            : proxy.size.height * 0.20
        return max(proxy.size.height >= 600 ? 122 : 62, adaptive)
            + proxy.safeAreaInsets.bottom
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
            let observedPlayer = layer?.player
            observation = layer?.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                guard let self, layer.isReadyForDisplay else { return }
                Task { @MainActor in
                    guard let observedPlayer else { return }
                    self.engine?.markReadyForDisplay(from: observedPlayer)
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

#if DEBUG
private struct PlayerDiagnosticsOverlay: View {
    let diagnostics: PlayerDiagnostics

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "PlayerKitDebugOverlay")
            || ProcessInfo.processInfo.arguments.contains("-PlayerKitDebugOverlay")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("PlayerKit")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            line("id", diagnostics.mediaID)
            line("src", diagnostics.sourceKind)
            line("mode", diagnostics.playbackStrategy)
            line("pre", diagnostics.preloadState)
            line("ttff", "\(Int(diagnostics.ttffMs)) / move \(Int(diagnostics.moveTTFFMs)) ms")
            line("cache", diagnostics.cacheSummary)
            line("state", diagnostics.stateText)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundColor(.white)
        .lineLimit(1)
        .padding(8)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .allowsHitTesting(false)
    }

    private func line(_ key: String, _ value: String) -> some View {
        Text("\(key): \(value)")
    }
}
#endif
