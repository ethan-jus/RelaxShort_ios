import SwiftUI

// MARK: - DramaBox Section Header

/// DramaBox 风格分区标题 — 左边竖线 + 标题 + 可选右侧按钮
struct DramaBoxSectionHeader: View {
    let title: String
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(DB.pink)
                .frame(width: 3, height: 18)

            // Title
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            // Optional right action
            if let label = actionLabel {
                Button {
                    onAction?()
                } label: {
                    HStack(spacing: 4) {
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundColor(DB.mutedText)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DB.mutedText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 44)
    }
}

#if DEBUG
struct DramaBoxSectionHeader_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DramaBoxSectionHeader(title: "Popular Now")
            DramaBoxSectionHeader(title: "VIP Recommendations", actionLabel: "See All")
        }
        .padding()
        .background(DB.black)
        .preferredColorScheme(.dark)
    }
}
#endif
