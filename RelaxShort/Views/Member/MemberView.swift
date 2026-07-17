import SwiftUI
import StoreKit
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
            let nextOffset = max(0, normalizedOffset)

            // KVO 可能在 UIViewRepresentable 的 update/layout 周期内同步回调。
            // 下一轮主队列再写 Binding，避免 SwiftUI 的“view update 期间修改状态”警告。
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      abs(self.offsetY.wrappedValue - nextOffset) > 0.5 else { return }
                self.offsetY.wrappedValue = nextOffset
            }
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
/// 套餐、权益、促销窗口与法律链接由 `/api/v2/member` 管理；
/// 价格、优惠资格与购买结果以 StoreKit 为准。
struct MemberView: View {
    enum Mode {
        case push
        case tab
    }

    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var storeKit: StoreKitManager
    @EnvironmentObject private var dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: MemberViewModel
    @State private var scrollOffsetY: CGFloat = 0
    @State private var purchaseMessage: String?
    @State private var showsPurchaseMessage = false
    @State private var purchaseAlertOffersProfile = false
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
    @ScaledMetric(relativeTo: .largeTitle)
    private var titleHeight: CGFloat = 52
    private let pageInset: CGFloat = 16
    private let planCardGap: CGFloat = 12
    private let planRadius: CGFloat = 6
    private let selectedRailWidth: CGFloat = 54
    private let benefitIconSize: CGFloat = 30
    private let benefitRowSpacing: CGFloat = 24

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
                : 0
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
                    .padding(.bottom, DT.Space.xl)
                }

                pinnedTitleMask
                    .opacity(pinProgress)
                    .zIndex(2)

                memberTitle
                    .offset(y: titleOffsetY)
                    .zIndex(3)

            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                fixedCTA(
                    bottomClearance: tabClearance,
                    availableWidth: geo.size.width
                )
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadIfNeeded()
            viewModel.startPromotionCountdown()
            Task { await synchronizeServerMembership() }
        }
        .onDisappear {
            viewModel.stopPromotionCountdown()
        }
        .alert(purchaseMessage ?? "", isPresented: $showsPurchaseMessage) {
            if purchaseAlertOffersProfile {
                Button("member.go_to_profile".localized) {
                    if mode == .push {
                        dismiss()
                    }
                    appStore.selectedTab = .profile
                }
            }
            Button(
                purchaseAlertOffersProfile
                    ? "common.cancel".localized
                    : "OK",
                role: .cancel
            ) {}
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
        .accessibilityHidden(true)
    }

    /// 标题和恢复购买始终使用同一个视图，仅连续改变纵向位置，避免吸附时闪切。
    private var memberTitle: some View {
        HStack(spacing: DT.Space.xs) {
            if mode == .push {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("common.back".localized)
            }

            Text("member.title".localized)
                .font(.largeTitle.weight(.heavy))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Button(action: restorePurchase) {
                Text("member.restore".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(storeKit.isPurchasing)
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

    private func restorePurchase() {
        guard !storeKit.isPurchasing else { return }
        Task {
            do {
                let token = try await storeKit.resolveAppAccountToken {
                    try await dependencies.detailRepository.fetchAppleAccountToken()
                }
                let receipts = try await storeKit.restoreVIPPurchases(appAccountToken: token)
                for receipt in receipts where receipt.requiresBackendVerification {
                    let account = try await dependencies.detailRepository.verifyVIPPurchase(receipt)
                    guard account.isVIP else {
                        throw APIError(code: "VIP_NOT_ACTIVE", message: "会员权益尚未生效，请稍后重试")
                    }
                    await storeKit.completeVIPDelivery(receipt)
                }
                showPurchaseMessage("profile.membership_active".localized)
            } catch {
                handlePurchaseError(error)
            }
        }
    }
}

// MARK: - Plans Section
extension MemberView {

    private var plansSection: some View {
        VStack(spacing: planCardGap) {
            if viewModel.plans.isEmpty {
                switch viewModel.loadState {
                case .idle, .loading:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                case .loaded, .empty, .failed:
                    VStack(spacing: DT.Space.sm) {
                        Text("member.plans_unavailable".localized)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.76))
                            .multilineTextAlignment(.center)
                        Button(L10n.commonRetry) {
                            viewModel.retry()
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88)
                }
            } else {
                ForEach(viewModel.plans) { plan in
                    planCard(for: plan)
                }

                if viewModel.plans.allSatisfy({
                    storeKit.storeDisplayPrice(for: $0.productID) == nil
                }) {
                    Button {
                        Task { await storeKit.requestProducts() }
                    } label: {
                        HStack(spacing: DT.Space.sm) {
                            if storeKit.isLoadingProducts {
                                ProgressView().tint(.white)
                            }
                            Text("member.retry_app_store".localized)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .disabled(storeKit.isLoadingProducts)
                }
            }
        }
        .padding(.horizontal, pageInset)
    }

    @ViewBuilder
    private func planCard(for plan: MemberPlanDisplayOption) -> some View {
        let isSelected = viewModel.selectedPlanID == plan.id
        let standardPrice = storeKit.storeDisplayPrice(
            for: plan.productID
        )
        let offer = activeOffer(for: plan)
        let displayedPrice = offer?.displayPrice
            ?? standardPrice
            ?? "member.price_unavailable".localized

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
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: selectedRailWidth)

                HStack {
                    VStack(alignment: .leading, spacing: DT.Space.sm) {
                        Text(plan.titleKey.localized)
                            .font(.headline)
                            .foregroundColor(.white)

                        if let promotion = plan.promotion,
                           offer != nil,
                           let countdown = viewModel
                            .formattedPromotionCountdown(for: promotion) {
                            Text(
                                "\(promotion.badgeKey.localized) \(countdown)"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, DT.Space.sm)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.purple.opacity(0.9))
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(alignment: .lastTextBaseline, spacing: DT.Space.xs) {
                            Text(displayedPrice)
                                .font(.title2.weight(.bold))
                                .foregroundColor(.white)

                            if offer != nil, let standardPrice {
                                Text(standardPrice)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.68))
                                    .strikethrough(
                                        true,
                                        color: .white.opacity(0.68)
                                    )
                            }
                        }

                        if let offer,
                           let promotion = plan.promotion {
                            Text(
                                String(
                                    format: promotion.titleKey.localized,
                                    offer.displayPrice,
                                    offer.periodCount
                                )
                            )
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(plan.detailKey.localized)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.76))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, DT.Space.lg)
            }
            .frame(minHeight: 112)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            planAccessibilityLabel(
                plan: plan,
                displayedPrice: displayedPrice,
                standardPrice: standardPrice,
                offer: offer
            )
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func activeOffer(
        for plan: MemberPlanDisplayOption
    ) -> VIPIntroductoryOfferDisplay? {
        guard let promotion = plan.promotion,
              promotion.offerType == .introductory else {
            return nil
        }
        let offer = storeKit.introductoryOffer(for: plan.productID)
        return promotion.canDisplay(
            at: viewModel.currentDate,
            hasMatchingStoreOffer: offer?.matches(promotion) == true
        ) ? offer : nil
    }

    private func planAccessibilityLabel(
        plan: MemberPlanDisplayOption,
        displayedPrice: String,
        standardPrice: String?,
        offer: VIPIntroductoryOfferDisplay?
    ) -> String {
        guard let offer,
              let promotion = plan.promotion,
              let standardPrice else {
            return "\(plan.titleKey.localized), \(displayedPrice), \(plan.detailKey.localized)"
        }
        let offerDisclosure = String(
            format: promotion.titleKey.localized,
            offer.displayPrice,
            offer.periodCount
        )
        return "\(plan.titleKey.localized), \(offerDisclosure), \("member.standard_price".localized) \(standardPrice)"
    }
}

// MARK: - Benefits Section
extension MemberView {

    private var benefitsSection: some View {
        Group {
            if !viewModel.benefits.isEmpty {
                VStack(alignment: .leading, spacing: DT.Space.lg) {
                    Text("member.why_join".localized)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, pageInset)

                    VStack(spacing: benefitRowSpacing) {
                        ForEach(viewModel.benefits) { benefit in
                            benefitRow(for: benefit)
                        }
                    }
                    .padding(.horizontal, pageInset)
                }
            }
        }
    }

    private func benefitRow(
        for benefit: MemberBenefitDisplayItem
    ) -> some View {
        HStack(spacing: DT.Space.md) {
            Image(systemName: benefit.icon)
                .font(.headline.weight(.medium))
                .foregroundColor(.white)
                .frame(width: benefitIconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.titleKey.localized)
                    .font(.body)
                    .foregroundColor(.white)

                if let detailKey = benefit.detailKey {
                    Text(detailKey.localized)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.76))
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Member-Only Dramas Grid
extension MemberView {

    @ViewBuilder
    private func memberDramasSection(width: CGFloat) -> some View {
        switch viewModel.loadState {
        case .idle, .empty:
            EmptyView()
        case .loaded where viewModel.memberOnlyDramas.isEmpty:
            EmptyView()
        case .loading, .loaded, .failed:
            VStack(alignment: .leading, spacing: DT.Space.md) {
                Text("member.dramas.title".localized)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, pageInset)

                switch viewModel.loadState {
                case .loading:
                    loadingGridView(width: width)
                case .failed:
                    errorView
                default:
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
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DT.logoRed)
                    .frame(minWidth: 44, minHeight: 44)
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
                .font(.headline)
                .foregroundColor(.white.opacity(0.82))

            VStack(alignment: .leading, spacing: DT.Space.sm) {
                ForEach([
                    "member.disclosure.access",
                    "member.disclosure.renewal",
                    "member.disclosure.restore"
                ], id: \.self) { key in
                    Text(key.localized)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.76))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: DT.Space.xs) {
                if let links = viewModel.legalLinks {
                    Link(
                        "member.terms".localized,
                        destination: links.termsURL
                    )
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    Link(
                        "member.privacy".localized,
                        destination: links.privacyURL
                    )
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                } else {
                    Text("member.legal_unavailable".localized)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.76))
                    Button(L10n.commonRetry) {
                        viewModel.retry()
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }

                Button(
                    "member.manage_subscription".localized,
                    action: manageSubscription
                )
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white)
            .tint(.white)
            .frame(minHeight: 44, alignment: .leading)
        }
        .padding(.horizontal, pageInset)
    }

    private func manageSubscription() {
        Task {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            else {
                showPurchaseMessage(
                    "member.manage_subscription_unavailable".localized
                )
                return
            }
            do {
                try await StoreKit.AppStore.showManageSubscriptions(in: scene)
            } catch {
                showPurchaseMessage(error.localizedDescription)
            }
        }
    }
}

// MARK: - Fixed CTA
extension MemberView {

    private func fixedCTA(
        bottomClearance: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        let buttonWidth = max(272, min(availableWidth - 48, 340))
        let plan = viewModel.plans.first {
            $0.id == viewModel.selectedPlanID
        }
        let displayedPrice = plan.flatMap {
            activeOffer(for: $0)?.displayPrice
                ?? storeKit.storeDisplayPrice(for: $0.productID)
        }
        let canPurchase = MemberPurchasePolicy.canPurchase(
            hasPlan: plan != nil,
            hasStorePrice: displayedPrice != nil,
            hasLegalLinks: viewModel.legalLinks != nil
        )
        let buttonTitle: String
        if storeKit.vipPurchaseState.hasActiveSubscription {
            buttonTitle = "profile.membership_active".localized
        } else if let plan, let displayedPrice {
            buttonTitle = String(
                format: "member.cta.subscribe".localized,
                plan.titleKey.localized,
                displayedPrice
            )
        } else {
            buttonTitle = "member.join_now".localized
        }

        return VStack(spacing: DT.Space.sm) {
            Button {
                purchaseSelectedPlan()
            } label: {
                Group {
                    if storeKit.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(buttonTitle)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, DT.Space.md)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: DB.posterRadius)
                        .fill(DT.logoRed)
                )
            }
            .buttonStyle(.plain)
            .disabled(
                storeKit.isPurchasing
                    || storeKit.vipPurchaseState.hasActiveSubscription
                    || !canPurchase
            )
            .frame(width: buttonWidth)
            .accessibilityLabel(buttonTitle)

            Text("member.auto_renew".localized)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.76))
        }
        .padding(.top, DT.Space.md)
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

    private func purchaseSelectedPlan() {
        guard !storeKit.isPurchasing,
              let plan = viewModel.plans.first(where: { $0.id == viewModel.selectedPlanID }),
              storeKit.storeDisplayPrice(for: plan.productID) != nil,
              viewModel.legalLinks != nil,
              let subscription = storeKit.vipSubscriptions.first(where: { $0.productID == plan.productID }) else {
            return
        }

        Task {
            do {
                let token = try await storeKit.resolveAppAccountToken {
                    try await dependencies.detailRepository.fetchAppleAccountToken()
                }
                let receipt = try await storeKit.purchaseVIP(
                    subscription,
                    appAccountToken: token
                )
                if receipt.requiresBackendVerification {
                    let account = try await dependencies.detailRepository.verifyVIPPurchase(receipt)
                    guard account.isVIP else {
                        throw APIError(code: "VIP_NOT_ACTIVE", message: "会员权益尚未生效，请稍后重试")
                    }
                    await storeKit.completeVIPDelivery(receipt)
                }
                showPurchaseMessage("profile.membership_active".localized)
            } catch StoreKitPurchaseError.userCancelled {
                return
            } catch {
                handlePurchaseError(error)
            }
        }
    }

    private func showPurchaseMessage(
        _ message: String,
        offersProfile: Bool = false
    ) {
        purchaseMessage = message
        purchaseAlertOffersProfile = offersProfile
        showsPurchaseMessage = true
    }

    private func handlePurchaseError(_ error: Error) {
        let apiCode = (error as? APIError)?.code
        let apiRequiresLogin = [
            "UNAUTHORIZED",
            "AUTH_ACCESS_TOKEN_EXPIRED",
            "AUTH_REFRESH_TOKEN_INVALID",
            "AUTH_REFRESH_TOKEN_REUSED"
        ].contains(apiCode)
        let networkRequiresLogin: Bool
        if let networkError = error as? NetworkError,
           case .unauthorized = networkError {
            networkRequiresLogin = true
        } else {
            networkRequiresLogin = false
        }

        if apiRequiresLogin || networkRequiresLogin || !authStore.hasSession {
            showPurchaseMessage(
                "member.login_required".localized,
                offersProfile: true
            )
        } else {
            showPurchaseMessage(error.localizedDescription)
        }
    }

    private func synchronizeServerMembership() async {
        do {
            let account = try await dependencies.detailRepository.fetchUnlockAccount()
            storeKit.synchronizeServerVIP(isActive: account.isVIP)
        } catch {
            #if DEBUG
            Logger.ui.warning("MemberView: membership sync failed — \(error.localizedDescription)")
            #endif
        }
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
        .environmentObject(AuthStore())
        .environmentObject(StoreKitManager())
        .environmentObject(DependencyContainer())
        .preferredColorScheme(.dark)
}
