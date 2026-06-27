import SwiftUI

/// Search 输入为空时展示最近搜索和三个真实榜单。
struct SearchDefaultView: View {
    @ObservedObject var viewModel: SearchDefaultViewModel
    let searchHistory: [String]
    let onHistorySelected: (String) -> Void
    let onClearHistory: () -> Void
    let onDramaSelected: (DramaItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !visibleSearchTerms.isEmpty {
                searchTermsSection
            }

            rankTabs

            Group {
                if viewModel.isLoading {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage {
                    errorState(errorMessage)
                } else {
                    SearchRankingPager(
                        viewModel: viewModel,
                        onDramaSelected: onDramaSelected
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DT.Color.bgPrimary)
        .task {
            await viewModel.loadData()
        }
    }

    private var visibleSearchTerms: [String] {
        searchHistory.isEmpty ? viewModel.trendingSearches : searchHistory
    }

    private var searchTermsTitle: String {
        searchHistory.isEmpty ? L10n.trendingSearches : L10n.recentSearches
    }

    private var searchTermsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(searchTermsTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                if !searchHistory.isEmpty {
                    Button(action: onClearHistory) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(DB.mutedText)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.clearSearchHistory)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleSearchTerms, id: \.self) { term in
                        Button {
                            onHistorySelected(term)
                        } label: {
                            Text(term)
                                .font(.system(size: 13))
                                .foregroundColor(DB.mutedText)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Color.white.opacity(0.08))
                                .clipShape(
                                    RoundedRectangle(cornerRadius: DB.posterRadius)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var rankTabs: some View {
        HStack(spacing: 0) {
            ForEach(SearchRankTheme.allCases) { theme in
                Button {
                    viewModel.selectTheme(theme)
                } label: {
                    Text(theme.title)
                        .font(
                            .system(
                                size: 16,
                                weight: viewModel.selectedTheme == theme
                                    ? .semibold
                                    : .regular
                            )
                        )
                        .foregroundColor(
                            viewModel.selectedTheme == theme
                                ? DB.logoRed
                                : DB.mutedText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var loadingState: some View {
        ProgressView()
            .tint(DB.logoRed)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(DB.mutedText)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(DB.mutedText)
                .multilineTextAlignment(.center)

            Button(L10n.retry) {
                Task {
                    await viewModel.loadData()
                }
            }
            .foregroundColor(DB.logoRed)
        }
        .padding(.horizontal, 24)
    }
}

#if DEBUG
#Preview("Search Default") {
    let repository = MockSearchRepository()
    SearchDefaultView(
        viewModel: SearchDefaultViewModel(
            homeRepository: MockHomeRepository(),
            searchRepository: repository
        ),
        searchHistory: ["Jiang", "CEO"],
        onHistorySelected: { _ in },
        onClearHistory: {},
        onDramaSelected: { _ in }
    )
    .preferredColorScheme(.dark)
}
#endif
