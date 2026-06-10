import SwiftUI

// MARK: - 倍速提示

/// 长按倍速提示 — 三角形推进动画
struct SpeedHUDView: View {

    var body: some View {
        HStack(spacing: 6) {
            Text("2.0x")
                .font(.system(size: 16, weight: .bold))

            TimelineView(.animation) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate * 6)

                HStack(spacing: -2) {
                    ForEach(0..<3) { i in
                        let step = (tick + i) % 3
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .black))
                            .scaleEffect(step == 0 ? 1.18 : 0.92)
                            .opacity(step == 0 ? 1 : (step == 1 ? 0.58 : 0.28))
                            .offset(x: step == 0 ? 3 : 0)
                    }
                }
            }
            .frame(width: 28, height: 14)
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
        .transition(.opacity)
    }
}

#if DEBUG
#Preview { SpeedHUDView().background(Color.black) }
#endif
