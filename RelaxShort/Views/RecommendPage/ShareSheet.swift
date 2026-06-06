import SwiftUI

// MARK: - DramaBox Share Sheet

/// DramaBox 风格底部分享面板
/// 奖励提示 + 平台图标 + Copy Link
struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let dramaTitle: String

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏 + 关闭
            HStack {
                Spacer().frame(width: 36)
                Spacer()
                Text("Share")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // 奖励提示
            HStack(spacing: 8) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(DB.gold)
                Text("first share gets 10 coins")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            // 平台列表
            HStack(spacing: 24) {
                sharePlatform(icon: "camera.circle.fill", name: "Instagram", color: Color(hex: "#E4405F"))
                sharePlatform(icon: "message.circle.fill", name: "Messenger", color: Color(hex: "#0084FF"))
                sharePlatform(icon: "ellipsis.message.fill", name: "WhatsApp", color: Color(hex: "#25D366"))
                sharePlatform(icon: "link", name: "Copy Link", color: Color.white.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .background(DB.panelElevated)
    }

    private func sharePlatform(icon: String, name: String, color: Color) -> some View {
        Button {
            if name == "Copy Link" {
                UIPasteboard.general.string = "https://relaxshort.app/drama/\(dramaTitle)"
            }
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(color)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(color.opacity(0.15)))

                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

#if DEBUG
#Preview("Share Sheet") {
    ShareSheet(dramaTitle: "Mafia's Good Girl")
        .preferredColorScheme(.dark)
}
#endif
