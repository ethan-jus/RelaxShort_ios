import SwiftUI

/// 强营销金币充值页：真实首充状态、StoreKit 价格、购买和服务端验单。
struct TopUpView: View {
    @EnvironmentObject private var coinStore: CoinStore
    @EnvironmentObject private var storeKitManager: StoreKitManager
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: TopUpViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(
        rewardRepository: CoinRewardRepositoryProtocol = RealCoinRewardRepository()
    ) {
        _viewModel = StateObject(
            wrappedValue: TopUpViewModel(rewardRepository: rewardRepository)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                balanceHero
                marketingHeadline
                    .padding(.top, 10)

                if viewModel.firstPurchaseBonusAvailable == true {
                    firstPurchaseBanner
                        .padding(.top, 18)
                }

                packageGrid
                    .padding(.top, 18)

                purchaseSummary
                    .padding(.top, 18)

                purchaseButton
                    .padding(.top, 12)

                trustNotice
                    .padding(.top, 14)
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 20)
        }
        .background(DB.black.ignoresSafeArea())
        .navigationTitle("topup.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DB.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.load(
                packages: storeKitManager.coinPackages,
                fallbackBalance: coinStore.coinBalance
            )
        }
    }

    private var balanceHero: some View {
        ZStack(alignment: .trailing) {
            Image("ProfileRedLight")
                .resizable()
                .scaledToFill()
                .frame(height: 148)
                .opacity(0.82)
                .clipped()

            Image("TopUpCoinStackLarge")
                .resizable()
                .scaledToFit()
                .frame(width: 168, height: 118)
                .offset(x: 8, y: 2)

            HStack(spacing: 12) {
                Image("RewardCoinIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 2) {
                    Text("topup.balance".localized)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DB.mutedText)
                    Text(viewModel.balance.formatted(.number.grouping(.automatic)))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 148)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DB.divider)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("wallet.balance_accessibility".localizedFormat(viewModel.balance))
    }

    private var marketingHeadline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("topup.headline".localized)
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(.white)
            Text("topup.subtitle".localized)
                .font(.system(size: 14))
                .foregroundColor(DB.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstPurchaseBanner: some View {
        let package = storeKitManager.coinPackages.first {
            $0.productID == .coinsSmall
        }
        let price = package.map {
            storeKitManager.displayPrice(for: $0.productID)
        } ?? ""
        let total = package.map(viewModel.totalCoins) ?? 0

        return ZStack(alignment: .trailing) {
            Image("ProfileRedLight")
                .resizable()
                .scaledToFill()
                .opacity(0.76)
                .clipped()

            Image("TopUpCoinPileMedium")
                .resizable()
                .scaledToFit()
                .frame(width: 146, height: 96)
                .offset(x: 8)

            VStack(alignment: .leading, spacing: 5) {
                Text("topup.first_bonus_badge".localized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(DT.logoRed)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text("topup.first_bonus_title".localized)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DT.coinGold)

                Text("topup.first_bonus_subtitle".localizedFormat(total, price))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.trailing, 136)
        }
        .frame(height: 116)
        .background(Color(hex: "#170706"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(DT.brandGold.opacity(0.72), lineWidth: 1)
        }
    }

    private var packageGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(storeKitManager.coinPackages) { package in
                packageCard(package)
            }
        }
    }

    private func packageCard(_ package: CoinPackage) -> some View {
        let selected = viewModel.selectedProductID == package.productID
        let bonus = viewModel.displayedBonus(for: package)
        let total = viewModel.totalCoins(for: package)
        let price = storeKitManager.displayPrice(for: package.productID)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.select(package)
            }
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 4) {
                        Image(artworkName(for: package))
                            .resizable()
                            .scaledToFit()
                            .frame(height: 74)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(package.amount.formatted(.number.grouping(.automatic)))
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.75)
                            Text("topup.coins".localized)
                                .font(.system(size: 12))
                                .foregroundColor(DB.mutedText)
                        }
                        .foregroundColor(.white)

                        if bonus > 0 {
                            Text("topup.bonus".localizedFormat(bonus))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DT.coinGold)
                        } else {
                            Color.clear.frame(height: 15)
                        }

                        Divider()
                            .overlay(DB.divider)
                            .padding(.horizontal, 10)
                            .padding(.top, 5)

                        Text("topup.total_get".localized)
                            .font(.system(size: 11))
                            .foregroundColor(DB.mutedText)
                            .padding(.top, 3)

                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(total.formatted(.number.grouping(.automatic)))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("topup.coins".localized)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(DT.coinGold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.top, 26)
                    .padding(.bottom, 10)

                    if let badge = badgeTitle(for: package) {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(DT.logoRed)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }

                HStack {
                    Spacer()
                    Text(price)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.trailing, 8)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: 48)
                .background(selected ? DT.logoRed : DB.panel)
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        selected ? DT.logoRed : DB.divider,
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .shadow(color: selected ? DT.logoRed.opacity(0.38) : .clear, radius: 9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "topup.package_accessibility".localizedFormat(total, price)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var purchaseSummary: some View {
        HStack(spacing: 12) {
            Image("RewardCoinIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            Text("topup.you_receive".localized)
                .font(.system(size: 14))
                .foregroundColor(DB.mutedText)

            Spacer()

            Text(selectedTotal.formatted(.number.grouping(.automatic)))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(DT.coinGold)
                .monospacedDigit()
            Text("topup.coins".localized)
                .font(.system(size: 12))
                .foregroundColor(DT.coinGold)
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(DB.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(DB.divider, lineWidth: 1)
        }
    }

    private var purchaseButton: some View {
        VStack(spacing: 10) {
            if let error = viewModel.purchaseErrorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DT.logoRed)
                    .multilineTextAlignment(.center)
            } else if viewModel.purchaseSucceeded {
                Label("topup.purchase_success".localized, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DT.coinGold)
            }

            Button {
                guard let package = selectedPackage else { return }
                Task {
                    await viewModel.purchase(
                        package: package,
                        storeKit: storeKitManager,
                        detailRepository: dependencies.detailRepository,
                        coinStore: coinStore
                    )
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isPurchasing {
                        ProgressView().tint(.white)
                    }
                    Text(purchaseButtonTitle)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(DT.logoRed)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(selectedPackage == nil || viewModel.isPurchasing)
            .opacity(selectedPackage == nil ? 0.55 : 1)
        }
    }

    private var trustNotice: some View {
        VStack(spacing: 5) {
            Label("topup.secure_purchase".localized, systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DB.mutedText)
            Text("topup.one_time_purchase".localized)
                .font(.system(size: 11))
                .foregroundColor(DB.mutedText)
            Text("topup.apple_charge".localized)
                .font(.system(size: 10))
                .foregroundColor(DB.mutedText.opacity(0.78))
                .multilineTextAlignment(.center)
        }
    }

    private var selectedPackage: CoinPackage? {
        viewModel.selectedPackage(from: storeKitManager.coinPackages)
    }

    private var selectedTotal: Int {
        selectedPackage.map(viewModel.totalCoins) ?? 0
    }

    private var purchaseButtonTitle: String {
        guard let package = selectedPackage else {
            return "topup.select_package".localized
        }
        return "topup.purchase_cta".localizedFormat(
            viewModel.totalCoins(for: package),
            storeKitManager.displayPrice(for: package.productID)
        )
    }

    private func artworkName(for package: CoinPackage) -> String {
        switch package.productID {
        case .coinsSmall, .coinsMedium: return "TopUpCoinPileSmall"
        case .coinsLarge: return "TopUpCoinPileMedium"
        case .coinsXLarge: return "TopUpCoinStackLarge"
        default: return "RewardCoinIcon"
        }
    }

    private func badgeTitle(for package: CoinPackage) -> String? {
        switch package.productID {
        case .coinsSmall where viewModel.firstPurchaseBonusAvailable == true:
            return "topup.first_top_up_badge".localized
        case .coinsLarge:
            return "store.most_popular".localized
        case .coinsXLarge:
            return "store.best_value".localized
        default:
            return nil
        }
    }
}
