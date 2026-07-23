import Foundation

/// 钱包首页领域模型，不直接暴露后端 DTO。
struct WalletOverview: Sendable {
    let balance: Int
    let transactions: [WalletTransaction]
    let hasMore: Bool
}

struct WalletTransaction: Identifiable, Sendable {
    let id: Int64
    let transactionType: String
    let amount: Int
    let balanceAfter: Int?
    let source: String
    let createdAt: Date?
}
