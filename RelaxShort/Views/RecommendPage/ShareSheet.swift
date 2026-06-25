import SwiftUI

// MARK: - Share Metrics (Task27 R3)

private enum ShareMetrics {
    static let detentHeight: CGFloat = 420
    static let cornerRadius: CGFloat = 26
    static let iconSize: CGFloat = 68
    static let rewardPillHeight: CGFloat = 52
}

extension View {
    func shareSheetPresentationStyle() -> some View {
        self
            .presentationDetents([.height(ShareMetrics.detentHeight)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(ShareMetrics.cornerRadius)
    }
}

// MARK: - DramaBox Share Sheet (Task27 R3)

struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let dramaTitle: String

    var body: some View {
        GeometryReader { geo in
            let iconW = min(ShareMetrics.iconSize, (geo.size.width - 90) / 5)
            VStack(spacing: 0) {
                HStack {
                    Spacer().frame(width: 40)
                    Spacer()
                    Text("Share").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55)).frame(width: 40, height: 40)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)

                HStack(spacing: 10) {
                    Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 22)).foregroundColor(DB.gold)
                    Text("first share gets 10 coins").font(.system(size: 17, weight: .medium)).foregroundColor(.white.opacity(0.88))
                    Spacer()
                }
                .padding(.horizontal, 20).frame(height: ShareMetrics.rewardPillHeight)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .padding(.horizontal, 24).padding(.bottom, 28)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        shareBtn(icon: "camera.fill", label: "Instagram",
                            bg: [Color(hex: "#F58529"), Color(hex: "#DD2A7B"), Color(hex: "#8134AF")], w: iconW)
                        shareBtn(icon: "bolt.fill", label: "Snapchat",
                            bg: [Color(hex: "#FFFC00")], iconC: .black, w: iconW)
                        shareBtn(icon: "message.fill", label: "Facebook Messenger",
                            bg: [Color(hex: "#00B2FF"), Color(hex: "#006AFF")], w: iconW)
                        shareBtn(icon: "phone.fill", label: "WhatsApp",
                            bg: [Color(hex: "#25D366")], w: iconW)
                        shareBtn(icon: "link", label: "Copy Link",
                            bg: [Color.white.opacity(0.18)], iconC: .white, w: iconW)
                    }
                    .padding(.horizontal, 16)
                }
                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(hex: "#1C1C1E"))
        }
    }

    private func shareBtn(icon: String, label: String, bg: [Color], iconC: Color = .white, w: CGFloat) -> some View {
        Button {
            if label == "Copy Link" { UIPasteboard.general.string = "https://relaxshort.app/drama/\(dramaTitle)" }
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if bg.count > 1 { LinearGradient(colors: bg, startPoint: .topLeading, endPoint: .bottomTrailing).clipShape(Circle()) }
                    else { Circle().fill(bg[0]) }
                    Image(systemName: icon).font(.system(size: max(20, w * 0.4), weight: .medium)).foregroundColor(iconC)
                }
                .frame(width: w, height: w)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.7))
                    .lineLimit(2).multilineTextAlignment(.center).frame(width: w)
            }
        }.buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Share Sheet") { ShareSheet(dramaTitle: "Mafia's Good Girl").preferredColorScheme(.dark) }
#endif
