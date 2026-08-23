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
    private var requestGate = LatestRequestGate()

    // MARK: - Init

    init(repository: HomeRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Load Data

    func loadData() async {
        let requestGeneration = requestGate.begin()
        let type = mapToRankingType(selectedCategory)
        isLoading = true
        errorMessage = nil
        defer {
            if requestGate.accepts(requestGeneration) {
                isLoading = false
            }
        }

        do {
            let entries = try await repository.fetchRankingEntries(type: type)
            guard requestGate.accepts(requestGeneration) else { return }
            self.dramas = entries.map(RankDrama.init(entry:))
        } catch {
            guard requestGate.accepts(requestGeneration), !Task.isCancelled else { return }
            errorMessage = "排行榜数据加载失败"
            logError("RankViewModel.loadData failed: \(error)")
            // 保持现有数据显示，不清空
        }
    }

    func reloadForDiscoveryCountryChange() async {
        await loadData()
    }

    func switchCategory(_ category: RankCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        Task {
            await loadData()
        }
    }

    // MARK: - Type Mapping

    private func mapToRankingType(_ category: RankCategory) -> String {
        category.apiType
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
