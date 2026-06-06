import SwiftUI
import Combine

// MARK: - Favorites ViewModel

/// 收藏/历史页 ViewModel，管理观看历史数据的加载与状态
@MainActor
final class FavoritesViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var watchHistory: [WatchHistoryItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showLoginModal: Bool = false

    // MARK: - Dependencies

    private let repository: FavoritesRepositoryProtocol

    // MARK: - Init

    init(repository: FavoritesRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Public Methods

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let history = try await repository.fetchWatchHistory(page: 1)
            self.watchHistory = history
        } catch {
            logError("FavoritesViewModel.fetchWatchHistory failed: \(error)")
            watchHistory = []
        }
    }

    func presentLoginModal() {
        showLoginModal = true
    }

    func dismissLoginModal() {
        showLoginModal = false
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
