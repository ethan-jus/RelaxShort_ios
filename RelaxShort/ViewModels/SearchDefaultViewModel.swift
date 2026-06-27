import SwiftUI

/// 加载并维护 Search 默认页的三个真实榜单。
@MainActor
final class SearchDefaultViewModel: ObservableObject {
    @Published var selectedTheme: SearchRankTheme = .topSearched
    @Published private(set) var rankings: [SearchRankTheme: [RankDrama]] = [:]
    @Published private(set) var trendingSearches: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let homeRepository: HomeRepositoryProtocol
    private let searchRepository: SearchRepositoryProtocol

    init(
        homeRepository: HomeRepositoryProtocol,
        searchRepository: SearchRepositoryProtocol
    ) {
        self.homeRepository = homeRepository
        self.searchRepository = searchRepository
    }

    func items(for theme: SearchRankTheme) -> [RankDrama] {
        rankings[theme] ?? []
    }

    func selectTheme(_ theme: SearchRankTheme) {
        selectedTheme = theme
    }

    func loadData() async {
        guard rankings.isEmpty || trendingSearches.isEmpty else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let suggestions = fetchSuggestions()

        do {
            async let topItems = fetchRanked(.topSearched)
            async let trendingItems = fetchRanked(.mostTrending)
            async let releaseItems = fetchRanked(.newReleases)

            let loaded = try await (topItems, trendingItems, releaseItems)
            rankings = [
                .topSearched: loaded.0,
                .mostTrending: loaded.1,
                .newReleases: loaded.2
            ]
        } catch {
            errorMessage = L10n.searchFailed
            logError("SearchDefaultViewModel.loadData failed: \(error)")
        }

        trendingSearches = await suggestions
    }

    private func fetchRanked(_ theme: SearchRankTheme) async throws -> [RankDrama] {
        try await homeRepository.fetchRankings(type: theme.apiType)
            .enumerated()
            .map { index, drama in
                RankDrama(from: drama, rank: index + 1)
            }
    }

    private func fetchSuggestions() async -> [String] {
        do {
            return try await searchRepository.fetchSuggestions()
        } catch {
            logError("SearchDefaultViewModel.fetchSuggestions failed: \(error)")
            return []
        }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
