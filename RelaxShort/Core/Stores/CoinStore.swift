import SwiftUI
import Combine

// MARK: - Coin Store

/// 金币管理器 — 管理用户金币余额的全局状态
/// 持久化到 UserDefaults，@MainActor 确保线程安全
@MainActor
final class CoinStore: ObservableObject {

    /// 当前金币余额
    @Published var coinBalance: Int {
        didSet { save() }
    }

    private let storageKey = "com.relaxshort.coinBalance"

    // MARK: - Init

    init() {
        self.coinBalance = UserDefaults.standard.integer(forKey: storageKey)
        #if DEBUG
        Logger.storage.info("CoinStore init: balance=\(self.coinBalance)")
        #endif
    }

    // MARK: - Public API

    /// 增加金币 — 对接 StoreKitManager 购买回调
    /// - Parameters:
    ///   - amount: 增加的金币数量
    ///   - source: 金币来源标记（如 "purchase_coins_small", "check_in", "ad_reward"）
    func addCoins(_ amount: Int, source: String) {
        let oldBalance = coinBalance
        coinBalance += amount
        #if DEBUG
        Logger.store.info("CoinStore: +\(amount) coins (\(source)), balance: \(oldBalance) → \(self.coinBalance)")
        #endif
    }

    /// 购买金币包 — 增加金币余额
    /// - Parameter amount: 购买得到的金币数量（含赠送）
    func purchaseCoins(amount: Int) {
        addCoins(amount, source: "purchase")
    }

    /// 消费金币 — 返回 true 表示扣款成功
    /// - Parameter amount: 要消费的金币数量
    /// - Returns: 余额充足返回 `true`，不足返回 `false`
    func spendCoins(_ amount: Int) -> Bool {
        guard coinBalance >= amount else {
            #if DEBUG
            Logger.store.warning("CoinStore: insufficient coins (\(self.coinBalance) < \(amount))")
            #endif
            return false
        }
        coinBalance -= amount
        #if DEBUG
        Logger.store.info("CoinStore: spent \(amount) coins, balance=\(self.coinBalance)")
        #endif
        return true
    }

    // MARK: - Private

    private func save() {
        UserDefaults.standard.set(coinBalance, forKey: storageKey)
    }
}
