import SwiftUI

// MARK: - Rank ViewModel

/// 排行榜页面 ViewModel
/// 管理榜单分类切换、排行数据加载
@MainActor
final class RankViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedCategory: RankCategory = .hot
    @Published var dramas: [RankDrama] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let repository: HomeRepositoryProtocol

    // MARK: - Init

    init(repository: HomeRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Load Data

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let allDramas = try await repository.fetchDramas(category: .all)
            let sorted: [DramaItem]
            switch selectedCategory {
            case .hot:
                sorted = allDramas.sorted { $0.viewCount > $1.viewCount }
            case .trending:
                sorted = allDramas.filter { $0.isTrending }
                    .sorted { $0.viewCount > $1.viewCount }
            case .new:
                sorted = allDramas.sorted {
                    (Int($0.id) ?? 0) > (Int($1.id) ?? 0)
                }
            }
            self.dramas = sorted.enumerated().map { index, drama in
                RankDrama(from: drama, rank: index + 1)
            }
        } catch {
            errorMessage = "排行榜数据加载失败"
            logError("RankViewModel.loadData failed: \(error)")
            dramas = []
        }
    }

    func switchCategory(_ category: RankCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        Task {
            await loadData()
        }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
