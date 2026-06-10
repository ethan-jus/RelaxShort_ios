import SwiftUI

// MARK: - 倍速提示

/// 长按倍速提示 — 三角形推进动画
struct SpeedHUDView: View {

    var body: some View {
        HStack(spacing: 4) {
            Text("2.0x")
                .font(.system(size: 16, weight: .bold))

            TimelineView(.animation) { context in
                let rawPhase = context.date.timeIntervalSinceReferenceDate / 0.92
                let phase = rawPhase - floor(rawPhase)

                HStack(spacing: -1) {
                    ForEach(0..<3) { i in
                        let opacity = triangleOpacity(index: i, phase: phase)

                        SharpTriangle()
                            .frame(width: 10, height: 13)
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

private struct SharpTriangle: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview { SpeedHUDView().background(Color.black) }
#endif
