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
    case unknown

    var errorDescription: String? {
        switch self {
        case .userCancelled: return "用户取消购买"
        case .pending:       return "购买等待处理中"
        case .unverified:    return "交易验证失败"
        case .unknown:       return "未知错误"
        }
    }
}

// MARK: - StoreKit Manager

/// 内购管理器 — 使用 StoreKit 2 API
///
/// 双重模式：
/// 1. **StoreKit 2 真实购买** — 当 App Store Connect 配置了产品时自动使用
/// 2. **Mock 回退** — 当产品请求失败或未配置时，使用本地定义的 fallback 数据
///
/// 用法：
/// ```swift
/// @EnvironmentObject var storeKit: StoreKitManager
/// let coins = try await storeKit.purchaseCoinPackage(pkg)
/// try await storeKit.restorePurchases()
/// ```
@MainActor
final class StoreKitManager: ObservableObject {

    // MARK: - Published State

    @Published var isPurchasing: Bool = false
    @Published var purchaseError: String?
    /// StoreKit 产品是否已加载（从 App Store 成功获取）
    @Published var isStoreKitReady: Bool = false

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

    /// VIP 订阅列表（本地回退数据）
    let vipSubscriptions: [VIPSubscription] = [
        VIPSubscription(id: "vip_weekly",    productID: .vipWeekly,    period: "周", price: "$12.99",  dailyEquivalent: "$1.86/天"),
        VIPSubscription(id: "vip_monthly",   productID: .vipMonthly,   period: "月", price: "$29.99",  dailyEquivalent: "$1.00/天"),
        VIPSubscription(id: "vip_quarterly", productID: .vipQuarterly, period: "季", price: "$68.99",  dailyEquivalent: "$0.77/天"),
        VIPSubscription(id: "vip_yearly",    productID: .vipYearly,    period: "年", price: "$199.99", dailyEquivalent: "$0.55/天"),
    ]

    // MARK: - Init

    init() {
        startTransactionListener()
        Task { await requestProducts() }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Public API — Display Price

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
            isStoreKitReady = true
            Logger.store.info("StoreKitManager: loaded \(self.storeKitProducts.count) products from App Store")
        } catch {
            Logger.store.warning("StoreKitManager: product request failed, using mock fallback — \(error.localizedDescription)")
            storeKitProducts = [:]
            isStoreKitReady = false
        }
    }

    // MARK: - Public API — Purchase Coin Package

    /// 购买金币包
    /// - Parameter package: 要购买的金币包
    /// - Returns: 购买成功后返回获取的金币数（含 bonus）
    /// - Throws: `StoreKitPurchaseError` 或 StoreKit 原生错误
    func purchaseCoinPackage(_ package: CoinPackage) async throws -> Int {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        let totalCoins = package.amount + (package.bonus ?? 0)

        // ── StoreKit 2 真实购买 ──
        if let product = storeKitProducts[package.productID.rawValue] {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                Logger.store.info("StoreKit: purchased \(product.id) → \(totalCoins) coins")
                return totalCoins

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

        // ── Mock 回退 ──
        try await Task.sleep(nanoseconds: 800_000_000)
        Logger.store.info("StoreKit(mock): purchased \(package.productID.rawValue) → \(totalCoins) coins")
        return totalCoins
    }

    // MARK: - Public API — Purchase VIP

    /// 购买 VIP 订阅
    /// - Parameter subscription: 要购买的订阅
    /// - Returns: 购买成功返回 `true`
    /// - Throws: `StoreKitPurchaseError` 或 StoreKit 原生错误
    func purchaseVIP(_ subscription: VIPSubscription) async throws -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        // ── StoreKit 2 真实购买 ──
        if let product = storeKitProducts[subscription.productID.rawValue] {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                Logger.store.info("StoreKit: purchased VIP \(product.id)")
                return true

            case .userCancelled:
                Logger.store.info("StoreKit: user cancelled VIP purchase")
                throw StoreKitPurchaseError.userCancelled

            case .pending:
                Logger.store.info("StoreKit: VIP purchase pending")
                throw StoreKitPurchaseError.pending

            @unknown default:
                throw StoreKitPurchaseError.unknown
            }
        }

        // ── Mock 回退 ──
        try await Task.sleep(nanoseconds: 800_000_000)
        Logger.store.info("StoreKit(mock): purchased VIP \(subscription.productID.rawValue)")
        return true
    }

    // MARK: - Public API — Restore Purchases

    /// 恢复购买 — 调用 App Store 同步所有历史交易
    ///
    /// 恢复的交易会通过 `Transaction.updates` 异步投递，
    /// 在 `startTransactionListener()` 中统一处理。
    func restorePurchases() async throws {
        try await StoreKit.AppStore.sync()
        Logger.store.info("StoreKitManager: purchases restored")
    }

    // MARK: - Private — Transaction Listener

    /// 启动 StoreKit 2 Transaction 监听
    ///
    /// 监听所有通过 `Transaction.updates` 投递的新交易
    /// （包括购买、恢复、家庭共享等），自动验证并完成。
    private func startTransactionListener() {
        transactionListenerTask = Task {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    Logger.store.info("StoreKitManager: transaction finished for \(transaction.productID)")
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
        case .vipYearly:     return "$199.99"
        }
    }
}
