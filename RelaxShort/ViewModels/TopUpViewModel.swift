import Foundation

@MainActor
final class TopUpViewModel: ObservableObject {
    @Published private(set) var balance = 0
    @Published private(set) var firstPurchaseBonusAvailable: Bool?
    @Published private(set) var selectedProductID: ProductID?
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchaseErrorMessage: String?
    @Published private(set) var purchaseSucceeded = false

    private let rewardRepository: CoinRewardRepositoryProtocol
    private var userSelectedPackage = false

    init(rewardRepository: CoinRewardRepositoryProtocol) {
        self.rewardRepository = rewardRepository
    }

    func load(packages: [CoinPackage], fallbackBalance: Int) async {
        guard !isLoading else { return }
        isLoading = true
        purchaseErrorMessage = nil
        defer { isLoading = false }

        do {
            apply(
                try await rewardRepository.fetchRewardCenter(),
                packages: packages
            )
        } catch {
            balance = fallbackBalance
            firstPurchaseBonusAvailable = false
            selectDefaultPackage(from: packages)
            #if DEBUG
            Logger.viewModel.warning(
                "TopUpViewModel.load fell back to local balance: \(error.localizedDescription)"
            )
            #endif
        }
    }

    func select(_ package: CoinPackage) {
        userSelectedPackage = true
        selectedProductID = package.productID
        purchaseErrorMessage = nil
        purchaseSucceeded = false
    }

    func selectedPackage(from packages: [CoinPackage]) -> CoinPackage? {
        guard let selectedProductID else { return nil }
        return packages.first { $0.productID == selectedProductID }
    }

    /// 商品刷新后保证默认选中项一定是 StoreKit 实际返回、可以购买的商品。
    func ensureAvailableSelection(
        packages: [CoinPackage],
        isAvailable: (ProductID) -> Bool
    ) {
        if let selectedProductID, isAvailable(selectedProductID) {
            return
        }

        let availablePackages = packages.filter { isAvailable($0.productID) }
        guard !availablePackages.isEmpty else {
            selectedProductID = nil
            return
        }

        userSelectedPackage = false
        if firstPurchaseBonusAvailable == true,
           let firstPurchase = availablePackages.first(where: {
               $0.productID == .coinsSmall
           }) {
            selectedProductID = firstPurchase.productID
        } else {
            selectedProductID = availablePackages.first(where: \.isPopular)?.productID
                ?? availablePackages.first?.productID
        }
    }

    func displayedBonus(for package: CoinPackage) -> Int {
        if package.productID == .coinsSmall,
           firstPurchaseBonusAvailable != true {
            return 0
        }
        return package.bonus ?? 0
    }

    func totalCoins(for package: CoinPackage) -> Int {
        package.amount + displayedBonus(for: package)
    }

    func purchase(
        package: CoinPackage,
        storeKit: StoreKitManager,
        detailRepository: DetailRepositoryProtocol,
        coinStore: CoinStore
    ) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseErrorMessage = nil
        purchaseSucceeded = false
        defer { isPurchasing = false }

        do {
            let token = try await storeKit.resolveAppAccountToken(
                using: {
                    try await detailRepository.fetchAppleAccountToken()
                }
            )
            let receipt = try await storeKit.purchaseCoinPackage(
                package,
                appAccountToken: token
            )

            let verifiedBalance: Int
            if receipt.requiresBackendVerification {
                verifiedBalance = try await detailRepository.verifyCoinPurchase(receipt)
                await storeKit.completeCoinDelivery(receipt)
            } else {
                verifiedBalance = coinStore.coinBalance + totalCoins(for: package)
            }

            coinStore.synchronize(balance: verifiedBalance)
            balance = verifiedBalance
            purchaseSucceeded = true

            if receipt.requiresBackendVerification,
               let refreshed = try? await rewardRepository.fetchRewardCenter() {
                apply(refreshed, packages: storeKit.coinPackages)
            }
        } catch let error as StoreKitPurchaseError {
            purchaseErrorMessage = error.localizedDescription
            #if DEBUG
            Logger.ui.error("TopUp purchase failed: \(error.localizedDescription)")
            #endif
        } catch {
            purchaseErrorMessage = error.localizedDescription
            #if DEBUG
            Logger.ui.error("TopUp verification failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func apply(_ state: RewardCenterState, packages: [CoinPackage]) {
        balance = state.coinBalance
        firstPurchaseBonusAvailable = state.firstCoinPurchaseBonusAvailable
        selectDefaultPackage(from: packages)
    }

    private func selectDefaultPackage(from packages: [CoinPackage]) {
        guard !userSelectedPackage else { return }
        if firstPurchaseBonusAvailable == true,
           let firstPurchase = packages.first(where: { $0.productID == .coinsSmall }) {
            selectedProductID = firstPurchase.productID
            return
        }
        selectedProductID = packages.first(where: \.isPopular)?.productID
            ?? packages.first?.productID
    }
}
