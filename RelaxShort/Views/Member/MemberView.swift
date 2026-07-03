import SwiftUI

// MARK: - Member View (Task32: DramaBox-style subscription page)

/// Member 会员订阅转化页。
/// - 底部 Tab 模式：全屏展示，无返回按钮
/// - Push 模式（profile/播放器入口）：显示返回按钮
///
/// 顶部使用 `/api/v2/member` 返回的 background_posters 组成倾斜封面拼贴背景，
/// 套餐、权益为第一版临时静态配置，会员专属剧集使用真实数据 + 真实播放器导航。
struct MemberView: View {
    enum Mode {
        case push
        case tab
    }

    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: MemberViewModel
    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
        _viewModel = StateObject(wrappedValue: MemberViewModel())
    }

    // MARK: - Layout Constants

    private let headerHeight: CGFloat = 230
    private let pageInset: CGFloat = 16
    private let planCardGap: CGFloat = 12
    private let planRadius: CGFloat = 6
    private let selectedRailWidth: CGFloat = 54
    private let benefitIconSize: CGFloat = 30
    private let benefitRowSpacing: CGFloat = 24
    private let ctaHeight: CGFloat = 56

    private var reservedBottomHeight: CGFloat {
        ctaHeight + DT.Layout.tabBarHeight + DT.Space.xl
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        memberHeader(width: geo.size.width)
                        plansSection
                            .padding(.top, DT.Space.xl)
                        benefitsSection
                            .padding(.top, DT.Space.xxl)
                        memberDramasSection(width: geo.size.width)
                            .padding(.top, DT.Space.xxl)
                        termsSection
                            .padding(.top, DT.Space.xl)
                    }
                    .padding(.bottom, reservedBottomHeight)
                }

                // 固定底部 CTA
                fixedCTA
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadIfNeeded()
            viewModel.startPromotionCountdown()
        }
        .onDisappear {
            viewModel.stopPromotionCountdown()
        }
    }
}

// MARK: - Header (cover collage + title)
extension MemberView {

    @ViewBuilder
    private func memberHeader(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // 封面拼贴背景
            coverCollageBackground(width: width)
                .frame(height: headerHeight)
                .clipped()

            // 从上到下的黑色渐变（保证标题可读）
            LinearGradient(
                colors: [
                    Color.black.opacity(0.1),
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.85),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: headerHeight)

            // Top trailing: Restore 按钮
            HStack {
                Spacer()
                if mode == .push {
                    // Push 模式：返回按钮在左
                }
                Button(action: {
                    // 第一版：展示提示，不执行真实恢复
                }) {
                    Text("member.restore".localized)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DT.Color.textSecondary)
                        .padding(.horizontal, DT.Space.md)
                        .padding(.vertical, DT.Space.xs)
                }
                .padding(.top, DT.Space.xl)
                .padding(.trailing, pageInset)
            }

            // 返回按钮（push 模式）
            if mode == .push {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
                .padding(.top, DT.Space.xl)
                .padding(.leading, pageInset)
            }

            // 左下标题
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Spacer()
                Text("member.title".localized)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
            }
            .padding(.leading, pageInset)
            .padding(.bottom, DT.Space.lg)
        }
    }

    /// 使用 background_posters 真实封面组成的倾斜拼贴
    @ViewBuilder
    private func coverCollageBackground(width: CGFloat) -> some View {
        let posters = viewModel.backgroundPosters
        if posters.isEmpty {
            // API 无图时仅显示深色背景
            Color(hex: "#0D0D0D")
        } else {
            ZStack {
                // 拼贴布局：3 列倾斜 -12°，彼此重叠
                ForEach(Array(posters.prefix(8).enumerated()), id: \.element.id) { idx, drama in
                    let col = idx % 3
                    let row = idx / 3
                    let xOffset = CGFloat(col - 1) * (width / 3.2)
                    let yOffset = CGFloat(row) * (headerHeight / 3.5) - 20

                    CoverImageView(
                        url: drama.coverURL,
                        aspectRatio: DT.Layout.cardAspectRatio,
                        cornerRadius: 2,
                        width: width / 3.0,
                        height: (width / 3.0) / DT.Layout.cardAspectRatio
                    )
                    .rotationEffect(.degrees(-12))
                    .offset(x: xOffset, y: yOffset)
                    .opacity(0.65)
                }
                // 顶部到中部的黑色渐变覆盖
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

// MARK: - Plans Section
extension MemberView {

    private var plansSection: some View {
        VStack(spacing: planCardGap) {
            ForEach(MemberDisplayConfig.plans) { plan in
                planCard(for: plan)
            }
        }
        .padding(.horizontal, pageInset)
    }

    @ViewBuilder
    private func planCard(for plan: MemberPlanDisplayOption) -> some View {
        let isSelected = viewModel.selectedPlanID == plan.id

        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedPlanID = plan.id
            }
        }) {
            HStack(spacing: 0) {
                // 左侧选中栏
                ZStack {
                    Rectangle()
                        .fill(isSelected ? DT.brandPink : DT.Color.textTertiary.opacity(0.3))
                        .frame(width: selectedRailWidth)
                        .cornerRadius(planRadius, corners: [.topLeft, .bottomLeft])

                    // 选中标记
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: selectedRailWidth)

                // 套餐内容
                HStack {
                    VStack(alignment: .leading, spacing: DT.Space.xs) {
                        HStack(spacing: 6) {
                            Text(plan.titleKey.localized)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.white)

                            if plan.showsPromotion {
                                Text("member.discount".localized)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.purple.opacity(0.8))
                                    )
                            }
                        }

                        HStack(alignment: .lastTextBaseline, spacing: DT.Space.xs) {
                            Text(plan.price)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)

                            if let orig = plan.originalPrice {
                                Text(orig)
                                    .font(.system(size: 13))
                                    .foregroundColor(DT.Color.textTertiary)
                                    .strikethrough(true, color: DT.Color.textTertiary)
                            }
                        }

                        Text(plan.detailKey.localized)
                            .font(.system(size: 12))
                            .foregroundColor(DT.Color.textSecondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, DT.Space.md + 2)
            }
            .frame(height: plan.showsPromotion ? 130 : 112)
            .background(
                RoundedRectangle(cornerRadius: planRadius)
                    .fill(DT.Color.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: planRadius)
                    .stroke(
                        isSelected ? DT.brandPink : DT.Color.textTertiary.opacity(0.3),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Benefits Section
extension MemberView {

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            Text("member.why_join".localized)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, pageInset)

            VStack(spacing: benefitRowSpacing) {
                ForEach(MemberDisplayConfig.benefits) { benefit in
                    benefitRow(for: benefit)
                }
            }
            .padding(.horizontal, pageInset)
        }
    }

    private func benefitRow(for benefit: MemberDisplayConfig.Benefit) -> some View {
        HStack(spacing: DT.Space.md) {
            Image(systemName: benefit.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(DT.brandPink)
                .frame(width: benefitIconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.titleKey.localized)
                    .font(.system(size: 15))
                    .foregroundColor(.white)

                if let detailKey = benefit.detailKey {
                    Text(detailKey.localized)
                        .font(.system(size: 12))
                        .foregroundColor(DT.Color.textSecondary)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Member-Only Dramas Grid
extension MemberView {

    @ViewBuilder
    private func memberDramasSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            Text("member.dramas.title".localized)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, pageInset)

            switch viewModel.loadState {
            case .loading:
                loadingGridView(width: width)
            case .empty:
                emptyContentView
            case .failed:
                errorView
            default:
                if viewModel.memberOnlyDramas.isEmpty {
                    emptyContentView
                } else {
                    dramaGridView(width: width)
                }
            }
        }
    }

    private var columnSpacing: CGFloat { 12 }

    private func dramaGridView(width: CGFloat) -> some View {
        let available = width - pageInset * 2
        let cardWidth = (available - columnSpacing * 2) / 3
        let cardHeight = cardWidth / DT.Layout.cardAspectRatio
        let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: columnSpacing), count: 3)

        return LazyVGrid(columns: columns, spacing: DT.Space.md) {
            ForEach(viewModel.memberOnlyDramas) { drama in
                Button {
                    appStore.navigationTarget = SeriesPlayerNav(
                        drama: drama,
                        startEpisode: 1,
                        sourceScene: "member_only_dramas"
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        CoverImageView(
                            url: drama.coverURL,
                            aspectRatio: DT.Layout.cardAspectRatio,
                            cornerRadius: 2,
                            width: cardWidth,
                            height: cardHeight
                        )
                        Text(drama.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .frame(width: cardWidth)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, pageInset)
    }

    private func loadingGridView(width: CGFloat) -> some View {
        let available = width - pageInset * 2
        let cardWidth = (available - columnSpacing * 2) / 3
        let cardHeight = cardWidth / DT.Layout.cardAspectRatio
        let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: columnSpacing), count: 3)

        return LazyVGrid(columns: columns, spacing: DT.Space.md) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(DT.Color.bgCard)
                    .frame(width: cardWidth, height: cardHeight)
                    .shimmer(true)
            }
        }
        .padding(.horizontal, pageInset)
    }

    private var emptyContentView: some View {
        VStack(spacing: DT.Space.sm) {
            Image(systemName: "play.rectangle")
                .font(DT.Font.emptyIcon)
                .foregroundColor(DT.Color.textTertiary)
            Text("member.content.empty".localized)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.Space.xxl)
    }

    private var errorView: some View {
        VStack(spacing: DT.Space.sm) {
            Text("member.content.failed".localized)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textSecondary)
            Button(action: { viewModel.retry() }) {
                Text(L10n.commonRetry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DT.brandPink)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.Space.xxl)
    }
}

// MARK: - Terms Section
extension MemberView {

    private var termsSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(spacing: 4) {
                Text("member.service_agreement".localized)
                    .font(DT.Font.caption)
                    .underline()
                    .foregroundColor(DT.Color.textSecondary)

                Text(">")
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textTertiary)
            }

            Text("member.tips.title".localized)
                .font(DT.Font.small)
                .foregroundColor(DT.Color.textTertiary)

            Text("member.auto_renew".localized)
                .font(DT.Font.small)
                .foregroundColor(DT.Color.textTertiary)
        }
        .padding(.horizontal, pageInset)
    }
}

// MARK: - Fixed CTA
extension MemberView {

    private var fixedCTA: some View {
        VStack(spacing: 0) {
            Button(action: {
                // 第一版：展示提示，不执行真实购买
                let message = "member.purchase_unavailable".localized
                #if DEBUG
                Logger.ui.info("Member Join Now tapped — purchase not available")
                #endif
            }) {
                Text("member.join_now".localized)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: ctaHeight)
                    .background(
                        RoundedRectangle(cornerRadius: planRadius)
                            .fill(DT.brandPink)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, pageInset)
            .padding(.bottom, DT.Space.xs)
        }
        .padding(.bottom, DT.Layout.tabBarHeight)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Shimmer Modifier
extension View {
    func shimmer(_ active: Bool) -> some View {
        self.overlay(
            Group {
                if active {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        )
    }

    /// 使用已有的 RoundedCorner shape 裁剪指定角
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// MARK: - Preview
#Preview {
    MemberView(mode: .tab)
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
