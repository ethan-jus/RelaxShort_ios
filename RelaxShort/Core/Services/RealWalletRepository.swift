import Foundation

/// 真实钱包仓库：并发读取余额与金币流水，并在此完成 DTO → 领域模型映射。
final class RealWalletRepository: WalletRepositoryProtocol {
    private let client = APIClient.shared

    func fetchOverview(limit: Int) async throws -> WalletOverview {
        async let walletDTO: WalletResponseDTO = client.requestData(.userWallet)
        async let transactionsDTO: WalletTransactionsResponseDTO = client.requestData(
            .walletTransactions(
                cursor: nil,
                limit: limit,
                month: Self.currentMonth,
                category: WalletTransactionCategory.all.rawValue
            )
        )
        let (wallet, transactions) = try await (walletDTO, transactionsDTO)

        let balance = wallet.balance.map(Self.intValue) ?? 0
        let items = (transactions.items ?? []).map(Self.mapTransaction)
        return WalletOverview(
            balance: balance,
            transactions: items,
            hasMore: transactions.hasMore ?? false
        )
    }

    func fetchTransactions(
        cursor: String?,
        limit: Int,
        month: String,
        category: WalletTransactionCategory
    ) async throws -> WalletTransactionPage {
        let dto: WalletTransactionsResponseDTO = try await client.requestData(
            .walletTransactions(
                cursor: cursor,
                limit: limit,
                month: month,
                category: category.rawValue
            )
        )
        return WalletTransactionPage(
            period: dto.period ?? month,
            totalEarned: dto.totalEarned.map(Self.intValue) ?? 0,
            totalSpent: dto.totalSpent.map(Self.intValue) ?? 0,
            transactions: (dto.items ?? []).map(Self.mapTransaction),
            nextCursor: dto.nextCursor,
            hasMore: dto.hasMore ?? false
        )
    }

    private static var currentMonth: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private static func mapTransaction(_ dto: WalletTransactionDTO) -> WalletTransaction {
        WalletTransaction(
            id: dto.id,
            transactionType: dto.transactionType,
            amount: intValue(dto.amount),
            balanceAfter: dto.balanceAfter.map(intValue),
            source: dto.source,
            createdAt: dto.createdAt.flatMap(BackendDateParser.parse)
        )
    }

    private static func intValue(_ value: Decimal) -> Int {
        (value as NSDecimalNumber).intValue
    }
}
