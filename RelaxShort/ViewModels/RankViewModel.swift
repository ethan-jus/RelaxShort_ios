import SwiftUI

// MARK: - Rank ViewModel

/// 排行榜页面 ViewModel
/// Task16：通过协议 `fetchRankings(type:)` 调用后端 rankings，不再本地排序。
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
            let type = mapToRankingType(selectedCategory)
            let items = try await repository.fetchRankings(type: type)
            self.dramas = items.enumerated().map { index, drama in
                RankDrama(from: drama, rank: index + 1)
            }
        } catch {
            errorMessage = "排行榜数据加载失败"
            logError("RankViewModel.loadData failed: \(error)")
            // 保持现有数据显示，不清空
        }
    }

    func switchCategory(_ category: RankCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        Task {
            await loadData()
        }
    }

    // MARK: - Type Mapping

    /// RankCategory → 后端 rankings type 参数。
    /// 后端 rankings 接口支持的 type: popular / new / trending（以 IOS_API_CONTRACT_V1.md 为准）
    private func mapToRankingType(_ category: RankCategory) -> String {
        switch category {
        case .hot:      return "popular"
        case .trending: return "trending"
        case .new:      return "new"
        }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
