import SwiftUI
import AVFoundation

// MARK: - 旧 PlayerComponents 辅助组件

struct VideoPlayerRepresentable: UIViewRepresentable { let player: AVPlayer
    func makeUIView(context: Context) -> UIView { OldPUIView(player: player) }
    func updateUIView(_ v: UIView, context: Context) { if let pv = v as? OldPUIView, pv.pl !== player { pv.pl = player } }
}
private final class OldPUIView: UIView {
    var pl: AVPlayer { get { (layer as? AVPlayerLayer)?.player ?? AVPlayer() } set { (layer as? AVPlayerLayer)?.player = newValue } }
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    init(player: AVPlayer) { super.init(frame: .zero); self.pl = player; (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill; backgroundColor = .black }
    required init?(coder: NSCoder) { fatalError() }
}

struct MockVideoView: View { let dramaTitle: String; let episodeNumber: Int; let isPlaying: Bool
    var body: some View { ZStack { LinearGradient(gradient: Gradient(colors: [Color(hex: "#1a1a2e"), Color(hex: "#2D1B69"), Color(hex: "#16213e")]), startPoint: .topLeading, endPoint: .bottomTrailing); VStack(spacing: 8) { ZStack { RoundedRectangle(cornerRadius: 16).fill(LinearGradient(gradient: Gradient(colors: [Color(hex: "#2D1B69"), Color(hex: "#1a1a3e")]), startPoint: .top, endPoint: .bottom)).frame(width: 180, height: 240); if !isPlaying { Circle().fill(Color.black.opacity(0.45)).frame(width: 64, height: 64); Image(systemName: "play.fill").font(.system(size: 28, weight: .medium)).foregroundColor(.white).offset(x: 2) } }; Text(dramaTitle).font(.system(size: 18, weight: .semibold)).foregroundColor(.white.opacity(0.85)); Text("EP \(episodeNumber)").font(.system(size: 13)).foregroundColor(.gray) } }.frame(maxWidth: .infinity, maxHeight: .infinity) }
}
