import SwiftUI

// MARK: - Search View

/// 搜索页 — NavigationStack 内 push，系统原生返回按钮 + 自定义搜索栏在返回按钮右侧
struct SearchView: View {
    @EnvironmentObject private var appStore: AppStore
    @StateObject private var viewModel: SearchViewModel

    init(viewModel: SearchViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? SearchViewModel(repository: MockSearchRepository()))
    }
    @State private var playerDrama: DramaItem?
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.searchText.isEmpty {
                SearchDefaultView(viewModel: SearchDefaultViewModel(repository: MockHomeRepository()))
            } else {
                VStack(spacing: 0) {
                    if viewModel.searchResults.isEmpty && !viewModel.isSearching {
                        emptyStateView
                    } else {
                        GeometryReader { geo in
                            ScrollView {
                                MarketingGrid(dramas: viewModel.searchResults, playerDrama: $playerDrama, containerW: geo.size.width)
                                    .padding(.top, DT.Space.lg)
                            }
                            .scrollDismissesKeyboard(.immediately)
                        }
                    }
                }
                .background(DT.Color.bgPrimary.ignoresSafeArea())
            }
        }
        .background(DT.Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                searchBar
            }
        }
        .onChange(of: playerDrama) { _, drama in
            guard let drama = drama else { return }
            appStore.navigationTarget = SeriesPlayerNav(drama: drama, startEpisode: max(1, drama.currentEpisode))
            playerDrama = nil
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textSecondary)
            TextField(L10n.homeSearchPlaceholder, text: $viewModel.searchText)
                .font(DT.Font.body(14))
                .foregroundColor(DT.Color.textSecondary)
                .tint(DT.brandPink)
                .frame(minWidth: 240)
                .onSubmit { viewModel.submitSearch() }
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DT.Font.caption)
                        .foregroundColor(DT.Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, DT.Space.md)
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: DT.Space.md) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(DT.Font.body(48))
                .foregroundColor(DT.Color.textTertiary)
            Text(L10n.noSearchResults)
                .font(DT.Font.subtitle)
                .foregroundColor(DT.Color.textPrimary)
            Text(L10n.tryDifferentKeyword)
                .font(DT.Font.bodyDefault)
                .foregroundColor(DT.Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Search") { SearchView() }
#endif
