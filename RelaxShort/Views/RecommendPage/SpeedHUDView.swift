import SwiftUI

// MARK: - Speed HUD (DramaBox style)

/// 长按倍速提示 — "2.0x >>>" 白色粗体，简洁
struct SpeedHUDView: View {

    @State private var arrowPhase = 0

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Text("2.0x")
                .font(.system(size: 22, weight: .bold))
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(arrowPhase > i ? 1 : 0.2)
                }
            }
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.5), radius: 4)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                arrowPhase = (arrowPhase + 1) % 4
            }
        }
        .transition(.opacity)
    }
}

#if DEBUG
#Preview { SpeedHUDView().background(Color.black) }
#endif
