import SwiftUI

// MARK: - 倍速提示

/// 长按倍速提示 — 三角形推进动画
struct SpeedHUDView: View {

    @State private var phase = 0

    private let timer = Timer.publish(every: 0.22, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            Text("2.0x")
                .font(.system(size: 16, weight: .bold))

            HStack(spacing: -2) {
                ForEach(0..<3) { i in
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .black))
                        .scaleEffect(phase == i ? 1.18 : 0.9)
                        .opacity(phase == i ? 1 : 0.34)
                        .offset(x: phase == i ? 2 : 0)
                        .animation(.easeInOut(duration: 0.18), value: phase)
                }
            }
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                phase = (phase + 1) % 3
            }
        }
        .transition(.opacity)
    }
}

#if DEBUG
#Preview { SpeedHUDView().background(Color.black) }
#endif
