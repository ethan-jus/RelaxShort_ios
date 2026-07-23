import Foundation

/// 真实钱包仓库：并发读取余额与金币流水，并在此完成 DTO → 领域模型映射。
final class RealWalletRepository: WalletRepositoryProtocol {
    private let client = APIClient.shared

    func fetchOverview(limit: Int) async throws -> WalletOverview {
        async let walletDTO: WalletResponseDTO = client.requestData(.userWallet)
        async let transactionsDTO: WalletTransactionsResponseDTO = client.requestData(
            .walletTransactions(cursor: nil, limit: limit)
        )
        let (wallet, transactions) = try await (walletDTO, transactionsDTO)

        let balance = wallet.balance.map(Self.intValue) ?? 0
        let items = (transactions.items ?? []).map { dto in
            WalletTransaction(
                id: dto.id,
                transactionType: dto.transactionType,
                amount: Self.intValue(dto.amount),
                balanceAfter: dto.balanceAfter.map(Self.intValue),
                source: dto.source,
                createdAt: dto.createdAt.flatMap(BackendDateParser.parse)
            )
        }
        return WalletOverview(
            balance: balance,
            transactions: items,
            hasMore: transactions.hasMore ?? false
        )
    }

    private static func intValue(_ value: Decimal) -> Int {
        (value as NSDecimalNumber).intValue
    }
}
