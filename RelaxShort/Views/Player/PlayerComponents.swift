import SwiftUI
import AVKit

// MARK: - Video Player Bridge

/// 通过 UIViewRepresentable 将 AVPlayerLayer 桥接到 SwiftUI
struct VideoPlayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let playerView = uiView as? PlayerUIView, playerView.player !== player else { return }
        playerView.player = player
    }
}

/// 承载 AVPlayerLayer 的 UIView
private final class PlayerUIView: UIView {
    var player: AVPlayer {
        get { playerLayer?.player ?? AVPlayer() }
        set { playerLayer?.player = newValue }
    }
    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        self.player = player
        playerLayer?.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

// MARK: - Mock Video View

/// Mock 视频播放区域：显示静态封面图 + 中央播放图标
/// 用于模拟视频播放的 UI 占位
struct MockVideoView: View {
    let dramaTitle: String
    let episodeNumber: Int
    let isPlaying: Bool

    var body: some View {
        ZStack {
            // 封面背景渐变
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#1a1a2e"),
                    Color(hex: "#2D1B69"),
                    Color(hex: "#16213e"),
                    Color(hex: "#0f3460")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 封面图案装饰
            VStack(spacing: 8) {
                // 模拟短剧封面图
                ZStack {
                    RoundedRectangle(cornerRadius: DT.Radius.xl)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    DT.Color.bgCoverPlaceholderStart,
                                    DT.Color.bgCoverPlaceholderEnd
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 180, height: 240)
                        .overlay(
                            RoundedRectangle(cornerRadius: DT.Radius.xl)
                                .stroke(DT.Color.textPrimary.opacity(0.15), lineWidth: 1)
                        )

                    // 中央播放/暂停图标
                    if !isPlaying {
                        Circle()
                            .fill(DT.Color.bgPrimary.opacity(0.45))
                            .frame(width: 64, height: 64)
                        Image(systemName: "play.fill")
                            .font(DT.Font.body(28, weight: .medium))
                            .foregroundColor(DT.Color.textPrimary)
                            .offset(x: 2)
                    }
                }

                // 剧名
                Text(dramaTitle)
                    .font(DT.Font.subtitle)
                    .foregroundColor(DT.Color.textPrimary.opacity(0.85))
                    .multilineTextAlignment(.center)

                // 集数
                Text(L10n.playerEpisodeNumber(episodeNumber))
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
            }

            // 底部轻微渐变遮罩（模拟播放进度视觉）
            VStack {
                Spacer()
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        DT.Color.bgPrimary.opacity(0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Custom Progress Bar

/// iOS 原生风格细进度条 + 可拖拽手柄
struct CustomProgressBar: View {
    /// 当前进度 0–1
    let progress: CGFloat
    /// 总宽度
    let totalWidth: CGFloat
    /// 是否正在拖拽
    let isScrubbing: Bool
    /// 拖拽变更回调
    var onDragChanged: ((CGFloat) -> Void)?
    /// 拖拽结束回调
    var onDragEnded: (() -> Void)?

    private let barHeight: CGFloat = 4
    private let scrubbedBarHeight: CGFloat = 6

    var body: some View {
        let effectiveHeight: CGFloat = isScrubbing ? scrubbedBarHeight : barHeight
        let clampedProgress = max(0, min(1, progress))

        ZStack(alignment: .leading) {
            // 背景轨道
            Capsule()
                .fill(DT.Color.textPrimary.opacity(0.18))
                .frame(height: effectiveHeight)

            // 播放进度
            Capsule()
                .fill(isScrubbing ? DT.brandPink.opacity(0.9) : DT.Color.textPrimary.opacity(0.75))
                .frame(
                    width: max(totalWidth * clampedProgress, effectiveHeight),
                    height: effectiveHeight
                )

            // 拖拽手柄（只在拖拽时显示）
            if isScrubbing {
                Circle()
                    .fill(DT.Color.textPrimary)
                    .frame(width: 14, height: 14)
                    .shadow(color: DT.Color.bgPrimary.opacity(0.3), radius: 3, x: 0, y: 1)
                    .offset(x: totalWidth * clampedProgress - 7)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let raw = max(0, min(1, value.location.x / totalWidth))
                    onDragChanged?(raw)
                }
                .onEnded { _ in
                    onDragEnded?()
                }
        )
    }
}

// MARK: - Time Label

/// 时间标签：显示 "03:25 / 12:40"
struct TimeLabel: View {
    let currentTime: TimeInterval
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 2) {
            Text(formatTime(currentTime))
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textPrimary)
                .monospacedDigit()

            Text(" / ")
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textSecondary)

            Text(formatTime(duration))
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textSecondary)
                .monospacedDigit()
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "00:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Control Button

/// 统一圆形 44pt 图标控制按钮
struct ControlButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DT.Font.body(20, weight: .medium))
                .foregroundColor(DT.Color.textPrimary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(DT.Color.bgPrimary.opacity(0.25))
                )
        }
    }
}

// MARK: - Small Control Button

/// 较小尺寸的控制按钮（用于底部栏）
struct SmallControlButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DT.Font.body(18, weight: .medium))
                .foregroundColor(DT.Color.textPrimary)
                .frame(width: 40, height: 40)
        }
    }
}

// MARK: - Tag View

/// 短剧标签胶囊（独家、现代言情、甜宠 等）
struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DT.Font.tabLabel)
            .foregroundColor(DT.Color.textPrimary)
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, 3)
            .background(DT.Color.bgDivider)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(DT.Color.textPrimary.opacity(0.2), lineWidth: 0.5)
            )
    }
}

// MARK: - Share Platform Button

/// 分享面板平台按钮
struct SharePlatformButton: View {
    let color: SwiftUI.Color
    let icon: String
    let name: String

    var body: some View {
        Button {
            // TODO: 实际分享逻辑
        } label: {
            VStack(spacing: DT.Space.sm) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(DT.Font.body(22, weight: .medium))
                        .foregroundColor(DT.Color.textPrimary)
                }
                Text(name)
                    .font(DT.Font.small)
                    .foregroundColor(DT.Color.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

#if DEBUG
#Preview("MockVideoView") {
    MockVideoView(dramaTitle: "我的老板四岁半", episodeNumber: 3, isPlaying: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

#Preview("CustomProgressBar") {
    VStack(spacing: 30) {
        CustomProgressBar(progress: 0.0, totalWidth: 300, isScrubbing: false)
        CustomProgressBar(progress: 0.45, totalWidth: 300, isScrubbing: false)
        CustomProgressBar(progress: 0.45, totalWidth: 300, isScrubbing: true)
        CustomProgressBar(progress: 1.0, totalWidth: 300, isScrubbing: false)
    }
    .padding()
    .background(DT.Color.bgPrimary)
}

#Preview("TimeLabel") {
    TimeLabel(currentTime: 225, duration: 760)
        .padding()
        .background(DT.Color.bgPrimary)
}

#Preview("ControlButton") {
    HStack(spacing: 16) {
        ControlButton(icon: "chevron.left") {}
        ControlButton(icon: "play.fill") {}
        ControlButton(icon: "forward.fill") {}
    }
    .padding()
    .background(DT.Color.bgPrimary)
}

#Preview("TagView") {
    HStack(spacing: 8) {
        TagView(text: "独家")
        TagView(text: "现代言情")
        TagView(text: "甜宠")
    }
    .padding()
    .background(DT.Color.bgPrimary)
}

#Preview("SharePlatformButton") {
    HStack(spacing: 20) {
        SharePlatformButton(color: .pink, icon: "camera.fill", name: "Instagram")
        SharePlatformButton(color: .green, icon: "phone.fill", name: "WhatsApp")
    }
    .padding()
    .background(DT.Color.bgPrimary)
}
#endif
