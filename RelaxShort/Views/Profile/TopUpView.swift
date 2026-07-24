import SwiftUI

/// 紧凑金币充值页：真实首充状态、StoreKit 价格、购买和服务端验单。
struct TopUpView: View {
    @EnvironmentObject private var coinStore: CoinStore
    @EnvironmentObject private var storeKitManager: StoreKitManager
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: TopUpViewModel

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
                CompactProfileNavigationHeader(title: "topup.title".localized)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                balanceHero
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                if viewModel.firstPurchaseBonusAvailable == true {
                    firstPurchaseStrip
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                } else {
                    marketingHeadline
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }

                packageList
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                purchaseButton
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                trustNotice
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 26)
            }
        }
        .background(DB.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
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
                .frame(height: 132)
                .opacity(0.78)
                .clipped()

            Image("TopUpCoinStackLarge")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 88)
                .offset(x: 4)

            VStack(alignment: .leading, spacing: 9) {
                Text("topup.balance".localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DB.mutedText)

                HStack(spacing: 10) {
                    Image("RewardCoinIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)

                    Text(viewModel.balance.formatted(.number.grouping(.automatic)))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .frame(height: 132)
        .background(Color(hex: "#080605"))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(DT.brandGold.opacity(0.46), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("wallet.balance_accessibility".localizedFormat(viewModel.balance))
    }

    private var marketingHeadline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("topup.headline".localized)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
            Text("topup.subtitle".localized)
                .font(.system(size: 13))
                .foregroundColor(DB.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstPurchaseStrip: some View {
        let package = storeKitManager.coinPackages.first {
            $0.productID == .coinsSmall
        }
        let price = package.map {
            storeKitManager.displayPrice(for: $0.productID)
        } ?? ""
        let total = package.map(viewModel.totalCoins) ?? 0

        return HStack(spacing: 10) {
            Text("topup.first_top_up_badge".localized)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DT.logoRed)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(DT.logoRed, lineWidth: 0.8)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("topup.first_bonus_title".localized)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DT.coinGold)
                    .lineLimit(1)

                Text("topup.first_bonus_subtitle".localizedFormat(total, price))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(DB.panel.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var packageList: some View {
        LazyVStack(spacing: 10) {
            ForEach(storeKitManager.coinPackages) { package in
                packageRow(package)
            }
        }
    }

    private func packageRow(_ package: CoinPackage) -> some View {
        let selected = viewModel.selectedProductID == package.productID
        let bonus = viewModel.displayedBonus(for: package)
        let total = viewModel.totalCoins(for: package)
        let price = storeKitManager.displayPrice(for: package.productID)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.select(package)
            }
        } label: {
            HStack(spacing: 12) {
                Image(artworkName(for: package))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(package.amount.formatted(.number.grouping(.automatic)))
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.75)
                        Text("topup.coins".localized)
                            .font(.system(size: 11))
                            .foregroundColor(DB.mutedText)
                    }
                    .foregroundColor(.white)

                    if bonus > 0 {
                        Text("topup.bonus".localizedFormat(bonus))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DT.coinGold)
                            .lineLimit(1)
                    } else {
                        Text("topup.total_get".localized)
                            .font(.system(size: 11))
                            .foregroundColor(DB.mutedText)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(price)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundColor(selected ? DT.logoRed : DB.mutedText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 88)
            .background(DB.black)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        selected ? DT.logoRed : DB.divider,
                        lineWidth: selected ? 1.2 : 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "topup.package_accessibility".localizedFormat(total, price)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var purchaseButton: some View {
        VStack(spacing: 9) {
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
                HStack(spacing: 9) {
                    if viewModel.isPurchasing {
                        ProgressView().tint(.white)
                    }
                    Text(purchaseButtonTitle)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(DT.logoRed)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .disabled(selectedPackage == nil || viewModel.isPurchasing)
            .opacity(selectedPackage == nil ? 0.55 : 1)
        }
    }

    private var trustNotice: some View {
        VStack(spacing: 4) {
            Label("topup.secure_purchase".localized, systemImage: "lock.shield")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DB.mutedText)
            Text("topup.one_time_purchase".localized)
                .font(.system(size: 10))
                .foregroundColor(DB.mutedText)
            Text("topup.apple_charge".localized)
                .font(.system(size: 9))
                .foregroundColor(DB.mutedText.opacity(0.78))
                .multilineTextAlignment(.center)
        }
    }

    private var selectedPackage: CoinPackage? {
        viewModel.selectedPackage(from: storeKitManager.coinPackages)
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
}
