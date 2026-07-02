import SwiftUI

// MARK: - My List View

struct FavoritesView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var appStore: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: FavoritesViewModel

    init(viewModel: FavoritesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !authStore.isLoggedIn {
                loggedOutGuide
            } else {
                VStack(spacing: 0) {
                    segmentHeader
                    contentArea
                }
            }
        }
        .onAppear { handleAppear() }
        .onDisappear { handleDisappear() }
        .onChange(of: appStore.selectedTab) { _, tab in
            guard tab == .myList, authStore.isLoggedIn else { return }
            Task { await viewModel.refreshUserData() }
        }
        .onChange(of: viewModel.isEditing) { _, editing in
            appStore.isBottomTabBarHidden = editing
        }
        .onChange(of: authStore.isLoggedIn) { _, loggedIn in
            if loggedIn {
                Task { await viewModel.refreshUserData() }
            } else {
                viewModel.cancelEditing()
                appStore.isBottomTabBarHidden = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  appStore.selectedTab == .myList,
                  authStore.isLoggedIn else { return }
            Task { await viewModel.refreshUserData() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isEditing { removeBar }
        }
        .sheet(isPresented: $viewModel.showLoginModal) {
            LoginView().environmentObject(authStore)
        }
    }

    // MARK: - Logged Out

    private var loggedOutGuide: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.star").font(.system(size: 44)).foregroundColor(DB.mutedText)
            Text(L10n.myListLoginGuide).font(.system(size: 15)).foregroundColor(DB.mutedText)
            Button(L10n.myListSignIn) { viewModel.presentLoginModal() }
                .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 32).padding(.vertical, 10)
                .background(DB.logoRed).cornerRadius(6)
        }
    }

    // MARK: - Segment Header

    private var segmentHeader: some View {
        HStack(spacing: 24) {
            if viewModel.isEditing {
                Text(L10n.myListChoose)
                    .font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Button(L10n.commonCancel) { viewModel.cancelEditing() }
                    .font(.system(size: 16)).foregroundColor(.white)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                ForEach(FavoritesViewModel.Segment.allCases, id: \.self) { seg in
                    Button { viewModel.selectedSegment = seg } label: {
                        VStack(spacing: 6) {
                            Text(seg == .following ? L10n.myListFollowing : L10n.myListHistory)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(viewModel.selectedSegment == seg ? .white : Color.white.opacity(0.55))
                            Capsule()
                                .fill(viewModel.selectedSegment == seg ? Color.white : Color.clear)
                                .frame(width: 28, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { viewModel.enterEditing() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18)).foregroundColor(.white)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(!viewModel.canEdit)
                .opacity(viewModel.canEdit ? 1 : 0.35)
                .accessibilityLabel(L10n.myListChoose)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        GeometryReader { geo in
            let coverW = min(max(geo.size.width * 0.22, 72), 92)
            let coverH = coverW * 1.5

            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.selectedSegment == .following {
                        bookmarkList(coverW: coverW, coverH: coverH, containerW: geo.size.width)
                    } else {
                        historyList(coverW: coverW, coverH: coverH, containerW: geo.size.width)
                    }

                    // Most Trending
                    trendingSection(containerW: geo.size.width)
                }
            }
            .padding(.bottom, appStore.isBottomTabBarHidden ? 0 : 0)
        }
    }

    // MARK: - Bookmark List

    @ViewBuilder
    private func bookmarkList(coverW: CGFloat, coverH: CGFloat, containerW: CGFloat) -> some View {
        if viewModel.bookmarks.isEmpty && !viewModel.isBookmarksLoading {
            emptyState(L10n.myListEmptyFollowing)
        } else {
            ForEach(viewModel.bookmarks) { drama in
                let history = viewModel.historyItem(for: drama.id)
                myListRow(
                    drama: drama,
                    episodeNumber: history?.currentEpisode ?? max(drama.currentEpisode, 1),
                    totalEpisodes: max(drama.episodeCount, 1),
                    progress: history.map { $0.progress } ?? 0,
                    coverW: coverW, coverH: coverH,
                    isEditing: viewModel.isEditing,
                    isSelected: viewModel.selectedItemIDs.contains(drama.id),
                    onTap: { handleBookmarkTap(drama, history: history) },
                    onToggle: { viewModel.toggleSelection(id: drama.id) }
                )
            }
            if !viewModel.bookmarks.isEmpty {
                Color.clear.frame(height: 1).onAppear {
                    Task { await viewModel.loadMoreBookmarks() }
                }
            }
            if viewModel.isBookmarksLoading { loadingFooter }
            if let err = viewModel.bookmarksError { errorFooter(err) { Task { await viewModel.retryBookmarks() } } }
        }
    }

    // MARK: - History List

    @ViewBuilder
    private func historyList(coverW: CGFloat, coverH: CGFloat, containerW: CGFloat) -> some View {
        if viewModel.watchHistory.isEmpty && !viewModel.isHistoryLoading {
            emptyState(L10n.myListEmptyHistory)
        } else {
            ForEach(viewModel.watchHistory) { item in
                myListRow(
                    drama: item.drama,
                    episodeNumber: item.currentEpisode,
                    totalEpisodes: item.drama.episodeCount,
                    progress: item.progress,
                    coverW: coverW, coverH: coverH,
                    isEditing: viewModel.isEditing,
                    isSelected: viewModel.selectedItemIDs.contains(item.drama.id),
                    onTap: { handleHistoryTap(item) },
                    onToggle: { viewModel.toggleSelection(id: item.drama.id) }
                )
            }
            if !viewModel.watchHistory.isEmpty {
                Color.clear.frame(height: 1).onAppear {
                    Task { await viewModel.loadMoreHistory() }
                }
            }
            if viewModel.isHistoryLoading { loadingFooter }
            if let err = viewModel.historyError { errorFooter(err) { Task { await viewModel.retryHistory() } } }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func myListRow(
        drama: DramaItem, episodeNumber: Int, totalEpisodes: Int, progress: Double,
        coverW: CGFloat, coverH: CGFloat,
        isEditing: Bool, isSelected: Bool,
        onTap: @escaping () -> Void, onToggle: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            if isEditing {
                selectionCircle(isSelected: isSelected, coverH: coverH)
                    .onTapGesture { onToggle() }
                    .padding(.trailing, 10)
            }

            Button(action: { isEditing ? onToggle() : onTap() }) {
                HStack(alignment: .top, spacing: 14) {
                    // Poster
                    ZStack(alignment: .bottom) {
                        CoverImageView(url: drama.coverURL, cornerRadius: DB.posterRadius, width: coverW, height: coverH)
                            .frame(width: coverW, height: coverH)
                            .cornerRadius(DB.posterRadius)
                        if isSelected {
                            Color.black.opacity(0.45).cornerRadius(DB.posterRadius)
                        }
                        // Progress bar
                        Rectangle().fill(Color(white: 0.30)).frame(height: 3)
                        Rectangle().fill(DB.logoRed)
                            .frame(width: coverW * CGFloat(clamp(progress, 0, 1)), height: 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: coverW, height: coverH)

                    // Text
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drama.title).font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white).lineLimit(1)
                        Text(dramaCategoryTags(drama)).font(.system(size: 15))
                            .foregroundColor(Color.white.opacity(0.45)).lineLimit(1)
                        Text(L10n.myListEpisodeProgress(episodeNumber, totalEpisodes)).font(.system(size: 16))
                            .foregroundColor(Color.white.opacity(0.60))
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    // MARK: - Trending

    @ViewBuilder
    private func trendingSection(containerW: CGFloat) -> some View {
        if let err = viewModel.trendingError {
            VStack(spacing: 8) {
                Text(err).font(.system(size: 14)).foregroundColor(DB.mutedText)
                Button(L10n.commonRetry) { Task { await viewModel.loadTrending() } }.foregroundColor(DB.logoRed)
            }.padding(.top, 32)
        } else if !viewModel.trendingEntries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.myListMostTrending).font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white).padding(.horizontal, 16).padding(.top, 32)
                trendingGrid(containerW: containerW)
                if viewModel.topTrendingEntries.count >= 6 {
                    Text(L10n.myListNoMoreContent).font(.system(size: 14)).foregroundColor(DB.mutedText)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func trendingGrid(containerW: CGFloat) -> some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        let cardW = (containerW - 42) / 3
        LazyVGrid(columns: cols, spacing: 18) {
            ForEach(viewModel.topTrendingEntries) { entry in
                Button {
                    appStore.navigationTarget = SeriesPlayerNav(drama: entry.drama, startEpisode: max(entry.drama.currentEpisode, 1), sourceScene: "my_list_trending")
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ZStack(alignment: .topLeading) {
                            CoverImageView(url: entry.drama.coverURL, cornerRadius: DB.posterRadius, width: cardW, height: cardW * 1.5)
                                .frame(width: cardW, height: cardW * 1.5)
                            Text("\(entry.rankPosition)")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(rankBadgeColor(entry.rankPosition))
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: DB.posterRadius))
                        }
                        .frame(width: cardW, height: cardW * 1.5)
                        Text(entry.drama.title).font(.system(size: 14)).foregroundColor(.white).lineLimit(2)
                            .frame(height: 36, alignment: .top)
                        Text(entry.drama.category).font(.system(size: 13)).foregroundColor(DB.mutedText).lineLimit(1)
                            .frame(height: 18, alignment: .top)
                    }
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 16)
    }

    private func rankBadgeColor(_ rank: Int) -> Color {
        switch rank { case 1: .orange; case 2: .green; case 3: .blue; default: .gray }
    }

    // MARK: - Helpers

    private var loadingFooter: some View {
        ProgressView().tint(DB.logoRed).padding(.vertical, 16).frame(maxWidth: .infinity)
    }

    private func errorFooter(_ msg: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(msg).font(.system(size: 14)).foregroundColor(DB.mutedText)
            Button(L10n.commonRetry, action: retry).foregroundColor(DB.logoRed)
        }.padding(.vertical, 16)
    }

    private func emptyState(_ msg: String) -> some View {
        Text(msg).font(.system(size: 15)).foregroundColor(DB.mutedText)
            .frame(maxWidth: .infinity).padding(.top, 80)
    }

    @ViewBuilder
    private func selectionCircle(isSelected: Bool, coverH: CGFloat) -> some View {
        Circle()
            .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.8), lineWidth: 2)
            .background(Circle().fill(isSelected ? DB.logoRed : Color.clear))
            .overlay { if isSelected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white) } }
            .frame(width: 22, height: 22)
            .frame(height: coverH, alignment: .center)
            .accessibilityValue(isSelected ? L10n.myListSelectionSelected : L10n.myListSelectionUnselected)
    }

    private func dramaCategoryTags(_ drama: DramaItem) -> String {
        let parts = [drama.category].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func clamp(_ val: Double, _ lo: Double, _ hi: Double) -> Double { min(max(val, lo), hi) }

    // MARK: - Remove Bar

    private var removeBar: some View {
        VStack(spacing: 0) {
            if let err = viewModel.removalError {
                Text(err).font(.system(size: 13)).foregroundColor(DB.logoRed).padding(.horizontal, 16).padding(.vertical, 4)
            }
            Divider().background(Color.white.opacity(0.5))
            HStack {
                Spacer()
                if viewModel.isRemoving {
                    ProgressView().tint(DB.logoRed)
                } else {
                    Button {
                        Task { await viewModel.removeSelectedItems() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text(L10n.myListRemove)
                        }
                        .font(.system(size: 16))
                        .foregroundColor(viewModel.selectedItemIDs.isEmpty ? Color.white.opacity(0.3) : .white)
                    }
                    .disabled(viewModel.selectedItemIDs.isEmpty || viewModel.isRemoving)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(L10n.myListRemoveSelectedCount(viewModel.selectedItemIDs.count))
                }
            }
            .padding(.horizontal, 16)
            .frame(
                height: DramaBoxBottomTabBar.totalHeight
                    + UIApplication.safeAreaInsets.bottom
                    - 1
            )
        }
        .background(Color.black)
    }

    // MARK: - Actions

    private func handleAppear() {
        if authStore.isLoggedIn {
            Task { await viewModel.loadAll() }
        }
    }

    private func handleDisappear() {
        viewModel.cancelEditing()
        appStore.isBottomTabBarHidden = false
    }

    private func handleBookmarkTap(_ drama: DramaItem, history: WatchHistoryItem?) {
        if let h = history {
            appStore.navigationTarget = SeriesPlayerNav(
                drama: drama, startEpisode: h.currentEpisode,
                episodeID: h.episodeID, resumeTime: h.resumeTime, sourceScene: "my_list_following")
        } else {
            appStore.navigationTarget = SeriesPlayerNav(
                drama: drama, startEpisode: max(drama.currentEpisode, 1), sourceScene: "my_list_following")
        }
    }

    private func handleHistoryTap(_ item: WatchHistoryItem) {
        appStore.navigationTarget = SeriesPlayerNav(
            drama: item.drama, startEpisode: item.currentEpisode,
            episodeID: item.episodeID, resumeTime: item.resumeTime, sourceScene: "my_list_history")
    }
}
