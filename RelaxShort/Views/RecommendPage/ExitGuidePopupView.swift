import SwiftUI

// MARK: - Exit Guide Popup

/// 退出引导弹窗 — 播放页面退出时提示用户开启通知
struct ExitGuidePopupView: View {
    @Binding var showExitPopup: Bool

    /// 是否开启通知（示例状态，后续接入系统通知权限）
    @State private var notificationGranted: Bool = false

    private let benefitTags: [(icon: String, text: String)] = [
        ("sparkles", L10n.newDramaBenefit),
        ("gift.fill", L10n.rewardBenefit),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    showExitPopup = false
                }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        showExitPopup = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DT.Font.body(24))
                            .foregroundColor(DT.Color.textSecondary)
                    }
                }
                .padding(.bottom, DT.Space.sm)

                HStack(spacing: DT.Space.sm) {
                    ForEach(benefitTags, id: \.text) { tag in
                        HStack(spacing: DT.Space.xs) {
                            Image(systemName: tag.icon)
                                .font(DT.Font.small)
                            Text(tag.text)
                                .font(DT.Font.caption)
                        }
                        .foregroundColor(DT.Color.textPrimary)
                        .padding(.horizontal, DT.Space.md)
                        .padding(.vertical, DT.Space.sm)
                        .background(DT.Color.textPrimary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
                .padding(.bottom, DT.Space.xxl)

                Text(L10n.enableNotificationsTitle)
                    .font(DT.Font.subtitle)
                    .foregroundColor(DT.Color.textPrimary)
                    .padding(.bottom, DT.Space.md)

                Text(L10n.enableNotificationsBody)
                    .font(DT.Font.bodyDefault)
                    .foregroundColor(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.bottom, DT.Space.xxl + 4)

                Button {
                    notificationGranted = true
                    showExitPopup = false
                } label: {
                    Text(L10n.enableNotifications)
                        .font(DT.Font.button)
                        .foregroundColor(DT.Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DT.brandPink)
                        .clipShape(Capsule())
                }

                Button {
                    showExitPopup = false
                } label: {
                    Text(L10n.notNow)
                        .font(DT.Font.bodyDefault)
                        .foregroundColor(DT.Color.textSecondary)
                }
                .padding(.top, DT.Space.lg)
            }
            .padding(DT.Space.xxl)
            .background(DT.Color.bgModal)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl))
            .padding(.horizontal, DT.Space.xl)
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
        }
    }
}

#if DEBUG
#Preview("Exit Popup") {
    ExitGuidePopupView(showExitPopup: .constant(true))
}
#endif
