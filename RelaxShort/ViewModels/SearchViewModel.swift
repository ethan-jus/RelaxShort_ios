import SwiftUI
import Combine

// MARK: - Search ViewModel
/// 搜索页 ViewModel，管理搜索文本、历史记录、分页和结果展示。
/// Task16：新增真实搜索分页（nextCursor/hasMore/isLoadingMore/loadMoreIfNeeded）。
@MainActor
final class SearchViewModel: ObservableObject {
    private let repository: SearchRepositoryProtocol

    @Published var searchText: String = ""
    @Published var allDramas: [DramaItem] = []
    @Published var searchResults: [DramaItem] = []
    @Published var searchHistory: [String] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?
    /// Task16: 分页状态
    @Published var isLoadingMore: Bool = false
    private var nextCursor: String?
    private var hasMore: Bool = false

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

    /// 执行搜索（关键词变化时重置分页状态）
    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            errorMessage = nil
            resetPagination()
            return
        }
        isSearching = true
        errorMessage = nil
        resetPagination()
        do {
            let (items, cursor, more) = try await repository.search(query: trimmed, cursor: nil, limit: 20)
            searchResults = items
            nextCursor = cursor
            hasMore = more
        } catch {
            errorMessage = "搜索失败"
            logError("SearchViewModel.performSearch failed: \(error)")
            // 失败不清空已有结果
        }
        isSearching = false
    }

    /// Task16: 加载更多（无限滚动）
    func loadMoreIfNeeded(currentItem: DramaItem) async {
        guard let last = searchResults.last, last.id == currentItem.id else { return }
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let (items, cursor, more) = try await repository.search(
                query: searchText.trimmingCharacters(in: .whitespaces),
                cursor: nextCursor, limit: 20
            )
            searchResults.append(contentsOf: items)
            nextCursor = cursor
            hasMore = more
        } catch {
            logError("SearchViewModel.loadMore failed: \(error)")
            // 加载更多失败不清空已有结果，保留重试机会
        }
        isLoadingMore = false
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

    // MARK: - Pagination

    private func resetPagination() {
        nextCursor = nil
        hasMore = false
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
