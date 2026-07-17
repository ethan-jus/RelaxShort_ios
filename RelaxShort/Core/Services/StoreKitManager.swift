import StoreKit
import SwiftUI

// MARK: - Product ID

/// StoreKit 产品标识符枚举
/// 映射到 App Store Connect 中配置的 Product ID
enum ProductID: String, CaseIterable {
    // 金币包
    case coinsSmall  = "com.relaxshort.coins.small"
    case coinsMedium = "com.relaxshort.coins.medium"
    case coinsLarge  = "com.relaxshort.coins.large"
    case coinsXLarge = "com.relaxshort.coins.xlarge"

    // VIP 订阅
    case vipWeekly    = "com.relaxshort.vip.weekly"
    case vipMonthly   = "com.relaxshort.vip.monthly"
    case vipQuarterly = "com.relaxshort.vip.quarterly"
    case vipYearly    = "com.relaxshort.vip.yearly"

    /// 当前 RelaxShort 对外销售的 VIP 套餐。季度套餐保留旧标识，但不进入购买界面。
    static let supportedVIPSubscriptions: [ProductID] = [
        .vipWeekly,
        .vipMonthly,
        .vipYearly
    ]

    /// 是否为金币包
    var isCoinPackage: Bool {
        switch self {
        case .coinsSmall, .coinsMedium, .coinsLarge, .coinsXLarge: return true
        default: return false
        }
    }

    /// 是否为 VIP 订阅
    var isVIPSubscription: Bool {
        switch self {
        case .vipWeekly, .vipMonthly, .vipQuarterly, .vipYearly: return true
        default: return false
        }
    }

    /// 对应的金币数量（仅金币包有效）
    var coinAmount: Int {
        switch self {
        case .coinsSmall:  return 300
        case .coinsMedium: return 700
        case .coinsLarge:  return 1500
        case .coinsXLarge: return 4000
        default: return 0
        }
    }
}

// MARK: - Coin Package

/// 金币包模型
struct CoinPackage: Identifiable, Equatable {
    let id: String
    let productID: ProductID
    let amount: Int
    let price: String
    let bonus: Int?
    let isPopular: Bool

    /// 显示标签（如 "最受欢迎"）
    var label: String? {
        if isPopular { return "最受欢迎" }
        if let bonus, bonus > 0 { return "加赠\(bonus)金币" }
        return nil
    }

    /// 当前显示价格：优先使用 StoreKit displayPrice，否则使用 fallback price
    var displayPrice: String { price }
}

// MARK: - VIP Subscription

/// VIP 订阅模型
struct VIPSubscription: Identifiable, Equatable {
    let id: String
    let productID: ProductID
    let period: String          // "周" / "月" / "季" / "年"
    let price: String
    let dailyEquivalent: String // "¥1.86/天"
}

// MARK: - StoreKit Purchase Error

/// StoreKit 购买错误
enum StoreKitPurchaseError: Error, LocalizedError {
    case userCancelled
    case pending
    case unverified
    case productUnavailable(ProductID)
    case noActiveSubscription
    case unknown

    var errorDescription: String? {
        switch self {
        case .userCancelled: return "用户取消购买"
        case .pending:       return "购买等待处理中"
        case .unverified:    return "交易验证失败"
        case .productUnavailable(let productID):
            return "App Store 商品暂不可用：\(productID.rawValue)"
        case .noActiveSubscription:
            return "未发现可恢复的有效会员订阅"
        case .unknown:       return "未知错误"
        }
    }
}

// MARK: - VIP Purchase State

struct VIPPurchaseState: Equatable {
    enum Phase: Equatable {
        case idle
        case purchasing(ProductID)
        case pending(ProductID)
        case awaitingServerVerification(ProductID)
        case active(ProductID)
        case serverActive(ProductID?)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    var isPurchasing: Bool {
        if case .purchasing = phase { return true }
        return false
    }

    var activeProductID: ProductID? {
        if case .active(let productID) = phase { return productID }
        if case .serverActive(let productID) = phase { return productID }
        return nil
    }

    var hasActiveSubscription: Bool {
        switch phase {
        case .active, .serverActive: return true
        default: return false
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    mutating func begin(productID: ProductID) {
        phase = .purchasing(productID)
    }

    mutating func activate(productID: ProductID) {
        phase = .active(productID)
    }

    mutating func markPending(productID: ProductID) {
        phase = .pending(productID)
    }

    mutating func awaitServerVerification(productID: ProductID) {
        phase = .awaitingServerVerification(productID)
    }

    mutating func activateFromServer(productID: ProductID? = nil) {
        phase = .serverActive(productID)
    }

    mutating func cancel() {
        phase = .idle
    }

    mutating func fail(message: String) {
        phase = .failed(message)
    }
}

// MARK: - StoreKit Manager

/// 内购管理器 — 使用 StoreKit 2 API
///
/// VIP 与金币包都必须使用 StoreKit 2 已加载商品；真实 Apple 交易由后端验单后才发放权益。
///
/// 用法：
/// ```swift
/// @EnvironmentObject var storeKit: StoreKitManager
/// let receipt = try await storeKit.purchaseCoinPackage(pkg, appAccountToken: token)
/// let receipts = try await storeKit.restoreVIPPurchases(appAccountToken: token)
/// ```
@MainActor
final class StoreKitManager: ObservableObject {

    private static let localTestingAccountToken = UUID(
        uuidString: "A37A0001-0000-4000-8000-000000000001"
    )!

    // MARK: - Published State

    @Published var isPurchasing: Bool = false
    @Published var purchaseError: String?
    /// StoreKit 产品是否已加载（从 App Store 成功获取）
    @Published var isStoreKitReady: Bool = false
    @Published private(set) var vipPurchaseState = VIPPurchaseState()

    // MARK: - Private State

    /// 从 App Store 获取的真实 Product 对象，key 为 productID rawValue
    private var storeKitProducts: [String: Product] = [:]

    /// Transaction 监听任务
    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Fallback Product Data

    /// 金币包列表（本地回退数据）
    let coinPackages: [CoinPackage] = [
        CoinPackage(id: "pack_300",  productID: .coinsSmall,  amount: 300,  price: "$4.99",  bonus: nil,   isPopular: false),
        CoinPackage(id: "pack_700",  productID: .coinsMedium, amount: 700,  price: "$9.99",  bonus: 50,    isPopular: true),
        CoinPackage(id: "pack_1500", productID: .coinsLarge,  amount: 1500, price: "$19.99", bonus: 150,   isPopular: false),
        CoinPackage(id: "pack_4000", productID: .coinsXLarge, amount: 4000, price: "$49.99", bonus: 500,   isPopular: false),
    ]

    /// VIP 订阅列表。价格优先使用 StoreKit 本地化价格。
    var vipSubscriptions: [VIPSubscription] {
        [
            VIPSubscription(id: "vip_weekly",  productID: .vipWeekly,  period: "周", price: displayPrice(for: .vipWeekly),  dailyEquivalent: "$1.86/天"),
            VIPSubscription(id: "vip_monthly", productID: .vipMonthly, period: "月", price: displayPrice(for: .vipMonthly), dailyEquivalent: "$1.00/天"),
            VIPSubscription(id: "vip_yearly",  productID: .vipYearly,  period: "年", price: displayPrice(for: .vipYearly),  dailyEquivalent: "$0.41/天")
        ]
    }

    // MARK: - Init

    init() {
        guard !AppRuntimeEnvironment.isUnitTesting else { return }
        startTransactionListener()
        Task {
            await requestProducts()
            await refreshVIPEntitlements()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Public API — Display Price

    /// Xcode StoreKit Configuration 不依赖后端；真实商店环境必须取得服务端用户令牌。
    func resolveAppAccountToken(
        using fetchFromServer: () async throws -> UUID
    ) async throws -> UUID {
        if let result = try? await StoreKit.AppTransaction.shared,
           case .verified(let appTransaction) = result,
           appTransaction.environment == .xcode {
            return Self.localTestingAccountToken
        }
        return try await fetchFromServer()
    }

    /// 获取产品显示价格
    /// - 优先返回 App Store 真实价格（含本地化货币符号）
    /// - 回退到本地定义的 fallback 价格
    func displayPrice(for productID: ProductID) -> String {
        storeKitProducts[productID.rawValue]?.displayPrice
            ?? fallbackPrice(for: productID)
    }

    // MARK: - Public API — Request Products

    /// 从 App Store 获取产品信息
    ///
    /// 成功时将产品缓存到 `storeKitProducts`，
    /// 失败时清空缓存、回退到 mock 模式。
    func requestProducts() async {
        do {
            let allIDs = ProductID.allCases.map(\.rawValue)
            let products = try await Product.products(for: Set(allIDs))
            storeKitProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            isStoreKitReady = ProductID.supportedVIPSubscriptions.allSatisfy {
                storeKitProducts[$0.rawValue] != nil
            }
            Logger.store.info("StoreKitManager: loaded \(self.storeKitProducts.count) products from App Store")
        } catch {
            Logger.store.warning("StoreKitManager: product request failed — \(error.localizedDescription)")
            storeKitProducts = [:]
            isStoreKitReady = false
        }
    }

    // MARK: - Public API — Purchase Coin Package

    /// 购买金币包
    /// - Parameter package: 要购买的金币包
    /// - Returns: 购买成功后的 Apple 交易凭证；必须交给服务端验单后才能发币。
    /// - Throws: `StoreKitPurchaseError` 或 StoreKit 原生错误
    func purchaseCoinPackage(
        _ package: CoinPackage,
        appAccountToken: UUID
    ) async throws -> ApplePurchaseReceipt {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        let totalCoins = package.amount + (package.bonus ?? 0)

        // ── StoreKit 2 真实购买 ──
        if let product = storeKitProducts[package.productID.rawValue] {
            let result = try await product.purchase(options: [
                .appAccountToken(appAccountToken)
            ])
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let receipt = purchaseReceipt(from: transaction, coins: totalCoins)
                if !receipt.requiresBackendVerification {
                    await transaction.finish()
                }
                Logger.store.info("StoreKit: purchased \(product.id) → \(totalCoins) coins")
                return receipt

            case .userCancelled:
                Logger.store.info("StoreKit: user cancelled purchase")
                throw StoreKitPurchaseError.userCancelled

            case .pending:
                Logger.store.info("StoreKit: purchase pending")
                throw StoreKitPurchaseError.pending

            @unknown default:
                throw StoreKitPurchaseError.unknown
            }
        }

        let error = StoreKitPurchaseError.productUnavailable(package.productID)
        purchaseError = error.localizedDescription
        throw error
    }

    // MARK: - Public API — Purchase VIP

    /// 购买 VIP 订阅
    /// - Parameters:
    ///   - subscription: 要购买的订阅
    ///   - appAccountToken: 后端为当前登录用户签发的稳定交易归属 UUID
    /// - Returns: 购买成功后的 Apple 交易凭证；必须由服务端验单后才能授予 VIP。
    /// - Throws: `StoreKitPurchaseError` 或 StoreKit 原生错误
    func purchaseVIP(
        _ subscription: VIPSubscription,
        appAccountToken: UUID
    ) async throws -> ApplePurchaseReceipt {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        vipPurchaseState.begin(productID: subscription.productID)

        // ── StoreKit 2 真实购买 ──
        if let product = storeKitProducts[subscription.productID.rawValue] {
            do {
                let result = try await product.purchase(options: [
                    .appAccountToken(appAccountToken)
                ])
                switch result {
                case .success(let verification):
                    let transaction = try checkVerified(verification)
                    let receipt = purchaseReceipt(from: transaction, coins: 0)
                    if receipt.requiresBackendVerification {
                        vipPurchaseState.awaitServerVerification(productID: subscription.productID)
                    } else {
                        await transaction.finish()
                        vipPurchaseState.activate(productID: subscription.productID)
                    }
                    Logger.store.info("StoreKit: purchased VIP \(product.id)")
                    return receipt

                case .userCancelled:
                    Logger.store.info("StoreKit: user cancelled VIP purchase")
                    vipPurchaseState.cancel()
                    throw StoreKitPurchaseError.userCancelled

                case .pending:
                    Logger.store.info("StoreKit: VIP purchase pending")
                    vipPurchaseState.markPending(productID: subscription.productID)
                    throw StoreKitPurchaseError.pending

                @unknown default:
                    throw StoreKitPurchaseError.unknown
                }
            } catch let error as StoreKitPurchaseError {
                switch error {
                case .userCancelled, .pending:
                    break
                default:
                    vipPurchaseState.fail(message: error.localizedDescription)
                    purchaseError = error.localizedDescription
                }
                throw error
            } catch {
                vipPurchaseState.fail(message: error.localizedDescription)
                purchaseError = error.localizedDescription
                throw error
            }
        }

        let error = StoreKitPurchaseError.productUnavailable(subscription.productID)
        vipPurchaseState.fail(message: error.localizedDescription)
        purchaseError = error.localizedDescription
        throw error
    }

    // MARK: - Public API — Restore Purchases

    /// 恢复购买并返回当前有效 VIP 交易。真实 Apple 环境仍需逐笔交给后端验单。
    func restoreVIPPurchases(appAccountToken: UUID) async throws -> [ApplePurchaseReceipt] {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        try await StoreKit.AppStore.sync()
        var receipts: [ApplePurchaseReceipt] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true,
                  let productID = ProductID(rawValue: transaction.productID),
                  productID.isVIPSubscription else { continue }

            let receipt = purchaseReceipt(from: transaction, coins: 0)
            if receipt.requiresBackendVerification {
                guard transaction.appAccountToken == appAccountToken else { continue }
                vipPurchaseState.awaitServerVerification(productID: productID)
            } else {
                await transaction.finish()
                vipPurchaseState.activate(productID: productID)
            }
            receipts.append(receipt)
        }
        guard !receipts.isEmpty else {
            throw StoreKitPurchaseError.noActiveSubscription
        }
        Logger.store.info("StoreKitManager: purchases restored")
        return receipts
    }

    /// 后端确认权益已写入后才完成真实 Apple 交易并更新 App 会员态。
    func completeVIPDelivery(_ receipt: ApplePurchaseReceipt) async {
        guard let productID = ProductID(rawValue: receipt.productID) else { return }
        await finishTransaction(receipt)
        vipPurchaseState.activateFromServer(productID: productID)
    }

    /// 后端确认金币已记账后才完成真实消耗型交易，失败时保留交易供用户重试。
    func completeCoinDelivery(_ receipt: ApplePurchaseReceipt) async {
        await finishTransaction(receipt)
    }

    /// 返回尚未完成且属于当前 App 用户的真实 Apple 交易，供启动时补偿后端发货。
    func unfinishedPurchaseReceipts(appAccountToken: UUID) async -> [ApplePurchaseReceipt] {
        var receipts: [ApplePurchaseReceipt] = []
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  transaction.appAccountToken == appAccountToken,
                  transaction.revocationDate == nil,
                  let productID = ProductID(rawValue: transaction.productID),
                  productID.isCoinPackage || productID.isVIPSubscription else { continue }
            if productID.isVIPSubscription,
               transaction.expirationDate.map({ $0 <= Date() }) ?? false {
                continue
            }
            let receipt = purchaseReceipt(from: transaction, coins: 0)
            guard receipt.requiresBackendVerification else { continue }
            receipts.append(receipt)
        }
        return receipts
    }

    private func finishTransaction(_ receipt: ApplePurchaseReceipt) async {
        for await result in Transaction.all {
            guard case .verified(let transaction) = result,
                  String(transaction.id) == receipt.transactionID else { continue }
            await transaction.finish()
            break
        }
    }

    /// 使用后端钱包/VIP 查询结果同步会员页，不能用本地 StoreKit 结果代替真实服务端权益。
    func synchronizeServerVIP(isActive: Bool) {
        if isActive {
            vipPurchaseState.activateFromServer()
        } else if case .serverActive = vipPurchaseState.phase {
            vipPurchaseState.cancel()
        }
    }

    /// 以 StoreKit 当前有效权益为本地测试环境的唯一会员状态来源。
    func refreshVIPEntitlements() async {
        var activeProductID: ProductID?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true,
                  let productID = ProductID(rawValue: transaction.productID),
                  productID.isVIPSubscription,
                  purchaseReceipt(from: transaction, coins: 0).requiresBackendVerification == false else { continue }
            activeProductID = productID
            break
        }

        if let activeProductID {
            vipPurchaseState.activate(productID: activeProductID)
        } else if case .active = vipPurchaseState.phase {
            vipPurchaseState.cancel()
        }
    }

    // MARK: - Private — Transaction Listener

    /// 启动 StoreKit 2 Transaction 监听
    ///
    /// 监听所有通过 `Transaction.updates` 投递的新交易
    /// （包括购买、恢复、家庭共享等）。Xcode 本地交易可直接完成，真实交易等待后端发货。
    private func startTransactionListener() {
        transactionListenerTask = Task {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    let receipt = self.purchaseReceipt(from: transaction, coins: 0)
                    if receipt.requiresBackendVerification {
                        if let productID = ProductID(rawValue: transaction.productID), productID.isVIPSubscription {
                            self.vipPurchaseState.awaitServerVerification(productID: productID)
                        }
                        Logger.store.info("StoreKitManager: transaction awaits server verification for \(transaction.productID)")
                    } else {
                        await transaction.finish()
                        await self.refreshVIPEntitlements()
                        Logger.store.info("StoreKitManager: local transaction finished for \(transaction.productID)")
                    }
                case .unverified:
                    Logger.store.error("StoreKitManager: unverified transaction received")
                }
            }
        }
    }

    // MARK: - Private — Verification

    /// 验证 StoreKit 返回的 `VerificationResult`，提取已验证数据
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreKitPurchaseError.unverified
        }
    }

    private func purchaseReceipt(from transaction: StoreKit.Transaction, coins: Int) -> ApplePurchaseReceipt {
        ApplePurchaseReceipt(
            transactionID: String(transaction.id),
            productID: transaction.productID,
            environment: String(describing: transaction.environment).uppercased(),
            appAccountToken: transaction.appAccountToken?.uuidString,
            coins: coins
        )
    }

    // MARK: - Private — Fallback Price

    /// 本地回退价格映射
    private func fallbackPrice(for productID: ProductID) -> String {
        switch productID {
        case .coinsSmall:    return "$4.99"
        case .coinsMedium:   return "$9.99"
        case .coinsLarge:    return "$19.99"
        case .coinsXLarge:   return "$49.99"
        case .vipWeekly:     return "$12.99"
        case .vipMonthly:    return "$29.99"
        case .vipQuarterly:  return "$68.99"
        case .vipYearly:     return "$149.99"
        }
    }
}
