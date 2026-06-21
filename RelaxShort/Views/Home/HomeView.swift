import SwiftUI

// MARK: - Home View (v9 — GeometryReader)

/// 首页 — 搜索/会员/金币通过本地状态驱动 push destination
struct HomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject private var viewModel: HomeViewModel
    private let rankingRepository: HomeRepositoryProtocol
    @State private var playerDrama: DramaItem?
    @State private var showVIP = false
    @State private var showReward = false

    init(viewModel: HomeViewModel, rankingRepository: HomeRepositoryProtocol = MockHomeRepository()) {
        self.viewModel = viewModel
        self.rankingRepository = rankingRepository
    }

    var body: some View {
        GeometryReader { geo in
            let topLift = min(max(geo.safeAreaInsets.top - 34, 0), 18)
            ZStack {
                DT.Color.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    DramaBoxSearchHeaderView(
                        onSearchTap: { NotificationCenter.default.post(name: .showSearch, object: nil) },
                        onVIPTap: { showVIP = true },
                        onRewardTap: { showReward = true }
                    )
                        .padding(.bottom, 0)
                    tabBar.padding(.bottom, 4)
                    TabView(selection: $viewModel.selectedTab) {
                        popularContent(containerW: geo.size.width).tag(0)
                        newTabContent(containerW: geo.size.width).tag(1)
                        rankingsTabContent.tag(2)
                        categoriesTabContent.tag(3)
                        animeTabContent(containerW: geo.size.width).tag(4)
                        homeVIPTabContent(containerW: geo.size.width).tag(5)
                        originalPlusTabContent(containerW: geo.size.width).tag(6)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .frame(width: geo.size.width)
                    .ignoresSafeArea(.container, edges: .bottom)
                }
                .padding(.top, -topLift)

                if viewModel.isLoading, !viewModel.hasContent { loadingView }
                else if let msg = viewModel.errorMessage, !viewModel.hasContent { errorView(message: msg) }
                else if !viewModel.hasContent, !viewModel.isLoading { emptyView }
            }
        }
        .onChange(of: playerDrama) { _, drama in
            guard let drama else { return }
            appStore.navigationTarget = SeriesPlayerNav(drama: drama, startEpisode: max(1, drama.currentEpisode))
            playerDrama = nil
        }
        .navigationDestination(isPresented: $showVIP) {
            VIPView()
        }
        .navigationDestination(isPresented: $showReward) {
            CoinRewardView(mode: .pushed)
        }
        .task { await viewModel.loadData() }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(viewModel.tabs.enumerated()), id: \.offset) { idx, tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                viewModel.selectedTab = idx
                                proxy.scrollTo(idx, anchor: .center)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(tab)
                                    .font(DT.Font.body(15, weight: .bold))
                                    .foregroundColor(viewModel.selectedTab == idx ? DT.Color.textPrimary : DT.Color.textSecondary)

                                Capsule()
                                    .fill(viewModel.selectedTab == idx ? DT.Color.textPrimary : Color.clear)
                                    .frame(width: 18, height: 2)
                            }
                            .padding(.horizontal, DT.Space.md)
                            .id(idx)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Space.pageH - DT.Space.md)
            }
            .onChange(of: viewModel.selectedTab) { _, newValue in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    // MARK: - Tab 0: Popular

    private func popularContent(containerW: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if !viewModel.fixedDramas.isEmpty { MarketingGrid(dramas: viewModel.fixedDramas, playerDrama: $playerDrama, containerW: containerW) }
                if !viewModel.featuredDramas.isEmpty { YouMightLikeSection(dramas: viewModel.featuredDramas, playerDrama: $playerDrama, containerW: containerW).padding(.top, 28) }
            }
            .padding(.bottom, 64)
        }
        .refreshable { await viewModel.loadData() }
    }

    // MARK: - Tab 1: New (Compact List)

    private func newTabContent(containerW: CGFloat) -> some View {
        let dramas = viewModel.dramasForNewTab
        return ScrollView(showsIndicators: false) {
            if !dramas.isEmpty {
                LazyVStack(spacing: DT.Space.sm) {
                    ForEach(dramas) { drama in
                        Button { playerDrama = drama } label: {
                            HStack(spacing: DT.Space.md) {
                                CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0,
                                    cornerRadius: 6, width: 72, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(drama.title)
                                        .font(.system(size: 15, weight: .medium)).foregroundColor(.white).lineLimit(1)
                                    HStack(spacing: 8) {
                                        Text(drama.category).font(.system(size: 12)).foregroundColor(DB.mutedText)
                                        Text("\(drama.episodeCount) EP").font(.system(size: 12)).foregroundColor(DB.mutedText)
                                        Text(drama.formattedViewCount).font(.system(size: 12)).foregroundColor(DB.mutedText)
                                    }
                                    Text(drama.synopsis)
                                        .font(.system(size: 12)).foregroundColor(DB.mutedText).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 28)).foregroundColor(DB.pink.opacity(0.8))
                            }
                            .padding(DT.Space.md)
                            .background(DB.panel).cornerRadius(DB.cardRadius)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
                .padding(.top, 12)
            }
            Color.clear.frame(height: 72)
        }
        .refreshable { await viewModel.loadData() }
    }

    // MARK: - Tab 2: Rankings

    private var rankingsTabContent: some View {
        RankView(playerDrama: $playerDrama, repository: rankingRepository)
    }

    // MARK: - Tab 3: Categories (Filters + 3-col grid)

    @State private var selectedCategory: DramaCategory = .all

    private var categoriesTabContent: some View {
        VStack(spacing: 0) {
            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Space.sm) {
                    ForEach(DramaCategory.allCases, id: \.rawValue) { category in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = category }
                        } label: {
                            Text(category.rawValue)
                                .font(.system(size: 13, weight: selectedCategory == category ? .bold : .regular))
                                .foregroundColor(selectedCategory == category ? .white : DB.mutedText)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(
                                    Capsule().fill(selectedCategory == category ? DB.pink : DB.panel)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
            }
            .padding(.top, DT.Space.sm).padding(.bottom, DT.Space.md)

            // Drama grid
            let dramas: [DramaItem] = {
                if selectedCategory == .all {
                    return featuredOrEmpty
                }
                let matches = viewModel.dramas(for: selectedCategory)
                return matches.isEmpty ? featuredOrEmpty : matches
            }()

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DT.Space.sm), count: 3),
                    spacing: DT.Space.md
                ) {
                    ForEach(dramas) { drama in
                        Button { playerDrama = drama } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0,
                                    cornerRadius: DB.posterRadius, width: DB.posterWidth, height: DB.posterHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
                                Text(drama.title).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                                Text("\(drama.episodeCount) EP").font(.system(size: 10)).foregroundColor(DB.mutedText)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
                Color.clear.frame(height: 72)
            }
        }
    }

    // MARK: - Tab 4: Anime

    private func animeTabContent(containerW: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            if !viewModel.dramasForAnimeTab.isEmpty {
                MasonryWaterfall(dramas: viewModel.dramasForAnimeTab, playerDrama: $playerDrama, containerW: containerW)
                    .padding(.top, 12)
            } else {
                VStack(spacing: DT.Space.md) {
                    Image(systemName: "tv")
                        .font(DT.Font.emptyIcon)
                        .foregroundColor(DT.Color.textTertiary)
                    Text(L10n.noAnime)
                        .font(DT.Font.bodyDefault)
                        .foregroundColor(DT.Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
            Color.clear.frame(height: 64)
        }
        .refreshable { await viewModel.loadData() }
    }

    // MARK: - Tab 5: VIP Content Channel

    private func homeVIPTabContent(containerW: CGFloat) -> some View {
        let vipDramas = MockData.homeVipRecommendations.isEmpty
            ? featuredOrEmpty.filter { $0.badge == .vip || $0.isHot }
            : MockData.homeVipRecommendations

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DT.Space.xl) {
                // Golden VIP theme banner
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: "#1A1410"), Color(hex: "#3D2B15"), Color(hex: "#5C3D1A")],
                        startPoint: .leading, endPoint: .trailing
                    )
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "crown.fill").foregroundColor(DB.gold)
                                Text("VIP Picks").font(.system(size: 20, weight: .bold)).foregroundColor(DB.gold)
                            }
                            Text("Exclusive content for members").font(.system(size: 13)).foregroundColor(DB.mutedText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DT.Space.pageH)
                }
                .frame(height: 100)
                .cornerRadius(DB.cardRadius)
                .padding(.horizontal, DT.Space.pageH)
                .padding(.top, DT.Space.sm)

                // VIP Picks grid
                Text("VIP Picks").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, DT.Space.pageH)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DT.Space.sm), count: 3),
                    spacing: DT.Space.md
                ) {
                    ForEach(Array(vipDramas.prefix(6))) { drama in
                        Button { playerDrama = drama } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0,
                                    cornerRadius: DB.posterRadius, width: DB.posterWidth, height: DB.posterHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
                                Text(drama.title).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)

                // Member-only Dramas
                if !MockData.memberOnlyDramas.isEmpty {
                    Text("Member-only Dramas").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, DT.Space.pageH)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DT.Space.sm) {
                            ForEach(MockData.memberOnlyDramas) { drama in
                                Button { playerDrama = drama } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0,
                                            cornerRadius: DB.posterRadius, width: 100, height: 150)
                                            .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
                                        Text(drama.title).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1).frame(width: 100)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DT.Space.pageH)
                    }
                }

                // CTA
                Button { showVIP = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                        Text("Unlock all VIP dramas").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(DB.gold).cornerRadius(DB.ctaRadius)
                }
                .padding(.horizontal, DT.Space.pageH)
            }
            .padding(.bottom, 64)
        }
        .refreshable { await viewModel.loadData() }
    }

    private var featuredOrEmpty: [DramaItem] {
        viewModel.featuredDramas.isEmpty ? MockData.homePopular : viewModel.featuredDramas
    }

    // MARK: - Tab 6: Original+

    private func originalPlusTabContent(containerW: CGFloat) -> some View {
        let dramas: [DramaItem] = viewModel.dramasForOriginalPlusTab.isEmpty
            ? Array(featuredOrEmpty.filter { $0.isHot }.prefix(12))
            : viewModel.dramasForOriginalPlusTab
        let originals = Array(dramas.prefix(6))
        let trending = Array(dramas.suffix(from: min(6, dramas.count)).prefix(6))

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DT.Space.xl) {
                // Banner
                ZStack {
                    LinearGradient(
                        colors: [DB.pink.opacity(0.3), DB.pink.opacity(0.05)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Original+").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                            Text("Exclusive original series").font(.system(size: 13)).foregroundColor(DB.mutedText)
                        }
                        Spacer()
                        Image(systemName: "play.rectangle.fill").font(.system(size: 32)).foregroundColor(DB.pink)
                    }
                    .padding(.horizontal, DT.Space.pageH)
                }
                .frame(height: 90).cornerRadius(DB.cardRadius)
                .padding(.horizontal, DT.Space.pageH).padding(.top, DT.Space.sm)

                // Exclusive Originals
                if !originals.isEmpty {
                    Text("Exclusive Originals").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, DT.Space.pageH)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: DT.Space.sm), count: 3),
                        spacing: DT.Space.md
                    ) {
                        ForEach(originals) { drama in
                            Button { playerDrama = drama } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0,
                                        cornerRadius: DB.posterRadius, width: DB.posterWidth, height: DB.posterHeight)
                                        .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
                                    Text(drama.title).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DT.Space.pageH)
                }

                // Trending Originals
                if !trending.isEmpty {
                    Text("Trending Originals").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, DT.Space.pageH)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: DT.Space.sm), count: 3),
                        spacing: DT.Space.md
                    ) {
                        ForEach(trending) { drama in
                            Button { playerDrama = drama } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0,
                                        cornerRadius: DB.posterRadius, width: DB.posterWidth, height: DB.posterHeight)
                                        .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
                                    Text(drama.title).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DT.Space.pageH)
                }
            }
            .padding(.bottom, 64)
        }
        .refreshable { await viewModel.loadData() }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: DT.Space.lg) { ProgressView().tint(DT.brandPink).scaleEffect(1.2); Text(L10n.loading).font(DT.Font.caption).foregroundColor(DT.Color.textSecondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: DT.Space.lg) {
            Image(systemName: "wifi.slash").font(DT.Font.emptyIcon).foregroundColor(DT.Color.textTertiary)
            Text(message).font(DT.Font.bodyDefault).foregroundColor(DT.Color.textSecondary).multilineTextAlignment(.center).padding(.horizontal, DT.Space.xxl)
            Button { Task { await viewModel.loadData() } } label: {
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "arrow.clockwise").font(DT.Font.body(14)); Text(L10n.retry).font(DT.Font.button)
                }.foregroundColor(DT.brandPink).padding(.horizontal, DT.Space.xl).padding(.vertical, DT.Space.sm)
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.md).stroke(DT.brandPink, lineWidth: 1))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: DT.Space.lg) {
            Image(systemName: "play.rectangle.on.rectangle").font(DT.Font.emptyIcon).foregroundColor(DT.Color.textTertiary)
            Text(L10n.noContent).font(DT.Font.bodyDefault).foregroundColor(DT.Color.textSecondary)
            Text(L10n.pullToRefresh).font(DT.Font.caption).foregroundColor(DT.Color.textTertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DramaBoxSearchHeader (NotificationCenter triggers)

/// 首页顶部搜索栏 — 接受闭包替代 NotificationCenter
private struct DramaBoxSearchHeaderView: View {
    private let btnH: CGFloat = 34
    var onSearchTap: () -> Void = {}
    var onVIPTap: () -> Void = {}
    var onRewardTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onSearchTap()
            } label: {
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "magnifyingglass").font(DT.Font.caption).foregroundColor(DT.Color.textSecondary)
                    Text(L10n.homeSearchPlaceholder).font(DT.Font.body(14)).foregroundColor(DT.Color.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, DT.Space.md).frame(height: btnH)
                .background(DT.Color.textPrimary.opacity(0.12)).cornerRadius(4)
            }
            .buttonStyle(.plain)

            Button {
                onVIPTap()
            } label: {
                AnimatedPromoButton(symbol: "crown.fill", badge: "-25%", tint: Color(red: 1, green: 0.82, blue: 0.15), delay: 0)
            }
            .buttonStyle(.plain)

            Button {
                onRewardTap()
            } label: {
                AnimatedPromoButton(symbol: "gift.fill", badge: "+150", tint: Color(red: 0.9, green: 0.2, blue: 0.2), delay: 0.3)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, DT.Space.pageH)
        .padding(.trailing, DT.Space.pageH)
        .padding(.top, 2).padding(.bottom, 2)
    }
}

// MARK: - Animated Promo Button (pure decoration, tap handled by parent)

private struct AnimatedPromoButton: View {
    let symbol: String
    let badge: String
    var tint: Color = DT.brandGold
    var delay: Double = 0
    @State private var anim = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)

            Text(badge)
                .font(.system(size: 7, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(DT.hotTag)
                .cornerRadius(3)
                .offset(x: 2, y: 2)
        }
        .frame(width: 42, height: 42, alignment: .center)
        .scaleEffect(anim ? 1.1 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(delay)) {
                anim = true
            }
        }
    }
}
