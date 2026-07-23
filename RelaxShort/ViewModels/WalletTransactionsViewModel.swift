import Foundation

@MainActor
final class WalletTransactionsViewModel: ObservableObject {
    @Published private(set) var transactions: [WalletTransaction] = []
    @Published private(set) var totalEarned = 0
    @Published private(set) var totalSpent = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedMonth: Date
    @Published private(set) var selectedCategory: WalletTransactionCategory = .all

    let availableMonths: [Date]

    private let repository: WalletRepositoryProtocol
    private var nextCursor: String?
    private var requestID = UUID()
    private let calendar: Calendar

    init(repository: WalletRepositoryProtocol) {
        self.repository = repository
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLocalization.locale
        self.calendar = calendar

        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let monthStart = calendar.date(from: components) ?? now
        selectedMonth = monthStart
        availableMonths = (0..<12).compactMap {
            calendar.date(byAdding: .month, value: -$0, to: monthStart)
        }
    }

    func load() async {
        await reload()
    }

    func selectMonth(_ month: Date) async {
        guard !calendar.isDate(month, equalTo: selectedMonth, toGranularity: .month) else { return }
        selectedMonth = month
        await reload()
    }

    func selectCategory(_ category: WalletTransactionCategory) async {
        guard category != selectedCategory else { return }
        selectedCategory = category
        await reload()
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore, let nextCursor else { return }
        let activeRequestID = requestID
        isLoadingMore = true
        defer {
            if activeRequestID == requestID { isLoadingMore = false }
        }

        do {
            let page = try await repository.fetchTransactions(
                cursor: nextCursor,
                limit: 20,
                month: monthKey,
                category: selectedCategory
            )
            guard activeRequestID == requestID else { return }
            let existingIDs = Set(transactions.map(\.id))
            transactions.append(contentsOf: page.transactions.filter { !existingIDs.contains($0.id) })
            self.nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            guard activeRequestID == requestID else { return }
            errorMessage = error.localizedDescription
            #if DEBUG
            Logger.viewModel.error("WalletTransactionsViewModel.loadMore failed: \(error)")
            #endif
        }
    }

    private func reload() async {
        requestID = UUID()
        let activeRequestID = requestID
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        transactions = []
        nextCursor = nil
        hasMore = false

        defer {
            if activeRequestID == requestID { isLoading = false }
        }

        do {
            let page = try await repository.fetchTransactions(
                cursor: nil,
                limit: 20,
                month: monthKey,
                category: selectedCategory
            )
            guard activeRequestID == requestID else { return }
            transactions = page.transactions
            totalEarned = page.totalEarned
            totalSpent = page.totalSpent
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            guard activeRequestID == requestID else { return }
            errorMessage = error.localizedDescription
            #if DEBUG
            Logger.viewModel.error("WalletTransactionsViewModel.reload failed: \(error)")
            #endif
        }
    }

    private var monthKey: String {
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        return String(format: "%04d-%02d", components.year ?? 1970, components.month ?? 1)
    }
}
