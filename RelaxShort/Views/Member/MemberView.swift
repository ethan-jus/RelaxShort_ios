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

    private let heroHeight: CGFloat = 410
    private let pageInset: CGFloat = 16
    private let planCardGap: CGFloat = 8
    private let planRadius: CGFloat = 12
    private var memberGold: Color { DT.memberGold }

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

            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        heroSection(
                            width: geo.size.width,
                            topInset: topInset
                        )

                        plansSection
                            .padding(.top, DT.Space.sm)
                        benefitsSection
                            .padding(.top, 36)
                        memberDramasSection(width: geo.size.width)
                            .padding(.top, 36)
                        membershipSimpleSection
                            .padding(.top, 36)
                        termsSection
                            .padding(.top, 28)
                    }
                    .padding(.bottom, 28)
                }
                .ignoresSafeArea(edges: .top)
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

// MARK: - Hero
extension MemberView {

    private func heroSection(width: CGFloat, topInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if let poster = viewModel.backgroundPosters.first {
                CoverImageView(
                    url: poster.coverURL,
                    aspectRatio: 0.9,
                    cornerRadius: 0,
                    width: width,
                    height: heroHeight + topInset
                )
                .frame(width: width, height: heroHeight + topInset)
                .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: "#260705"),
                        Color(hex: "#090303"),
                        .black
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottom
                )
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.24),
                    Color.black.opacity(0.46),
                    Color.black.opacity(0.84),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    DT.logoRed.opacity(0.24),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 280
            )

            VStack(spacing: 0) {
                memberHeader

                Spacer(minLength: 8)

                VIPCrownView(
                    width: 128,
                    height: 94,
                    glowColor: memberGold,
                    glowRadius: 3
                )

                Text("vip.unlock_all".localized)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(memberGold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .padding(.top, 6)

                Text("member.benefit.unlimited_detail".localized)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 6)
                    .padding(.horizontal, 34)

                Spacer(minLength: 24)
            }
            .padding(.top, topInset)
            .padding(.horizontal, pageInset)
        }
        .frame(width: width, height: heroHeight + topInset)
        .accessibilityElement(children: .contain)
    }

    private var memberHeader: some View {
        HStack(spacing: 4) {
            if mode == .push {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel("common.back".localized)
            }

            Text("member.title".localized)
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button(action: restorePurchase) {
                Text("member.restore".localized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(storeKit.isPurchasing)
        }
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
                HStack(alignment: .bottom, spacing: planCardGap) {
                    ForEach(viewModel.plans) { plan in
                        planCard(for: plan)
                    }
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
            VStack(spacing: 7) {
                HStack(spacing: 4) {
                    Text(plan.titleKey.localized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(memberGold)
                            .accessibilityHidden(true)
                    }
                }

                Text(displayedPrice)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                if offer != nil, let standardPrice {
                    Text(standardPrice)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .strikethrough(true, color: .white.opacity(0.5))
                        .lineLimit(1)
                }

                Group {
                    if let promotion = plan.promotion,
                       offer != nil,
                       let countdown = viewModel
                        .formattedPromotionCountdown(for: promotion) {
                        Text(
                            "\(promotion.badgeKey.localized) · \(countdown)"
                        )
                    } else {
                        Text(plan.detailKey.localized)
                    }
                }
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? memberGold : .white.opacity(0.48))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(minHeight: 26, alignment: .top)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(minHeight: isSelected ? 142 : 132)
            .background(
                RoundedRectangle(cornerRadius: planRadius)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    Color(hex: "#510D0B"),
                                    Color(hex: "#220706")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [
                                    Color(hex: "#101010"),
                                    Color(hex: "#070707")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: planRadius)
                    .stroke(
                        isSelected
                            ? memberGold
                            : Color.white.opacity(0.14),
                        lineWidth: isSelected ? 1.2 : 0.7
                    )
            )
            .shadow(
                color: isSelected ? DT.logoRed.opacity(0.2) : .clear,
                radius: 12,
                y: 5
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
                let primaryBenefits = Array(viewModel.benefits.prefix(4))
                let moreBenefits = Array(viewModel.benefits.dropFirst(4))

                VStack(alignment: .leading, spacing: 16) {
                    Text("member.why_join".localized)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 0),
                            GridItem(.flexible(), spacing: 0)
                        ],
                        spacing: 0
                    ) {
                        ForEach(
                            Array(primaryBenefits.enumerated()),
                            id: \.element.id
                        ) { index, benefit in
                            primaryBenefitCell(
                                benefit,
                                index: index,
                                count: primaryBenefits.count
                            )
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#0B0B0B"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )

                    if !moreBenefits.isEmpty {
                        Text("member.more_benefits".localized)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        VStack(spacing: 0) {
                            ForEach(
                                Array(moreBenefits.enumerated()),
                                id: \.element.id
                            ) { index, benefit in
                                secondaryBenefitRow(benefit)

                                if index < moreBenefits.count - 1 {
                                    Divider()
                                        .overlay(Color.white.opacity(0.1))
                                        .padding(.leading, 58)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#0B0B0B"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                    }
                }
                .padding(.horizontal, pageInset)
            }
        }
    }

    private func primaryBenefitCell(
        _ benefit: MemberBenefitDisplayItem,
        index: Int,
        count: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: benefit.icon)
                .font(.system(size: 25, weight: .regular))
                .foregroundColor(memberGold)
                .frame(width: 34, height: 30, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.titleKey.localized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let detailKey = benefit.detailKey {
                    Text(detailKey.localized)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.56))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .overlay(alignment: .trailing) {
            if index.isMultiple(of: 2), index + 1 < count {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if index < 2, count > 2 {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func secondaryBenefitRow(
        _ benefit: MemberBenefitDisplayItem
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: benefit.icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(memberGold)
                .frame(width: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(benefit.titleKey.localized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                if let detailKey = benefit.detailKey {
                    Text(detailKey.localized)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.56))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.58))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 76)
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
            VStack(alignment: .leading, spacing: 16) {
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

        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(viewModel.memberOnlyDramas) { drama in
                Button {
                    appStore.navigationTarget = SeriesPlayerNav(
                        drama: drama,
                        startEpisode: 1,
                        sourceScene: "member_only_dramas"
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            CoverImageView(
                                url: drama.coverURL,
                                aspectRatio: DT.Layout.cardAspectRatio,
                                cornerRadius: 8,
                                width: cardWidth,
                                height: cardHeight
                            )

                            Text("VIP")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(hex: "#2A1603"))
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(memberGold)
                                .clipShape(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: 8,
                                        bottomTrailingRadius: 5
                                    )
                                )
                        }
                        Text(drama.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
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

        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
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

// MARK: - Membership Guidance
extension MemberView {

    private var membershipSimpleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("member.simple_title".localized)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            VStack(spacing: 0) {
                membershipSimpleRow(
                    icon: "bolt",
                    title: "member.benefit.unlimited".localized,
                    detail: "member.benefit.unlimited_detail".localized
                )

                membershipGuideDivider

                membershipSimpleRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "member.auto_renew".localized,
                    detail: "member.disclosure.renewal".localized
                )

                membershipGuideDivider

                membershipSimpleRow(
                    icon: "arrow.clockwise",
                    title: "member.restore".localized,
                    detail: "member.disclosure.restore".localized,
                    actionTitle: "member.restore".localized,
                    action: restorePurchase
                )
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#0B0B0B"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, pageInset)
    }

    private var membershipGuideDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.1))
            .padding(.leading, 50)
    }

    private func membershipSimpleRow(
        icon: String,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(memberGold)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.56))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(memberGold)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(storeKit.isPurchasing)
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 76)
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

// MARK: - Terms Section
extension MemberView {

    private var termsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("member.subscription_details".localized)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 10) {
                ForEach([
                    "member.disclosure.access",
                    "member.disclosure.renewal",
                    "member.disclosure.restore"
                ], id: \.self) { key in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.white.opacity(0.42))
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)

                        Text(key.localized)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.58))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: 0) {
                if let links = viewModel.legalLinks {
                    Link(
                        destination: links.termsURL
                    ) {
                        legalRow(
                            icon: "doc.text",
                            title: "member.terms".localized
                        )
                    }

                    legalDivider

                    Link(
                        destination: links.privacyURL
                    ) {
                        legalRow(
                            icon: "shield",
                            title: "member.privacy".localized
                        )
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("member.legal_unavailable".localized)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.62))
                        Button(L10n.commonRetry) {
                            viewModel.retry()
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                    .padding(.vertical, 8)
                }

                legalDivider

                Button(action: manageSubscription) {
                    legalRow(
                        icon: "person.crop.circle",
                        title: "member.manage_subscription".localized
                    )
                }
            }
            .buttonStyle(.plain)
            .tint(memberGold)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#0B0B0B"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, pageInset)
    }

    private var legalDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.1))
            .padding(.leading, 44)
    }

    private func legalRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(memberGold)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(memberGold)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(memberGold.opacity(0.82))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
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
        let buttonWidth = max(272, availableWidth - pageInset * 2)
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
                .frame(minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#F02E31"),
                                    Color(hex: "#D70F1D")
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.94),
                    Color.black
                ],
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
