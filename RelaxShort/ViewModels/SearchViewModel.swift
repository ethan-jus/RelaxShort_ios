import SwiftUI
import Combine

// MARK: - Search ViewModel
/// 搜索页 ViewModel，管理搜索文本、历史记录和结果过滤
@MainActor
final class SearchViewModel: ObservableObject {
    private let repository: SearchRepositoryProtocol

    @Published var searchText: String = ""
    @Published var allDramas: [DramaItem] = []
    @Published var searchResults: [DramaItem] = []
    @Published var searchHistory: [String] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?

    private let historyKey = "com.relaxshort.searchHistory"
    private var cancellables = Set<AnyCancellable>()

    init(repository: SearchRepositoryProtocol) {
        self.repository = repository
        loadHistory()

        // Debounced search: 300ms after typing stops
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                Task { await self?.performSearch(query: query) }
            }
            .store(in: &cancellables)

        Task {
            await loadAllDramas()
        }
    }

    private func loadAllDramas() async {
        do {
            allDramas = try await repository.fetchDramas(category: .all)
        } catch {
            errorMessage = "搜索数据加载失败"
            logError("SearchViewModel.loadAllDramas failed: \(error)")
            allDramas = []
        }
    }

    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            errorMessage = nil
            return
        }
        isSearching = true
        errorMessage = nil
        do {
            let (items, _, _) = try await repository.search(query: trimmed, cursor: nil, limit: 20)
            searchResults = items
        } catch {
            errorMessage = "搜索失败"
            logError("SearchViewModel.performSearch failed: \(error)")
            searchResults = allDramas.filter { drama in
                drama.title.localizedCaseInsensitiveContains(trimmed) ||
                drama.category.localizedCaseInsensitiveContains(trimmed) ||
                drama.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }
        isSearching = false
    }

    func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        addToHistory(trimmed)
    }

    func searchFromHistory(_ query: String) {
        searchText = query
        submitSearch()
    }

    // MARK: - History Management

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let history = try? JSONDecoder().decode([String].self, from: data) {
            searchHistory = history
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func addToHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        searchHistory.insert(query, at: 0)
        if searchHistory.count > 10 {
            searchHistory = Array(searchHistory.prefix(10))
        }
        saveHistory()
    }

    func removeHistoryItem(_ item: String) {
        searchHistory.removeAll { $0 == item }
        saveHistory()
    }

    func clearHistory() {
        searchHistory.removeAll()
        saveHistory()
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
