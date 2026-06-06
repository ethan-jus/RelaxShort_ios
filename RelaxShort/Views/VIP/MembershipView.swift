import SwiftUI

// MARK: - Membership Option Model
struct MembershipOption: Identifiable {
    let id = UUID()
    let title: String
    let price: String
    let originalPrice: String?
    let detail: String
    let isSelected: Bool
    let discountCountdown: String?
}

// MARK: - Membership Fullscreen Page (DramaBox Style)
/// 点击首页👑图标后弹出的全屏会员购买页
/// - 全屏覆盖，无底部 TabBar
/// - 顶部返回 + 金色渐变头部 + 三个会员选项 + 权益列表 + 条款 + 底部金色按钮
struct MembershipView: View {
    enum Mode {
        case push
        case tab
    }

    @Environment(\.dismiss) private var dismiss

    @State private var selectedOptionIndex = 0
    let mode: Mode

    init(mode: Mode = .push) {
        self.mode = mode
    }

    let options = [
        MembershipOption(
            title: L10n.weeklyMember,
            price: "$12.99",
            originalPrice: "$19.99",
            detail: L10n.weeklyDetail,
            isSelected: true,
            discountCountdown: "00:18:54"
        ),
        MembershipOption(
            title: L10n.monthlyMember,
            price: "$39.99",
            originalPrice: nil,
            detail: L10n.monthlyDetail,
            isSelected: false,
            discountCountdown: nil
        ),
        MembershipOption(
            title: L10n.yearlyMember,
            price: "$149.99",
            originalPrice: nil,
            detail: L10n.yearlyDetail,
            isSelected: false,
            discountCountdown: nil
        )
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            DT.Color.bgPrimary.edgesIgnoringSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    topHeader

                    // Option cards
                    optionsSection
                        .padding(.top, DT.Space.xl)

                    // Benefits
                    benefitsSection
                        .padding(.top, DT.Space.xxl)

                    // Terms
                    termsSection
                        .padding(.top, DT.Space.xl)
                        .padding(.bottom, mode == .tab ? 148 : 100)
                }
            }

            // Bottom fixed button
            bottomButton
        }
        .navigationTitle(L10n.vipCenter)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Top Header
extension MembershipView {

    private var topHeader: some View {
        ZStack(alignment: .topLeading) {
            // Golden gradient background
            LinearGradient(
                colors: [
                    Color(hex: "#1A1410"),
                    Color(hex: "#3D2B15"),
                    Color(hex: "#5C3D1A"),
                    Color(hex: "#3D2B15"),
                    Color(hex: "#1A1410")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)

            // Radial gold glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            DT.brandGold.opacity(0.12),
                            DT.brandGold.opacity(0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 150
                    )
                )
                .frame(width: 240, height: 240)
                .offset(x: 80, y: -20)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                // Crown + Title
                HStack(spacing: DT.Space.md) {
                    ZStack {
                        Circle()
                            .fill(DT.brandGold.opacity(0.18))
                            .frame(width: 56, height: 56)

                        Image(systemName: "crown.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(DT.brandGold)
                    }

                    VStack(alignment: .leading, spacing: DT.Space.xs) {
                        Text(L10n.joinMembership)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(DT.brandGold)

                        Text(L10n.unlockAllContent)
                            .font(DT.Font.bodyDefault)
                            .foregroundColor(DT.Color.textSecondary)
                    }
                }
                .padding(.bottom, DT.Space.xl)
            }
            .padding(.horizontal, DT.Space.pageH)
        }
    }
}

// MARK: - Option Cards
extension MembershipView {

    private var optionsSection: some View {
        VStack(spacing: DT.Space.md) {
            ForEach(options.indices, id: \.self) { index in
                optionCard(at: index)
            }
        }
        .padding(.horizontal, DT.Space.pageH)
    }

    private func optionCard(at index: Int) -> some View {
        let option = options[index]
        let isSelected = selectedOptionIndex == index

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedOptionIndex = index
            }
        }) {
            HStack(spacing: DT.Space.md) {
                // Radio indicator
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? DT.brandGold : DT.Color.textTertiary,
                            lineWidth: 2
                        )
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(DT.brandGold)
                            .frame(width: 12, height: 12)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    // Title + discount badge
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(DT.Font.body(16, weight: .semibold))
                            .foregroundColor(DT.Color.textPrimary)

                        if let countdown = option.discountCountdown {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9))
                                Text("\(L10n.discount) \(countdown)")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                LinearGradient(
                                    colors: [DT.hotTag, DT.hotTag.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(DT.Radius.full)
                        }
                    }

                    // Price row
                    HStack(alignment: .lastTextBaseline, spacing: DT.Space.xs) {
                        Text(option.price)
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundColor(
                                isSelected ? DT.brandGold : DT.Color.textPrimary
                            )

                        if let original = option.originalPrice {
                            Text(original)
                                .font(.system(size: 13))
                                .foregroundColor(DT.Color.textTertiary)
                                .strikethrough(true, color: DT.Color.textTertiary)
                        }
                    }

                    // Detail
                    Text(option.detail)
                        .font(DT.Font.caption)
                        .foregroundColor(DT.Color.textSecondary)
                }

                Spacer()
            }
            .padding(DT.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.lg)
                    .fill(isSelected ? DT.brandGold.opacity(0.08) : DT.Color.textPrimary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.lg)
                    .stroke(
                        isSelected ? DT.brandGold.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .shadow(
                color: isSelected ? DT.brandGold.opacity(0.15) : Color.clear,
                radius: 8, x: 0, y: 2
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Benefits List
extension MembershipView {

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            // Section header
            HStack(spacing: DT.Space.sm) {
                Rectangle()
                    .fill(DT.brandGold)
                    .frame(width: 3, height: 18)
                    .cornerRadius(1.5)

                Text(L10n.whyJoinVip)
                    .font(DT.Font.subtitle)
                    .foregroundColor(DT.Color.textPrimary)
            }
            .padding(.horizontal, DT.Space.pageH)

            // Benefits grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: DT.Space.sm
            ) {
                benefitItem(icon: "play.rectangle", text: L10n.benefitAllShows)
                benefitItem(icon: "arrow.down.to.line", text: L10n.benefitDownload)
                benefitItem(icon: "star.fill", text: L10n.benefitVipShows)
                benefitItem(icon: "sparkles", text: L10n.benefitThemes)
                benefitItem(icon: "4k.tv", text: L10n.benefitQuality)
                benefitItem(icon: "gift.fill", text: L10n.benefitGift)
                benefitItem(icon: "person.fill.checkmark", text: L10n.benefitFriendGift)
                benefitItem(icon: "speaker.slash", text: L10n.benefitNoAds)
            }
            .padding(.horizontal, DT.Space.pageH)
        }
    }

    private func benefitItem(icon: String, text: String) -> some View {
        HStack(spacing: DT.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .fill(DT.brandGold.opacity(0.12))
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DT.brandGold)
            }

            Text(text)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textSecondary)
                .lineLimit(2)
                .lineSpacing(2)

            Spacer(minLength: 0)
        }
        .padding(.vertical, DT.Space.xs)
    }
}

// MARK: - Terms
extension MembershipView {

    private var termsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Text(L10n.rechargeInfo)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textTertiary)

            HStack(spacing: 4) {
                Text(L10n.serviceAgreement)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)

                Text(">")
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textTertiary)
            }

            Text(L10n.terms1)
                .font(DT.Font.small)
                .foregroundColor(DT.Color.textTertiary)

            Text(L10n.terms2)
                .font(DT.Font.small)
                .foregroundColor(DT.Color.textTertiary)

            Text(L10n.terms3)
                .font(DT.Font.small)
                .foregroundColor(DT.Color.textTertiary)
        }
        .padding(.horizontal, DT.Space.pageH)
    }
}

// MARK: - Bottom Button
extension MembershipView {

    private var bottomButton: some View {
        Button(action: {
            Logger.ui.info("User tapped Join Membership")
        }) {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .medium))

                Text(L10n.joinNow)
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: DT.Layout.ctaButtonHeight)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#E8C34A"),
                        Color(hex: "#D4A832"),
                        Color(hex: "#C29852")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(DT.Radius.md)
            .shadow(
                color: DT.brandGold.opacity(0.3),
                radius: 12, x: 0, y: 4
            )
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.bottom, mode == .tab ? DT.Layout.tabBarHeight + DT.Space.xl : DT.Space.xl)
    }
}

// MARK: - Preview
#Preview {
    MembershipView()
        .preferredColorScheme(.dark)
}
