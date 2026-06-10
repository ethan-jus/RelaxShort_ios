import SwiftUI

// MARK: - 倍速提示

/// 长按倍速提示 — 三角形推进动画
struct SpeedHUDView: View {

    var body: some View {
        HStack(spacing: 6) {
            Text("2.0x")
                .font(.system(size: 14, weight: .bold))

            TimelineView(.animation) { context in
                let progress = context.date.timeIntervalSinceReferenceDate / 0.84

                HStack(spacing: -2) {
                    ForEach(0..<3) { i in
                        let rawPhase = progress - Double(i) * 0.18
                        let phase = rawPhase - floor(rawPhase)
                        let pulse = max(0, 1 - abs(phase - 0.5) * 2)
                        let eased = pulse * pulse * (3 - 2 * pulse)

                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .black))
                            .scaleEffect(0.92 + 0.18 * eased)
                            .opacity(0.3 + 0.7 * eased)
                            .offset(x: 2.5 * eased)
                    }
                }
            }
            .frame(width: 27, height: 13)
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

#if DEBUG
#Preview { SpeedHUDView().background(Color.black) }
#endif
