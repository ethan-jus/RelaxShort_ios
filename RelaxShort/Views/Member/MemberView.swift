import SwiftUI
import UIKit

/// 直接监听 SwiftUI ScrollView 底层 UIScrollView 的标准化滚动距离。
/// 相比 PreferenceKey，该值不受视图吸附、惰性卸载和坐标空间重建影响。
private struct MemberScrollOffsetReader: UIViewRepresentable {
    @Binding var offsetY: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetY: $offsetY)
    }

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.coordinator = context.coordinator
        context.coordinator.attach(to: view.nearestVerticalScrollView)
    }

    final class ObserverView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attach()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attach()
        }

        private func attach() {
            coordinator?.attach(to: nearestVerticalScrollView)
        }
    }

    final class Coordinator: NSObject {
        private var offsetY: Binding<CGFloat>
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(offsetY: Binding<CGFloat>) {
            self.offsetY = offsetY
        }

        func attach(to scrollView: UIScrollView?) {
            guard let scrollView, self.scrollView !== scrollView else { return }
            self.scrollView = scrollView
            publishOffset(from: scrollView)
            observation = scrollView.observe(
                \.contentOffset,
                options: [.new]
            ) { [weak self] scrollView, _ in
                self?.publishOffset(from: scrollView)
            }
        }

        private func publishOffset(from scrollView: UIScrollView) {
            let normalizedOffset =
                scrollView.contentOffset.y
                + scrollView.adjustedContentInset.top
            offsetY.wrappedValue = max(0, normalizedOffset)
        }
    }
}

private extension UIView {
    var nearestVerticalScrollView: UIScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                let isVertical =
                    scrollView.alwaysBounceVertical
                    || scrollView.contentSize.height > scrollView.bounds.height
                if isVertical {
                    return scrollView
                }
            }
            view = current.superview
        }
        return nil
    }
}

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
    @State private var scrollOffsetY: CGFloat = 0
    let mode: Mode

    init(mode: Mode, repository: MemberRepositoryProtocol) {
        self.mode = mode
        _viewModel = StateObject(
            wrappedValue: MemberViewModel(repository: repository)
        )
    }

    // MARK: - Layout Constants

    private let backgroundHeight: CGFloat = 260
    private let titleInitialTop: CGFloat = 64
    private let titleHeight: CGFloat = 52
    private let pageInset: CGFloat = 16
    private let planCardGap: CGFloat = 12
    private let planRadius: CGFloat = 6
    private let selectedRailWidth: CGFloat = 54
    private let benefitIconSize: CGFloat = 30
    private let benefitRowSpacing: CGFloat = 24
    private let ctaHeight: CGFloat = 50

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
                ctaHeight + 30 + tabClearance + DT.Space.xl
            let titleOffsetY = max(
                titleInitialTop - scrollOffsetY,
                0
            )
            let pinProgress = min(
                max(
                    (scrollOffsetY - titleInitialTop + 12) / 12,
                    0
                ),
                1
            )

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                fixedBackground(
                    width: geo.size.width,
                    topInset: topInset
                )
                .opacity(1 - pinProgress)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        MemberScrollOffsetReader(offsetY: $scrollOffsetY)
                            .frame(width: 1, height: 1)

                        Color.clear.frame(
                            height: titleInitialTop + titleHeight - 1
                        )

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

                pinnedTitleMask
                    .opacity(pinProgress)
                    .zIndex(2)

                memberTitle
                    .offset(y: titleOffsetY)
                    .zIndex(3)

                fixedCTA(
                    bottomClearance: tabClearance,
                    availableWidth: geo.size.width
                )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottom
                    )
                    .zIndex(4)
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

// MARK: - Fixed Background + Sticky Title
extension MemberView {

    @ViewBuilder
    private func fixedBackground(width: CGFloat, topInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
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

        }
        .frame(width: width, height: backgroundHeight + topInset)
        .offset(y: -topInset)
        .ignoresSafeArea(edges: .top)
    }

    /// 标题和恢复购买始终使用同一个视图，仅连续改变纵向位置，避免吸附时闪切。
    private var memberTitle: some View {
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
                .font(.system(size: 28, weight: .heavy))
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
    }

    /// 接近吸附点时连续渐入，覆盖状态栏和标题区域，滚动内容不会透出。
    private var pinnedTitleMask: some View {
        Color.black
            .frame(height: titleHeight)
            .background(
                Color.black
                    .ignoresSafeArea(edges: .top)
            )
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
        VStack(alignment: .leading, spacing: DT.Space.md) {
            Text("member.tips.title".localized)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DT.Color.textSecondary)

            Text("member.service_agreement".localized)
                .font(.system(size: 14))
                .underline()
                .foregroundColor(DT.Color.textSecondary)

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                ForEach(1...10, id: \.self) { index in
                    Text("member.tips.item\(index)".localized)
                        .font(.system(size: 13))
                        .foregroundColor(DT.Color.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, pageInset)
    }
}

// MARK: - Fixed CTA
extension MemberView {

    private func fixedCTA(
        bottomClearance: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        let buttonWidth = max(272, min(availableWidth - 48, 340))

        return VStack(spacing: DT.Space.sm) {
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
                        RoundedRectangle(cornerRadius: DB.posterRadius)
                            .fill(DT.logoRed)
                    )
            }
            .buttonStyle(.plain)
            .frame(width: buttonWidth)

            Text("member.auto_renew".localized)
                .font(.system(size: 12))
                .foregroundColor(DT.Color.textSecondary)
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
