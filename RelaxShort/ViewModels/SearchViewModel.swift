import Combine
import SwiftUI

/// 管理关键词搜索、分页和本地搜索历史。
@MainActor
final class SearchViewModel: ObservableObject {
    private let repository: SearchRepositoryProtocol
    private let historyKey = "com.relaxshort.searchHistory"

    @Published var searchText = ""
    @Published private(set) var searchResults: [DramaItem] = []
    @Published private(set) var searchHistory: [String] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasCompletedSearch = false
    @Published private(set) var errorMessage: String?

    private var nextCursor: String?
    private var hasMore = false
    private var searchGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    init(repository: SearchRepositoryProtocol) {
        self.repository = repository
        loadHistory()

        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                Task {
                    await self?.performSearch(query: query)
                }
            }
            .store(in: &cancellables)
    }

    func retry() {
        Task {
            await performSearch(query: searchText)
        }
    }

    func loadMoreIfNeeded(currentItem: DramaItem) async {
        guard let lastItem = searchResults.last, lastItem.id == currentItem.id else {
            return
        }
        guard hasMore, !isLoadingMore else {
            return
        }

        let requestQuery = normalize(searchText)
        let requestGeneration = searchGeneration
        guard !requestQuery.isEmpty else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let (items, cursor, more) = try await repository.search(
                query: requestQuery,
                cursor: nextCursor,
                limit: 20
            )
            guard isCurrent(
                query: requestQuery,
                generation: requestGeneration
            ) else {
                return
            }

            let existingIDs = Set(searchResults.map(\.id))
            searchResults.append(contentsOf: items.filter { !existingIDs.contains($0.id) })
            nextCursor = cursor
            hasMore = more
        } catch {
            logError("SearchViewModel.loadMore failed: \(error)")
        }
    }

    func submitSearch() {
        let query = normalize(searchText)
        guard !query.isEmpty else {
            return
        }
        addToHistory(query)
    }

    func searchFromHistory(_ query: String) {
        searchText = query
        submitSearch()
    }

    func removeHistoryItem(_ item: String) {
        searchHistory.removeAll { $0 == item }
        saveHistory()
    }

    func clearHistory() {
        searchHistory.removeAll()
        saveHistory()
    }

    private func performSearch(query: String) async {
        let normalizedQuery = normalize(query)
        searchGeneration += 1
        let requestGeneration = searchGeneration

        guard !normalizedQuery.isEmpty else {
            searchResults = []
            isSearching = false
            errorMessage = nil
            hasCompletedSearch = false
            resetPagination()
            return
        }

        isSearching = true
        errorMessage = nil
        hasCompletedSearch = false
        resetPagination()

        defer {
            if isCurrent(
                query: normalizedQuery,
                generation: requestGeneration
            ) {
                isSearching = false
            }
        }

        do {
            let (items, cursor, more) = try await repository.search(
                query: normalizedQuery,
                cursor: nil,
                limit: 20
            )
            guard isCurrent(
                query: normalizedQuery,
                generation: requestGeneration
            ) else {
                return
            }

            searchResults = items
            nextCursor = cursor
            hasMore = more
            hasCompletedSearch = true
        } catch {
            guard isCurrent(
                query: normalizedQuery,
                generation: requestGeneration
            ) else {
                return
            }
            errorMessage = L10n.searchFailed
            hasCompletedSearch = true
            logError("SearchViewModel.performSearch failed: \(error)")
        }
    }

    private func resetPagination() {
        nextCursor = nil
        hasMore = false
    }

    private func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isCurrent(query: String, generation: Int) -> Bool {
        generation == searchGeneration && query == normalize(searchText)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        searchHistory = history
    }

    private func addToHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        searchHistory.insert(query, at: 0)
        searchHistory = Array(searchHistory.prefix(10))
        saveHistory()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(searchHistory) else {
            return
        }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
