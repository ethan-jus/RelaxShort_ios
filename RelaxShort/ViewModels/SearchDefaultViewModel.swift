import SwiftUI
import Combine

// MARK: - Search Default ViewModel
/// 搜索默认页 ViewModel
/// 管理三榜（热搜榜/热播榜/新剧榜）数据加载与 Tab 切换
@MainActor
final class SearchDefaultViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedTab: Int = 0
    @Published var hotSearch: [RankDrama] = []
    @Published var hotPlay: [RankDrama] = []
    @Published var newDrama: [RankDrama] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let repository: HomeRepositoryProtocol

    // MARK: - Tab Titles

    let tabs = ["热搜榜", "热播榜", "新剧榜"]

    var emptyMessage: String {
        switch selectedTab {
        case 0: return "暂无热搜"
        case 1: return "暂无热播"
        case 2: return "暂无新剧"
        default: return "暂无数据"
        }
    }

    var currentDramas: [RankDrama] {
        switch selectedTab {
        case 0: return hotSearch
        case 1: return hotPlay
        case 2: return newDrama
        default: return []
        }
    }

    // MARK: - Init

    init(repository: HomeRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Load Data

    func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            let allDramas = try await repository.fetchDramas(category: .all)
            populateRanks(from: allDramas)
        } catch {
            errorMessage = error.localizedDescription
            logError("SearchDefaultViewModel.loadData failed: \(error)")
        }
        isLoading = false
    }

    // MARK: - Tab Switching

    func switchTab(to index: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedTab = index
        }
    }

    // MARK: - Private Helpers

    private func populateRanks(from dramas: [DramaItem]) {
        // 热搜榜：按评分降序
        hotSearch = dramas
            .sorted { $0.rating > $1.rating }
            .prefix(20)
            .enumerated()
            .map { RankDrama(from: $1, rank: $0 + 1) }

        // 热播榜：按播放量降序
        hotPlay = dramas
            .sorted { $0.viewCount > $1.viewCount }
            .prefix(20)
            .enumerated()
            .map { RankDrama(from: $1, rank: $0 + 1) }

        // 新剧榜：按 ID 降序（模拟新剧排序）
        newDrama = dramas
            .sorted { $0.id > $1.id }
            .prefix(20)
            .enumerated()
            .map { RankDrama(from: $1, rank: $0 + 1) }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
