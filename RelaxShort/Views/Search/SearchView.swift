import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: SearchViewModel
    @StateObject private var defaultViewModel: SearchDefaultViewModel
    @State private var playerDrama: DramaItem?

    init(
        searchRepository: SearchRepositoryProtocol,
        discoveryRepository: HomeRepositoryProtocol,
        analytics: (any DiscoveryAnalyticsTracking)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: SearchViewModel(
                repository: searchRepository,
                analytics: analytics ?? NoopDiscoveryAnalyticsTracker()
            )
        )
        _defaultViewModel = StateObject(
            wrappedValue: SearchDefaultViewModel(
                homeRepository: discoveryRepository,
                searchRepository: searchRepository
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            if viewModel.searchText.isEmpty {
                defaultContent
            } else {
                searchContent
            }
        }
        .background(DT.Color.bgPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
        .onChange(of: playerDrama) { _, drama in
            guard let drama else { return }
            viewModel.trackResultClick(dramaID: drama.id)
            openPlayer(drama)
            playerDrama = nil
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 36)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(DB.mutedText)

                TextField(
                    L10n.searchPlaceholder,
                    text: $viewModel.searchText
                )
                .font(.system(size: 15))
                .foregroundColor(.white)
                .tint(DB.logoRed)
                .submitLabel(.search)
                .onSubmit {
                    viewModel.submitSearch()
                }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(DB.mutedText)
                                .frame(width: 28, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.clearSearchText)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 36)
            .background(Color(hex: "#252525"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var defaultContent: some View {
        SearchDefaultView(
            viewModel: defaultViewModel,
            searchHistory: viewModel.searchHistory,
            onHistorySelected: viewModel.searchFromHistory,
            onClearHistory: viewModel.clearHistory,
            onDramaSelected: openPlayer
        )
    }

    @ViewBuilder
    private var searchContent: some View {
        if viewModel.isSearching && viewModel.searchResults.isEmpty {
            ProgressView()
                .tint(DB.logoRed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage,
                  viewModel.searchResults.isEmpty {
            searchErrorState(errorMessage)
        } else if viewModel.hasCompletedSearch
                    && viewModel.searchResults.isEmpty {
            searchEmptyState
        } else {
            searchResults
        }
    }

    private var searchResults: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    MarketingGrid(
                        dramas: viewModel.searchResults,
                        playerDrama: $playerDrama,
                        containerW: proxy.size.width
                    )
                    .padding(.top, 12)

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(DB.logoRed)
                            .padding(.vertical, 20)
                    }

                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            guard let lastItem = viewModel.searchResults.last else {
                                return
                            }
                            Task {
                                await viewModel.loadMoreIfNeeded(
                                    currentItem: lastItem
                                )
                            }
                        }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(DB.mutedText)
            Text(L10n.noSearchResults)
                .font(.system(size: 14))
                .foregroundColor(DB.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func searchErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(DB.mutedText)
                .multilineTextAlignment(.center)

            Button(L10n.retry) {
                viewModel.retry()
            }
            .foregroundColor(DB.logoRed)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPlayer(_ drama: DramaItem) {
        appStore.navigationTarget = SeriesPlayerNav(
            drama: drama,
            startEpisode: max(1, drama.currentEpisode),
            sourceScene: "search"
        )
    }
}

#if DEBUG
#Preview("Search") {
    SearchView(
        searchRepository: MockSearchRepository(),
        discoveryRepository: MockHomeRepository()
    )
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
#endif
