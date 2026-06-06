import SwiftUI

// MARK: - Recommend ViewModel

/// 推荐页沉浸式视频流 ViewModel — DramaBox 标准
@MainActor
final class RecommendViewModel: ObservableObject {
    @Published var dramas: [DramaItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let repository: HomeRepositoryProtocol

    init(repository: HomeRepositoryProtocol) {
        self.repository = repository
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            dramas = try await repository.fetchDramas(category: .all)
        } catch {
            errorMessage = L10n.recommendLoadFailed
            #if DEBUG
            Logger.viewModel.error("RecommendViewModel.loadData failed: \(error)")
            #endif
            dramas = []
        }
    }
}
