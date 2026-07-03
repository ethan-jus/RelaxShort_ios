import SwiftUI

// MARK: - Member View (Task32: DramaBox-style subscription page)

/// Member 会员订阅转化页。
/// - 底部 Tab 模式：全屏展示，无返回按钮
/// - Push 模式（profile/播放器入口）：显示返回按钮
///
/// 顶部暂时使用 `/api/v2/member` 返回的第一张 background poster 作为固定背景，
/// 套餐、权益为第一版临时静态配置，会员专属剧集使用真实数据 + 真实播放器导航。
struct MemberView: View {
    enum Mode {
        case push
        case tab
    }

    @EnvironmentObject var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: MemberViewModel
    @State private var scrollContentMinY: CGFloat = 0
    let mode: Mode

    init(mode: Mode, repository: MemberRepositoryProtocol) {
        self.mode = mode
        _viewModel = StateObject(
            wrappedValue: MemberViewModel(repository: repository)
        )
    }

    // MARK: - Layout Constants

    private let backgroundHeight: CGFloat = 300
    private let titleInitialTop: CGFloat = 112
    private let titleHeight: CGFloat = 52
    private let pageInset: CGFloat = 16
    private let planCardGap: CGFloat = 12
    private let planRadius: CGFloat = 6
    private let selectedRailWidth: CGFloat = 54
    private let benefitIconSize: CGFloat = 30
    private let benefitRowSpacing: CGFloat = 24
    private let ctaHeight: CGFloat = 56

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let topInset = max(
                geo.safeAreaInsets.top,
                UIApplication.safeAreaInsets.top
            )
            let bottomInset = max(
                geo.safeAreaInsets.bottom,
                UIApplication.safeAreaInsets.bottom
            )
            let tabClearance = mode == .tab
                ? DramaBoxBottomTabBar.totalHeight + bottomInset
                : bottomInset
            let reservedBottomHeight =
                ctaHeight + tabClearance + DT.Space.xl
            let titlePinned = scrollContentMinY <= -titleInitialTop

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                fixedBackground(
                    width: geo.size.width,
                    topInset: topInset
                )
                .opacity(titlePinned ? 0 : 1)

                ScrollView(.vertical, showsIndicators: false) {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MemberScrollOffsetPreferenceKey.self,
                            value: proxy.frame(
                                in: .named("member-scroll")
                            ).minY
                        )
                    }
                    .frame(height: 0)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: titleInitialTop)
                        memberTitle
                        plansSection
                            .padding(.top, DT.Space.md)
                        benefitsSection
                            .padding(.top, DT.Space.xxl)
                        memberDramasSection(width: geo.size.width)
                            .padding(.top, DT.Space.xxl)
                        termsSection
                            .padding(.top, DT.Space.xl)
                    }
                    .padding(.bottom, reservedBottomHeight)
                }
                .coordinateSpace(name: "member-scroll")

                if titlePinned {
                    stickyMemberTitle
                        .transition(.opacity)
                }

                fixedCTA(bottomClearance: tabClearance)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
            }
            .onPreferenceChange(MemberScrollOffsetPreferenceKey.self) {
                scrollContentMinY = $0
            }
            .animation(.easeOut(duration: 0.18), value: titlePinned)
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

// MARK: - Fixed Background + Sticky Title
extension MemberView {

    @ViewBuilder
    private func fixedBackground(width: CGFloat, topInset: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if let poster = viewModel.backgroundPosters.first {
                CoverImageView(
                    url: poster.coverURL,
                    aspectRatio: DT.Layout.bannerAspectRatio,
                    cornerRadius: 0,
                    width: width,
                    height: backgroundHeight + topInset
                )
                .frame(width: width, height: backgroundHeight + topInset)
                .clipped()
            } else {
                Color(hex: "#0D0D0D")
            }

            // 固定封面只承担氛围背景，渐变保证前景内容始终可读。
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.68),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Button(action: logRestoreTap) {
                Text("member.restore".localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, DT.Space.md)
                    .padding(.vertical, DT.Space.xs)
            }
            .padding(.top, topInset + DT.Space.sm)
            .padding(.trailing, pageInset)
        }
        .frame(width: width, height: backgroundHeight + topInset)
        .offset(y: -topInset)
        .ignoresSafeArea(edges: .top)
    }

    private var memberTitle: some View {
        Text("member.title".localized)
            .font(.system(size: 28, weight: .heavy))
            .foregroundColor(.white)
            .frame(
                maxWidth: .infinity,
                minHeight: titleHeight,
                alignment: .leading
            )
            .padding(.horizontal, pageInset)
    }

    private var stickyMemberTitle: some View {
        HStack(spacing: DT.Space.xs) {
            if mode == .push {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
            }

            Text("member.title".localized)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Button(action: logRestoreTap) {
                Text("member.restore".localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .frame(height: titleHeight)
        .padding(.horizontal, mode == .push ? DT.Space.sm : pageInset)
        .background(Color.black)
    }

    /// 第一版尚未接入恢复购买能力；只保留入口，不展示 Coming Soon。
    private func logRestoreTap() {
        #if DEBUG
        Logger.ui.info("Member Restore tapped — purchase flow is not integrated")
        #endif
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
                        .fill(isSelected ? DT.logoRed : DT.Color.textTertiary.opacity(0.3))
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
                                Text(
                                    "\("member.discount".localized) \(viewModel.formattedPromotionCountdown)"
                                )
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
                        isSelected ? DT.logoRed : DT.Color.textTertiary.opacity(0.3),
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
                .foregroundColor(.white)
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
                    .foregroundColor(DT.logoRed)
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

    private func fixedCTA(bottomClearance: CGFloat) -> some View {
        VStack(spacing: 0) {
            Button {
                #if DEBUG
                Logger.ui.info("Member Join Now tapped — purchase not available")
                #endif
            } label: {
                Text("member.join_now".localized)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: ctaHeight)
                    .background(
                        RoundedRectangle(cornerRadius: planRadius)
                            .fill(DT.logoRed)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, pageInset)
        }
        .padding(.bottom, bottomClearance + DT.Space.sm)
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
    MemberView(
        mode: .tab,
        repository: RealMemberRepository()
    )
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}

private struct MemberScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(
        value: inout CGFloat,
        nextValue: () -> CGFloat
    ) {
        value = nextValue()
    }
}
