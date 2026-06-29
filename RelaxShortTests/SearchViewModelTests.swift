import Foundation
import Testing
@testable import RelaxShort

@MainActor
struct SearchViewModelTests {
    @Test
    func clickingSearchResultStoresTheRealQueryInRecentSearches() {
        let suiteName = "SearchViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = SearchViewModel(
            repository: MockSearchRepository(),
            historyStore: defaults
        )
        viewModel.searchText = "  Jiang   Nan  "

        viewModel.trackResultClick(dramaID: "20250312000001")

        #expect(viewModel.searchHistory == ["Jiang Nan"])
    }
}
