import SwiftUI

// MARK: - VIP View (DramaBox Style)
struct VIPView: View {
    @EnvironmentObject var authStore: AuthStore
    @StateObject private var viewModel: VIPViewModel

    @State private var showCoupon = false

    init(viewModel: VIPViewModel? = nil) {
        let vm = viewModel ?? VIPViewModel(repository: MockVIPRepository())
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DB.black.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    topHeaderSection
                    planCardsSection
                    benefitsSection.padding(.top, DT.Space.xxl)
                    memberOnlySection.padding(.top, DT.Space.xxl)
                    termsSection
                        .padding(.top, DT.Space.lg)
                        .padding(.bottom, 100)
                }
            }

            fixedJoinNowButton
        }
        .overlay {
            if showCoupon {
                couponDialogView.zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Fixed Join Now

    private var fixedJoinNowButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) { showCoupon = true }
        } label: {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "crown.fill")
                Text(authStore.isVip ? "Renew Membership" : "Join Now")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: DT.Layout.ctaButtonHeight)
            .background(DB.pink)
            .cornerRadius(DB.ctaRadius)
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.bottom, 8)
        .background(DB.black.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Coupon Dialog

    private var couponDialogView: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showCoupon = false } }

            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(DB.gold.opacity(0.2)).frame(width: 72, height: 72)
                    Image(systemName: "gift.fill").font(.system(size: 32)).foregroundColor(DB.gold)
                }
                .padding(.top, 28).padding(.bottom, 16)

                Text("Congratulations!")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    .padding(.bottom, 6)
                Text("$7.00 OFF")
                    .font(.system(size: 36, weight: .heavy)).foregroundColor(DB.gold)
                    .padding(.bottom, 12)
                Text("Your first membership comes with a special discount. Limited time offer!")
                    .font(.system(size: 13)).foregroundColor(DB.mutedText)
                    .multilineTextAlignment(.center).padding(.horizontal, 28).padding(.bottom, 20)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showCoupon = false }
                } label: {
                    Text("Subscribe Now")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(DB.pink).cornerRadius(DB.ctaRadius)
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
            .frame(width: 300)
            .background(DB.panelElevated)
            .clipShape(RoundedRectangle(cornerRadius: DB.sheetCornerRadius))
        }
    }
}

// MARK: - Top Header (Golden Gradient + Crown + Title)
extension VIPView {

    @ViewBuilder
    private var topHeaderSection: some View {
        ZStack {
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
            .frame(height: 240)

            // Subtle radial gold glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            DT.brandGold.opacity(0.15),
                            DT.brandGold.opacity(0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 180
                    )
                )
                .frame(width: 280, height: 280)
                .offset(y: -20)

            // Content
            VStack(spacing: DT.Space.sm) {
                // Crown icon
                ZStack {
                    Circle()
                        .fill(DT.brandGold.opacity(0.2))
                        .frame(width: 72, height: 72)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(DT.brandGold)
                }
                .padding(.bottom, DT.Space.sm)

                // Main title
                Text(L10n.vipTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(DT.brandGold)

                // Subtitle
                Text(L10n.unlockAllContent)
                    .font(DT.Font.bodyDefault)
                    .foregroundColor(DT.Color.textSecondary)

                // VIP expiry info
                if authStore.isLoggedIn && authStore.isVip, let expireDate = authStore.vipExpireDate {
                    let days = viewModel.remainingDays(from: expireDate)
                    HStack(spacing: DT.Space.xs) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DT.brandGold)
                        if days > 30 {
                            Text(L10n.vipExpiry(viewModel.formattedExpiryDate(expireDate)))
                                .font(DT.Font.caption)
                        } else {
                            Text(L10n.remainingDays(days))
                                .font(DT.Font.caption)
                        }
                    }
                    .foregroundColor(DT.Color.textSecondary)
                    .padding(.top, DT.Space.xs)
                }
            }
        }
    }
}

// MARK: - Plan Cards (Horizontal Scroll)
extension VIPView {

    @ViewBuilder
    private var planCardsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Space.md) {
                    ForEach(viewModel.plans) { plan in
                        planCard(for: plan)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
            }
        }
        .padding(.top, -24) // overlap into header slightly
    }

    @ViewBuilder
    private func planCard(for plan: VIPPlan) -> some View {
        let isSelected = viewModel.selectedPlanId == plan.id

        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.selectedPlanId = plan.id
            }
        }) {
            VStack(spacing: DT.Space.sm) {
                // Title row with recommendation badge
                ZStack(alignment: .topTrailing) {
                    // Dummy spacer for alignment
                    Color.clear.frame(height: 0)

                    if plan.isRecommended {
                        Text(L10n.recommended)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(
                                    colors: [DT.hotTag, DT.hotTag.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(DT.Radius.full)
                            .offset(y: -22)
                    }
                }
                .frame(maxWidth: .infinity)

                // Period title
                Text(plan.title)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
                    .padding(.top, plan.isRecommended ? 0 : DT.Space.sm)

                // Price - large number
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(plan.price)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(
                            isSelected ? DT.brandGold : DT.Color.textPrimary
                        )

                    Text(plan.period)
                        .font(DT.Font.priceUnit)
                        .foregroundColor(DT.Color.textTertiary)
                        .padding(.leading, 1)
                }

                // Original price strikethrough
                if let originalPrice = plan.originalPrice {
                    Text(originalPrice)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DT.Color.textTertiary)
                        .strikethrough(true, color: DT.Color.textTertiary)
                }

                // Discount badge
                if let discount = plan.discountPercent {
                    Text("-\(discount)%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DT.hotTag)
                } else if plan.isRecommended {
                    // Placeholder to keep spacing consistent
                    Color.clear.frame(height: 14)
                }

                Spacer(minLength: 0)
            }
            .frame(width: 100, height: 170)
            .padding(.vertical, DT.Space.md)
            .padding(.horizontal, DT.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.lg)
                    .fill(isSelected ? DT.brandGold.opacity(0.08) : DT.Color.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.lg)
                    .stroke(
                        isSelected ? DT.brandGold : Color.clear,
                        lineWidth: 2
                    )
            )
            // Subtle glow when selected
            .shadow(
                color: isSelected ? DT.brandGold.opacity(0.2) : Color.clear,
                radius: 12, x: 0, y: 4
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Benefits Section
extension VIPView {

    @ViewBuilder
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
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

            // Benefits list
            VStack(spacing: 0) {
                ForEach(Array(viewModel.benefits.enumerated()), id: \.element.id) { index, benefit in
                    benefitRow(for: benefit)

                    if index < viewModel.benefits.count - 1 {
                        Divider()
                            .background(DT.Color.bgDivider)
                            .padding(.leading, DT.Space.pageH + 44)
                    }
                }
            }
            .background(DT.Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            .padding(.horizontal, DT.Space.pageH)
        }
    }

    @ViewBuilder
    private func benefitRow(for benefit: VIPBenefit) -> some View {
        HStack(spacing: DT.Space.md) {
            // Icon with gold tint
            ZStack {
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .fill(DT.brandGold.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: benefit.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DT.brandGold)
            }

            Text(benefit.title)
                .font(DT.Font.bodyDefault)
                .foregroundColor(DT.Color.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DT.Color.textTertiary)
        }
        .padding(.horizontal, DT.Space.lg)
        .padding(.vertical, DT.Space.md + 2)
    }
}

// MARK: - Members-only Dramas Section
extension VIPView {

    @ViewBuilder
    private var memberOnlySection: some View {
        let dramas = MockData.memberOnlyDramas
        VStack(alignment: .leading, spacing: DT.Space.md) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(DB.pink).frame(width: 3, height: 18)
                Text("Members-only Dramas").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text("See All").font(.system(size: 13)).foregroundColor(DB.mutedText)
            }
            .padding(.horizontal, DT.Space.pageH)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Space.sm) {
                    ForEach(dramas) { drama in
                        VStack(alignment: .leading, spacing: 6) {
                            CoverImageView(
                                url: drama.coverURL, aspectRatio: 2.0/3.0,
                                cornerRadius: DB.posterRadius, width: 100, height: 150
                            )
                            .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
                            Text(drama.title).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1).frame(width: 100)
                            Text("\(drama.episodeCount) EP").font(.system(size: 10)).foregroundColor(DB.mutedText)
                        }
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
            }
        }
    }

}

// MARK: - Terms Section
extension VIPView {

    @ViewBuilder
    private var termsSection: some View {
        VStack(spacing: DT.Space.sm) {
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
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DT.Space.pageH)
    }
}

// MARK: - Preview
#Preview {
    VIPView()
        .environmentObject(AuthStore())
        .preferredColorScheme(.dark)
}
