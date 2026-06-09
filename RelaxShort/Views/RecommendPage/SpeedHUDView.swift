import SwiftUI

// MARK: - 倍速提示

/// 长按倍速提示 — 三角形推进动画
struct SpeedHUDView: View {

    @State private var phase = 0

    private let timer = Timer.publish(every: 0.22, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            Text("2.0x")
                .font(.system(size: 23, weight: .heavy))

            HStack(spacing: -1) {
                ForEach(0..<3) { i in
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .black))
                        .scaleEffect(phase == i ? 1.18 : 0.92)
                        .opacity(phase == i ? 1 : 0.42)
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.22)))
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 2)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                phase = (phase + 1) % 3
            }
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}

#if DEBUG
#Preview { SpeedHUDView().background(Color.black) }
#endif
