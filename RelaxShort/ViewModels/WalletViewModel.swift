import Foundation

@MainActor
final class WalletViewModel: ObservableObject {
    @Published private(set) var overview: WalletOverview?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: WalletRepositoryProtocol

    init(repository: WalletRepositoryProtocol) {
        self.repository = repository
    }

    func load(limit: Int = 4) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            overview = try await repository.fetchOverview(limit: limit)
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            Logger.viewModel.error("WalletViewModel.load failed: \(error)")
            #endif
        }
    }
}
