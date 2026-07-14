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
