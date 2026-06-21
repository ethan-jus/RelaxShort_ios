import SwiftUI
import Combine

// MARK: - Search Default ViewModel
/// 搜索默认页 ViewModel
/// Task16：真实模式优先用 RealSearchRepository.fetchDramas（走 search/default hot_series），
/// Mock 模式保留 Home 全量本地排序。
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

    private let homeRepository: HomeRepositoryProtocol
    private let searchRepository: SearchRepositoryProtocol

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

    init(homeRepository: HomeRepositoryProtocol, searchRepository: SearchRepositoryProtocol) {
        self.homeRepository = homeRepository
        self.searchRepository = searchRepository
    }

    // MARK: - Load Data

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if DependencyContainer.useRealAPI {
            await loadFromSearchDefault()
        } else {
            await loadFromHome()
        }
    }

    /// 真实模式：从 search/default 取 hot_series 作为发现数据
    private func loadFromSearchDefault() async {
        do {
            let items = try await searchRepository.fetchDramas(category: .all)
            populateRanks(from: items)
        } catch {
            errorMessage = "搜索发现数据加载失败"
            logError("SearchDefaultViewModel.loadFromSearchDefault failed: \(error)")
        }
    }

    /// Mock 模式：全量 Home 数据本地排序
    private func loadFromHome() async {
        do {
            let allDramas = try await homeRepository.fetchDramas(category: .all)
            populateRanks(from: allDramas)
        } catch {
            errorMessage = error.localizedDescription
            logError("SearchDefaultViewModel.loadFromHome failed: \(error)")
        }
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

        // 新剧榜：按 ID 降序
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
