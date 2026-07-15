import SwiftUI

// MARK: - Coin Purchase Sheet

/// 金币购买弹窗 — 从 CoinRewardView 或其他页面触发
///
/// 布局：
/// - 4 个金币包卡片，选中高亮
/// - 底部「立即购买」按钮
/// - 支持 StoreKit 2 真实购买 + Mock 回退
struct CoinPurchaseSheet: View {

    // MARK: - Dependencies

    let coinStore: CoinStore
    let storeKit: StoreKitManager

    // MARK: - Callbacks

    var onDismiss: (() -> Void)?
    /// Series 解锁场景传入：先服务端验单发币，成功后才能展示购买成功。
    var verifyPurchase: ((ApplePurchaseReceipt) async throws -> Int)?
    var onPurchaseCompleted: ((Int) -> Void)?

    // MARK: - State

    @State private var selectedPackage: CoinPackage?
    @State private var isPurchasing: Bool = false
    @State private var purchaseSuccess: Bool = false
    @State private var purchaseErrorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            headerBar

            Divider()
                .background(DT.Color.bgDivider)

            // ── 金币包列表 ──
            ScrollView {
                VStack(spacing: DT.Space.md) {
                    ForEach(storeKit.coinPackages) { package in
                        coinPackageCard(package)
                    }
                }
                .padding(DT.Space.lg)
            }

            // ── 底部购买按钮 ──
            purchaseButton
        }
        .background(DT.Color.bgModal)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous))
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            // 默认选中第二个（最受欢迎）
            if selectedPackage == nil {
                selectedPackage = storeKit.coinPackages.first(where: \.isPopular)
                    ?? storeKit.coinPackages.first
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text(L10n.buyCoins)
                .font(DT.Font.subtitle)
                .foregroundColor(DT.Color.textPrimary)

            Spacer()

            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DT.Font.body(22))
                    .foregroundColor(DT.Color.textTertiary)
            }
        }
        .padding(.horizontal, DT.Space.lg)
        .padding(.vertical, DT.Space.md)
    }

    // MARK: - Coin Package Card

    @ViewBuilder
    private func coinPackageCard(_ package: CoinPackage) -> some View {
        let isSelected = selectedPackage?.id == package.id
        let displayPrice = storeKit.displayPrice(for: package.productID)

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPackage = package
            }
        } label: {
            HStack(spacing: DT.Space.md) {
                // 金币图标
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? DT.brandGold.opacity(0.2)
                                : DT.Color.textPrimary.opacity(0.06)
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(DT.Font.body(24))
                        .foregroundColor(isSelected ? DT.brandGold : DT.Color.textSecondary)
                }

                // 金币量 + 标签
                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    HStack(spacing: DT.Space.xs) {
                        Text("\(package.amount)")
                            .font(DT.Font.body(18, weight: .bold))
                            .foregroundColor(
                                isSelected ? DT.Color.textPrimary : DT.Color.textPrimary.opacity(0.8)
                            )
                        Text(L10n.coinsUnit)
                            .font(DT.Font.caption)
                            .foregroundColor(DT.Color.textSecondary)

                        if let label = package.label {
                            Text(label)
                                .font(DT.Font.tabLabel)
                                .foregroundColor(DT.brandGold)
                                .padding(.horizontal, DT.Space.sm)
                                .padding(.vertical, 2)
                                .background(DT.brandGold.opacity(0.12))
                                .cornerRadius(DT.Radius.sm)
                        }
                    }

                    if let bonus = package.bonus, bonus > 0 {
                        Text(L10n.bonusCoins(bonus))
                            .font(DT.Font.small)
                            .foregroundColor(DT.Color.textTertiary)
                    }
                }

                Spacer()

                // 价格（优先显示 App Store 真实价格）
                VStack(alignment: .trailing, spacing: 2) {
                    Text(displayPrice)
                        .font(DT.Font.body(18, weight: .bold))
                        .foregroundColor(
                            isSelected ? DT.brandPink : DT.Color.textPrimary
                        )
                }

                // 选中标记
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DT.Font.body(20))
                        .foregroundColor(DT.brandPink)
                }
            }
            .padding(DT.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.lg)
                    .fill(isSelected
                        ? DT.Color.textPrimary.opacity(0.04)
                        : DT.Color.textPrimary.opacity(0.02)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.lg)
                    .stroke(
                        isSelected ? DT.brandPink : DT.Color.textPrimary.opacity(0.06),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        VStack(spacing: DT.Space.sm) {
            if let errorMsg = purchaseErrorMessage {
                // 购买失败提示
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(DT.hotTag)
                    Text(errorMsg)
                        .font(DT.Font.body(13, weight: .medium))
                        .foregroundColor(DT.hotTag)
                }
                .padding(.vertical, DT.Space.md)
            }

            if purchaseSuccess {
                // 购买成功提示
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DT.success)
                    Text(L10n.purchaseSuccess)
                        .font(DT.Font.body(15, weight: .medium))
                        .foregroundColor(DT.Color.textPrimary)
                }
                .padding(.vertical, DT.Space.md)
            }

            Button {
                performPurchase()
            } label: {
                HStack(spacing: DT.Space.sm) {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: DT.Color.textPrimary))
                            .scaleEffect(0.8)
                    }
                    Text(isPurchasing ? L10n.purchasing : L10n.buyNow)
                        .font(DT.Font.body(16, weight: .bold))
                }
                .foregroundColor(DT.Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: DT.Layout.ctaButtonHeight)
                .background(
                    (isPurchasing || selectedPackage == nil)
                        ? DT.brandPink.opacity(0.5)
                        : DT.brandPink
                )
                .cornerRadius(DT.Radius.md)
            }
            .disabled(isPurchasing || selectedPackage == nil)
            .padding(.horizontal, DT.Space.lg)

            // 合规声明
            Text(L10n.appleDisclaimer)
                .font(DT.Font.tabLabel)
                .foregroundColor(DT.Color.textPrimary.opacity(0.25))
                .padding(.top, DT.Space.xs)
                .padding(.bottom, DT.Space.lg)
        }
        .padding(.top, DT.Space.sm)
    }

    // MARK: - Purchase Logic

    private func performPurchase() {
        guard let pkg = selectedPackage, !isPurchasing else { return }
        isPurchasing = true
        purchaseErrorMessage = nil

        Task {
            do {
                let receipt = try await storeKit.purchaseCoinPackage(pkg)
                let verifiedBalance: Int
                if let verifyPurchase {
                    verifiedBalance = try await verifyPurchase(receipt)
                } else {
                    verifiedBalance = coinStore.coinBalance + receipt.coins
                }
                await MainActor.run {
                    coinStore.synchronize(balance: verifiedBalance)
                    onPurchaseCompleted?(verifiedBalance)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPurchasing = false
                        purchaseSuccess = true
                    }
                    // 1.5s 后自动关闭
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run { onDismiss?() }
                    }
                }
            } catch let error as StoreKitPurchaseError {
                await MainActor.run {
                    isPurchasing = false
                    purchaseErrorMessage = error.localizedDescription
                    #if DEBUG
                    Logger.ui.error("CoinPurchaseSheet: purchase failed — \(error.localizedDescription)")
                    #endif
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    purchaseErrorMessage = error.localizedDescription
                    #if DEBUG
                    Logger.ui.error("CoinPurchaseSheet: purchase failed — \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }
}

// MARK: - Episode Unlock Purchase Center

enum EpisodeUnlockPurchaseTab: String, CaseIterable {
    case coins = "金币充值"
    case vip = "VIP 会员"
}

/// 锁集专用购买中心。金币和 VIP 分页展示，购买成功必须经过服务端验单后才通知播放器。
struct EpisodeUnlockPurchaseSheet: View {
    let coinStore: CoinStore
    let storeKit: StoreKitManager
    let coinCost: Int
    let balance: Int
    let safeAreaBottom: CGFloat
    let onDismiss: () -> Void
    let verifyCoinPurchase: (ApplePurchaseReceipt) async throws -> Int
    let verifyVIPPurchase: (ApplePurchaseReceipt) async throws -> EpisodeUnlockAccount
    let refreshAccount: () async throws -> EpisodeUnlockAccount
    let onCoinPurchaseCompleted: (Int) -> Void
    let onVIPPurchaseCompleted: (EpisodeUnlockAccount) -> Void

    @State private var selectedTab: EpisodeUnlockPurchaseTab
    @State private var selectedPackage: CoinPackage?
    @State private var selectedSubscription: VIPSubscription?
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    private let gold = Color(red: 1.0, green: 0.76, blue: 0.22)
    private let paleGold = Color(red: 1.0, green: 0.90, blue: 0.62)
    private let panel = Color(red: 0.075, green: 0.068, blue: 0.058)

    init(
        coinStore: CoinStore,
        storeKit: StoreKitManager,
        coinCost: Int,
        balance: Int,
        initialTab: EpisodeUnlockPurchaseTab,
        safeAreaBottom: CGFloat,
        onDismiss: @escaping () -> Void,
        verifyCoinPurchase: @escaping (ApplePurchaseReceipt) async throws -> Int,
        verifyVIPPurchase: @escaping (ApplePurchaseReceipt) async throws -> EpisodeUnlockAccount,
        refreshAccount: @escaping () async throws -> EpisodeUnlockAccount,
        onCoinPurchaseCompleted: @escaping (Int) -> Void,
        onVIPPurchaseCompleted: @escaping (EpisodeUnlockAccount) -> Void
    ) {
        self.coinStore = coinStore
        self.storeKit = storeKit
        self.coinCost = coinCost
        self.balance = balance
        self.safeAreaBottom = safeAreaBottom
        self.onDismiss = onDismiss
        self.verifyCoinPurchase = verifyCoinPurchase
        self.verifyVIPPurchase = verifyVIPPurchase
        self.refreshAccount = refreshAccount
        self.onCoinPurchaseCompleted = onCoinPurchaseCompleted
        self.onVIPPurchaseCompleted = onVIPPurchaseCompleted
        _selectedTab = State(initialValue: initialTab)

        let shortfall = max(0, coinCost - balance)
        let package = storeKit.coinPackages.first {
            $0.amount + ($0.bonus ?? 0) >= shortfall
        } ?? storeKit.coinPackages.last
        _selectedPackage = State(initialValue: package)
        _selectedSubscription = State(
            initialValue: storeKit.vipSubscriptions.first(where: { $0.productID == .vipMonthly })
                ?? storeKit.vipSubscriptions.first
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            ScrollView(showsIndicators: false) {
                Group {
                    if selectedTab == .coins { coinContent }
                    else { vipContent }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            purchaseFooter
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.10, blue: 0.075), panel, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [gold.opacity(0.72), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            if selectedTab == .coins {
                coinMetadata
            } else {
                Text("VIP 全剧畅看")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(paleGold)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(EpisodeUnlockPurchaseTab.allCases, id: \.self) { tab in
                Button {
                    errorMessage = nil
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 10) {
                        Text(tab.rawValue)
                            .font(.system(size: 15, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? paleGold : .white.opacity(0.42))
                        Capsule()
                            .fill(selectedTab == tab ? gold : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.08)) }
    }

    private var coinMetadata: some View {
        HStack(spacing: 13) {
            metadataItem(label: "本集：", value: coinCost)
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 18)
            metadataItem(label: "余额：", value: balance)
        }
    }

    private func metadataItem(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Image(systemName: "bitcoinsign.circle.fill")
                .foregroundStyle(gold)
            Text("\(value)")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white.opacity(0.86))
    }

    private var coinContent: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(storeKit.coinPackages) { package in
                let selected = selectedPackage?.id == package.id
                Button {
                    selectedPackage = package
                    errorMessage = nil
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "bitcoinsign.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(gold)
                            Text("\(package.amount)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                            if let bonus = package.bonus, bonus > 0 {
                                Text("+\(bonus)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(gold)
                            }
                        }
                        Text(storeKit.displayPrice(for: package.productID))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(selected ? gold.opacity(0.12) : .white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selected ? gold : .white.opacity(0.09), lineWidth: selected ? 1.6 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var vipContent: some View {
        VStack(spacing: 12) {
            ForEach(vipPlans) { plan in
                let selected = selectedSubscription?.id == plan.id
                Button {
                    selectedSubscription = plan
                    errorMessage = nil
                } label: {
                    HStack(spacing: 15) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text("\(plan.period)卡")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                if plan.productID == .vipMonthly {
                                    Text("推荐")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(gold, in: Capsule())
                                }
                            }
                            Text(plan.dailyEquivalent)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        Text(storeKit.displayPrice(for: plan.productID))
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(selected ? paleGold : .white.opacity(0.8))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 78)
                    .background(selected ? gold.opacity(0.12) : .white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selected ? gold : .white.opacity(0.09), lineWidth: selected ? 1.6 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            HStack(spacing: 20) {
                Label("无限观看", systemImage: "infinity")
                Label("高清画质", systemImage: "4k.tv")
                Label("离线下载", systemImage: "arrow.down.circle")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(paleGold.opacity(0.72))
            .padding(.top, 6)
        }
    }

    private var vipPlans: [VIPSubscription] {
        storeKit.vipSubscriptions.filter { $0.productID != .vipQuarterly }
    }

    private var purchaseFooter: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.36))
            }

            Button(action: performPurchase) {
                HStack(spacing: 8) {
                    if isPurchasing { ProgressView().tint(.black) }
                    Text(purchaseButtonTitle)
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(colors: [Color.white, paleGold, gold], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .shadow(color: gold.opacity(0.22), radius: 18, y: 7)
            }
            .disabled(isPurchasing || (selectedTab == .coins ? selectedPackage == nil : selectedSubscription == nil))

            Text(selectedTab == .coins
                 ? "购买成功后将自动使用 \(coinCost) 金币解锁本集"
                 : "订阅将自动续订，可随时在 App Store 账户设置中取消")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))

            if selectedTab == .vip {
                Button(action: restorePurchase) {
                    Text("恢复购买  ·  使用条款  ·  隐私政策")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .disabled(isPurchasing)
            } else {
                Text("由 App Store 安全支付")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, max(14, safeAreaBottom + 12))
        .background(.black.opacity(0.32))
    }

    private var purchaseButtonTitle: String {
        if selectedTab == .coins, let selectedPackage {
            return "购买 \(selectedPackage.amount) 金币并解锁"
        }
        if let selectedSubscription { return "开通\(selectedSubscription.period) VIP 并解锁" }
        return "继续"
    }

    private func performPurchase() {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                if selectedTab == .coins, let package = selectedPackage {
                    let receipt = try await storeKit.purchaseCoinPackage(package)
                    let verifiedBalance = try await verifyCoinPurchase(receipt)
                    await MainActor.run {
                        coinStore.synchronize(balance: verifiedBalance)
                        isPurchasing = false
                        onCoinPurchaseCompleted(verifiedBalance)
                    }
                } else if let subscription = selectedSubscription {
                    let receipt = try await storeKit.purchaseVIP(subscription)
                    let account = try await verifyVIPPurchase(receipt)
                    await MainActor.run {
                        coinStore.synchronize(balance: account.balance)
                        isPurchasing = false
                        onVIPPurchaseCompleted(account)
                    }
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func restorePurchase() {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        Task {
            do {
                try await storeKit.restorePurchases()
                let account = try await refreshAccount()
                guard account.isVIP else {
                    throw APIError(code: "VIP_NOT_ACTIVE", message: "未发现可恢复的会员权益")
                }
                await MainActor.run {
                    coinStore.synchronize(balance: account.balance)
                    isPurchasing = false
                    onVIPPurchaseCompleted(account)
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CoinPurchaseSheet") {
    ZStack {
        DT.Color.bgPrimary.ignoresSafeArea()
        VStack {
            Spacer()
            CoinPurchaseSheet(
                coinStore: CoinStore(),
                storeKit: StoreKitManager(),
                onDismiss: {}
            )
            .frame(height: 520)
        }
    }
    .preferredColorScheme(.dark)
}
#endif
