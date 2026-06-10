import SwiftUI

// MARK: - 倍速提示

/// 长按倍速提示 — 三角形推进动画
struct SpeedHUDView: View {

    var body: some View {
        HStack(spacing: 7) {
            Text("2.0x")
                .font(.system(size: 16, weight: .bold))

            TimelineView(.animation) { context in
                let rawPhase = context.date.timeIntervalSinceReferenceDate / 0.92
                let phase = rawPhase - floor(rawPhase)

                HStack(spacing: -1) {
                    ForEach(0..<3) { i in
                        let opacity = triangleOpacity(index: i, phase: phase)

                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .black))
                            .opacity(opacity)
                            .scaleEffect(0.96 + 0.04 * opacity)
                    }
                }
            }
            .frame(width: 34, height: 16)
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func triangleOpacity(index: Int, phase: Double) -> Double {
        let fade = 0.08
        let hideStart = [0.24, 0.42, 0.6][index]
        let resetStart = 0.82

        if phase >= resetStart {
            return smoothStep((phase - resetStart) / fade)
        }

        if phase < hideStart {
            return 1
        }

        if phase < hideStart + fade {
            return 1 - smoothStep((phase - hideStart) / fade)
        }

        return 0
    }

    private func smoothStep(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }
}

#if DEBUG
#Preview { SpeedHUDView().background(Color.black) }
#endif
