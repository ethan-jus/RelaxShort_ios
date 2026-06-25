import SwiftUI

// MARK: - Favorites View

/// My List 页 — 复刻 DramaBox
/// 顶部「Following | History」分段控制器，卡片式列表，未登录弹出引导弹窗

struct FavoritesView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var appStore: AppStore
    @StateObject private var viewModel: FavoritesViewModel

    @State private var selectedSegment: MyListSegment = .following

    enum MyListSegment: String, CaseIterable {
        case following = "Following"
        case history = "History"
    }

    init(viewModel: FavoritesViewModel? = nil) {
        let vm = viewModel ?? FavoritesViewModel(repository: MockFavoritesRepository())
        _viewModel = StateObject(wrappedValue: vm)
    }

    @State private var showLoginView = false

    var body: some View {
        ZStack {
            DB.black.ignoresSafeArea()

            if authStore.isLoggedIn {
                loggedInContent
            } else {
                notLoggedInContent
            }
        }
        .navigationTitle("My List")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if authStore.isLoggedIn {
                Task { await viewModel.loadData() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    viewModel.presentLoginModal()
                }
            }
        }
        .onChange(of: authStore.isLoggedIn) { _, newValue in
            if newValue {
                viewModel.dismissLoginModal()
                Task { await viewModel.loadData() }
            }
        }
        .overlay {
            if viewModel.showLoginModal && !authStore.isLoggedIn {
                LoginGuideModal(
                    isPresented: $viewModel.showLoginModal,
                    onNavigateToLogin: { showLoginView = true }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeOut(duration: 0.25), value: viewModel.showLoginModal)
            }
        }
        .sheet(isPresented: $showLoginView) {
            LoginView()
        }
    }

    // MARK: - Logged In Content

    private var loggedInContent: some View {
        VStack(spacing: 0) {
            // Segmented control
            HStack(spacing: 0) {
                ForEach(MyListSegment.allCases, id: \.rawValue) { segment in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedSegment = segment }
                    } label: {
                        VStack(spacing: 6) {
                            Text(segment.rawValue)
                                .font(.system(size: 15, weight: selectedSegment == segment ? .bold : .regular))
                                .foregroundColor(selectedSegment == segment ? .white : DB.mutedText)
                            Capsule()
                                .fill(selectedSegment == segment ? DB.pink : Color.clear)
                                .frame(width: 24, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, DT.Space.pageH)
            .padding(.top, 8)

            if viewModel.isLoading {
                Spacer()
                ProgressView().tint(DB.pink)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: DT.Space.xl) {
                        if selectedSegment == .following {
                            followingContent
                        } else {
                            historyContent
                        }
                        recommendedSection
                    }
                    .padding(.bottom, DT.Space.xxl)
                }
            }
        }
    }

    // MARK: - Following Content

    private var followingContent: some View {
        let followed = MockData.myListFollowing
        return VStack(alignment: .leading, spacing: DT.Space.md) {
            if followed.isEmpty {
                emptyStateView(message: "No following yet")
            } else {
                ForEach(followed) { drama in
                    HStack(spacing: DT.Space.md) {
                        CoverImageView(
                            url: drama.coverURL, aspectRatio: 2.0/3.0,
                            cornerRadius: DB.posterRadius, width: 72, height: 96
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(drama.title)
                                .font(.system(size: 15, weight: .medium)).foregroundColor(.white).lineLimit(1)
                            Text("\(drama.episodeCount) EP · \(drama.category)")
                                .font(.system(size: 12)).foregroundColor(DB.mutedText)
                            if let region = drama.regionTag {
                                Text(region)
                                    .font(.system(size: 11)).foregroundColor(DB.gold)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12)).foregroundColor(DB.mutedText)
                    }
                    .padding(DT.Space.md)
                    .background(DB.panel)
                    .clipShape(RoundedRectangle(cornerRadius: DB.cardRadius))
                }
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.md)
    }

    // MARK: - History Content

    private var historyContent: some View {
        let history = MockData.moreWatchHistory
        return VStack(spacing: DT.Space.sm) {
            if history.isEmpty {
                emptyStateView(message: "No watch history")
            } else {
                ForEach(history) { record in
                    WatchHistoryCard(record: record)
                }
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.md)
    }

    // MARK: - Recommended Section

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: DT.Space.md) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(DB.pink).frame(width: 3, height: 18)
                Text("Recommended For You").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DT.Space.sm), count: 3),
                spacing: DT.Space.md
            ) {
                ForEach(MockData.homePopular.prefix(6)) { drama in
                    VStack(alignment: .leading, spacing: 4) {
                        CoverImageView(
                            url: drama.coverURL, aspectRatio: 2.0/3.0,
                            cornerRadius: DB.posterRadius, width: DB.posterWidth, height: DB.posterHeight
                        )
                        Text(drama.title)
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.lg)
    }

    // MARK: - Not Logged In Content

    private var notLoggedInContent: some View {
        VStack(spacing: DT.Space.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DT.brandPink.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "bookmark")
                    .font(DT.Font.body(44))
                    .foregroundColor(DT.brandPink)
            }

            Text(L10n.loginToViewFavorites)
                .font(DT.Font.body(17, weight: .semibold))
                .foregroundColor(DT.Color.textPrimary)

            Text(L10n.loginToSync)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Space.xxl)

            Button {
                viewModel.presentLoginModal()
            } label: {
                Text(L10n.loginNow)
                    .font(DT.Font.body(15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 44)
                    .background(DT.brandPink)
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }

    // MARK: - Empty State

    private func emptyStateView(message: String) -> some View {
        VStack(spacing: DT.Space.lg) {
            Spacer().frame(height: 60)
            ZStack {
                Circle()
                    .fill(DT.Color.overlaySubtle)
                    .frame(width: 80, height: 80)
                Image(systemName: "tray")
                    .font(DT.Font.body(32))
                    .foregroundColor(DT.Color.textTertiary)
            }
            Text(message)
                .font(DT.Font.bodyDefault)
                .foregroundColor(DT.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Watch History Card

/// 观看历史卡片 — 水平布局，含封面、标题、进度、集数
struct WatchHistoryCard: View {
    let record: WatchHistoryItem

    var body: some View {
        HStack(spacing: DT.Space.md) {
            // Cover 80×106
            CoverImageView(
                url: record.drama.coverURL,
                aspectRatio: DT.Layout.cardAspectRatio,
                cornerRadius: DB.posterRadius,
                width: 80,
                height: 106
            )
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

            // Info
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(record.drama.title)
                    .font(DT.Font.body(15, weight: .medium))
                    .foregroundColor(DT.Color.textPrimary)
                    .lineLimit(1)

                // Progress bar + percentage
                HStack(spacing: DT.Space.sm) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(DT.Color.overlaySubtle)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(DT.brandPink)
                                .frame(width: geo.size.width * CGFloat(record.progress), height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text(progressText)
                        .font(DT.Font.small)
                        .foregroundColor(DT.brandPink)
                }

                HStack(spacing: 2) {
                    Text(L10n.episodeProgress(record.currentEpisode, record.drama.episodeCount))
                        .font(DT.Font.small)
                        .foregroundColor(DT.Color.textTertiary)

                    Spacer().frame(width: 6)

                    Text(record.relativeTime)
                        .font(DT.Font.small)
                        .foregroundColor(DT.Color.textTertiary)
                }

                Spacer().frame(height: 2)
            }
        }
        .padding(DT.Space.md)
        .background(DT.Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }

    private var progressText: String {
        String(format: "%.0f%%", record.progress * 100)
    }
}

// MARK: - Login Guide Modal

/// 未登录引导弹窗 — 复刻 DramaBox
/// Google / Apple 登录入口 + 协议条款
struct LoginGuideModal: View {
    @Binding var isPresented: Bool
    var onNavigateToLogin: (() -> Void)?

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            // Modal card
            VStack(spacing: DT.Space.lg) {
                // Top decorative icon
                ZStack {
                    Circle()
                        .fill(DT.brandPink.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "bookmark.fill")
                        .font(DT.Font.body(28))
                        .foregroundColor(DT.brandPink)
                }

                // Title
                Text(L10n.saveYourList)
                    .font(DT.Font.body(20, weight: .bold))
                    .foregroundColor(DT.Color.textPrimary)

                // Description
                Text(L10n.loginRecommendation)
                    .font(DT.Font.bodyDefault)
                    .foregroundColor(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DT.Space.sm)

                // Google Login
                Button {
                    isPresented = false
                    onNavigateToLogin?()
                } label: {
                    HStack(spacing: DT.Space.sm) {
                        Image(systemName: "g.circle.fill")
                            .font(DT.Font.body(20))
                        Text(L10n.loginWithGoogle)
                            .font(DT.Font.body(15, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: DT.Layout.ctaButtonHeight)
                    .background(.white)
                    .clipShape(Capsule())
                }

                // Apple Login
                Button {
                    isPresented = false
                    onNavigateToLogin?()
                } label: {
                    HStack(spacing: DT.Space.sm) {
                        Image(systemName: "apple.logo")
                            .font(DT.Font.body(20))
                        Text(L10n.loginWithApple)
                            .font(DT.Font.body(15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: DT.Layout.ctaButtonHeight)
                    .background(.black)
                    .clipShape(Capsule())
                }

                // Terms
                Text(L10n.loginAgreement)
                    .font(DT.Font.small)
                    .foregroundColor(DT.Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(DT.Space.xxl)
            .background(DT.Color.bgModal)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl))
            .padding(.horizontal, DT.Space.xl)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct FavoritesView_Previews: PreviewProvider {
    static var previews: some View {
        let authStore = AuthStore()
        authStore.isLoggedIn = true
        authStore.currentUser = User(
            id: "preview",
            nickname: "Test",
            isVip: true,
            vipExpireDate: Date().addingTimeInterval(86400 * 30),
            coinBalance: 100,
            followedCount: 0
        )
        authStore.isVip = true
        authStore.vipExpireDate = Date().addingTimeInterval(86400 * 30)
        authStore.coinBalance = 100
        authStore.loginMethod = .google
        return FavoritesView()
            .environmentObject(authStore)
            .preferredColorScheme(.dark)
    }
}
#endif
