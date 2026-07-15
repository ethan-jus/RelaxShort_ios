import SwiftUI
import UIKit

private struct CategoryScrollOffsetReader: UIViewRepresentable {
    @Binding var offsetY: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetY: $offsetY)
    }

    func makeUIView(context: Context) -> UIView {
        let view = ObserverView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        (view as? ObserverView)?.coordinator = context.coordinator
        context.coordinator.attach(to: view.nearestVerticalScrollView)
    }

    final class ObserverView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attach()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attach()
        }

        private func attach() {
            coordinator?.attach(to: nearestVerticalScrollView)
        }
    }

    final class Coordinator: NSObject {
        private var offsetY: Binding<CGFloat>
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(offsetY: Binding<CGFloat>) {
            self.offsetY = offsetY
        }

        func attach(to scrollView: UIScrollView?) {
            guard let scrollView, self.scrollView !== scrollView else { return }
            self.scrollView = scrollView
            publishOffset(scrollView.contentOffset.y)
            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.publishOffset(scrollView.contentOffset.y)
            }
        }

        /// UIViewRepresentable 的 update/layout 周期内同步写 SwiftUI Binding 会触发未定义行为警告。
        /// 延迟到下一轮主队列，并过滤无变化值，避免重复刷新。
        private func publishOffset(_ value: CGFloat) {
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.offsetY.wrappedValue - value) > 0.5 else { return }
                self.offsetY.wrappedValue = value
            }
        }
    }
}

private extension UIView {
    var nearestVerticalScrollView: UIScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                let isVertical = scrollView.alwaysBounceVertical || scrollView.contentSize.height > scrollView.bounds.height
                if isVertical {
                    return scrollView
                }
            }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Home View (v9 — GeometryReader)

/// 首页 — 搜索/会员/金币通过本地状态驱动 push destination
struct HomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var dependencies: DependencyContainer
    @ObservedObject private var viewModel: HomeViewModel
    private let rankingRepository: HomeRepositoryProtocol
    @State private var playerDrama: DramaItem?
    @State private var showVIP = false
    @State private var showReward = false
    /// Categories 三行筛选状态。
    @State private var selectedLanguage: String = "All"
    @State private var selectedGenre: String = "All"
    @State private var selectedPayment: String = "All"
    @State private var categoryScrollOffsetY: CGFloat = 0
    @State private var isCategoryFilterOverlayPresented = false
    @State private var selectedRankCategory: RankCategory = .hot

    private enum HomeMetrics {
        static let chromeTopGap: CGFloat = 8
        static let tabVerticalPadding: CGFloat = 14
        static let searchBarHeight: CGFloat = 36
        static let categorySummaryHeight: CGFloat = 44
        static let categoryFilterHideThreshold: CGFloat = 155
    }

    init(viewModel: HomeViewModel, rankingRepository: HomeRepositoryProtocol) {
        self.viewModel = viewModel
        self.rankingRepository = rankingRepository
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                homeBackdrop.ignoresSafeArea()
                VStack(spacing: 0) {
                    DramaBoxSearchHeaderView(
                        onSearchTap: { NotificationCenter.default.post(name: .showSearch, object: nil) },
                        onVIPTap: { showVIP = true },
                        onRewardTap: { showReward = true }
                    )
                        .padding(.top, HomeMetrics.chromeTopGap)
                    tabBar.padding(.vertical, HomeMetrics.tabVerticalPadding)
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
                if viewModel.isLoading, !viewModel.hasContent { loadingView }
                else if let msg = viewModel.errorMessage, !viewModel.hasContent { errorView(message: msg) }
                else if !viewModel.hasContent, !viewModel.isLoading { emptyView }
            }
        }
        .onChange(of: playerDrama) { _, drama in
            guard let drama else { return }
            appStore.navigationTarget = SeriesPlayerNav(
                drama: drama,
                startEpisode: max(1, drama.currentEpisode),
                sourceScene: viewModel.selectedTab == 2 ? "rankings" : "home"
            )
            playerDrama = nil
        }
        .navigationDestination(isPresented: $showVIP) {
            MemberView(
                mode: .push,
                repository: dependencies.memberRepository
            )
        }
        .navigationDestination(isPresented: $showReward) {
            CoinRewardView(mode: .pushed)
        }
        .task { await viewModel.loadData() }
    }

    @ViewBuilder
    private var homeBackdrop: some View {
        if viewModel.selectedTab == 2 {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: selectedRankCategory.homeBackdropColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 270)

                DB.black
            }
        } else {
            DT.Color.bgPrimary
        }
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
                                    .font(DT.Font.body(17, weight: .bold))
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

    // MARK: - Tab 1: New

    private func newTabContent(containerW: CGFloat) -> some View {
        let dramas = viewModel.dramasForNewTab
        return ScrollView(showsIndicators: false) {
            if !dramas.isEmpty {
                LazyVStack(spacing: 16) {
                    ForEach(Array(dramas.enumerated()), id: \.element.id) { index, drama in
                        NewDramaRow(
                            drama: drama,
                            dateBadge: newDateBadge(for: index),
                            containerWidth: containerW,
                            onTap: { playerDrama = drama }
                        )
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
                .padding(.top, 6)
            }
            Color.clear.frame(height: 72)
        }
        .refreshable { await viewModel.loadData() }
    }

    private func newDateBadge(for index: Int) -> String {
        if index < 2 { return "Today" }
        return index < 5 ? "06/21" : "06/20"
    }

    // MARK: - Tab 2: Rankings

    private var rankingsTabContent: some View {
        RankView(
            playerDrama: $playerDrama,
            repository: rankingRepository,
            onCategoryChange: { selectedRankCategory = $0 }
        )
    }

    // MARK: - Categories Filter Model

    private struct CategoryFilterOption: Identifiable, Equatable {
        let id: String
        let title: String
    }

    // MARK: - Tab 3: Categories

    /// 语言行：All + 常用语言码映射
    private var languageOptions: [CategoryFilterOption] {
        [
            CategoryFilterOption(id: "All", title: "All"),
            CategoryFilterOption(id: "local", title: "Local"),
            CategoryFilterOption(id: "zh-Hans", title: "Chinese"),
            CategoryFilterOption(id: "ko", title: "Korean"),
            CategoryFilterOption(id: "ja", title: "Japanese"),
            CategoryFilterOption(id: "es", title: "Spanish"),
            CategoryFilterOption(id: "others", title: "Others"),
            CategoryFilterOption(id: "en", title: "English")
        ]
    }

    private var genreOptions: [CategoryFilterOption] {
        var opts = [CategoryFilterOption(id: "All", title: "All")]
        for cat in viewModel.categories {
            opts.append(CategoryFilterOption(id: cat.code, title: cat.title))
        }
        return opts
    }

    /// 付费行：All / Paid / Members Only / Free（前端过滤）
    private var paymentOptions: [CategoryFilterOption] {
        [
            CategoryFilterOption(id: "All", title: "All"),
            CategoryFilterOption(id: "paid", title: "Paid"),
            CategoryFilterOption(id: "member", title: "Members Only"),
            CategoryFilterOption(id: "free", title: "Free")
        ]
    }

    private var languageRow: some View {
        catFilterRow(options: languageOptions, selected: $selectedLanguage)
    }

    private var genreRow: some View {
        catFilterRow(options: genreOptions, selected: .init(
            get: { selectedGenre },
            set: { newVal in
                selectedGenre = newVal
                if newVal == "All" {
                    viewModel.categoryDramas = []
                } else if let idx = viewModel.categories.firstIndex(where: { $0.code == newVal }) {
                    Task { await viewModel.selectCategory(at: idx) }
                }
            }
        ))
    }

    private var paymentRow: some View {
        catFilterRow(options: paymentOptions, selected: $selectedPayment)
    }

    private var categorySelectedSummary: String {
        let selectedTitles = [
            selectedLanguage == "All" ? nil : title(for: selectedLanguage, in: languageOptions),
            selectedGenre == "All" ? nil : title(for: selectedGenre, in: genreOptions),
            selectedPayment == "All" ? nil : title(for: selectedPayment, in: paymentOptions)
        ].compactMap { $0 }

        return selectedTitles.isEmpty ? "Categories" : selectedTitles.joined(separator: " · ")
    }

    private func title(for id: String, in options: [CategoryFilterOption]) -> String {
        options.first(where: { $0.id == id })?.title ?? "All"
    }

    private var categoriesTabContent: some View {
        GeometryReader { _ in
            let filterHideThreshold = HomeMetrics.categoryFilterHideThreshold
            let filterIsFullyHidden = categoryScrollOffsetY >= filterHideThreshold

            ZStack(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    CategoryScrollOffsetReader(offsetY: $categoryScrollOffsetY)
                        .frame(width: 1, height: 1)

                    categoryFilterContent

                    categoryGridStateContent
                }
                .onChange(of: categoryScrollOffsetY) { _, offset in
                    if offset < filterHideThreshold {
                        isCategoryFilterOverlayPresented = false
                    }
                }
                .refreshable { await viewModel.loadData() }

                if filterIsFullyHidden, !isCategoryFilterOverlayPresented {
                    categorySummaryHeader
                }

                if isCategoryFilterOverlayPresented {
                    categoryFilterOverlay
                }
            }
        }
    }

    private var categoryFilterContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            languageRow
            genreRow
            paymentRow
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.sm)
        .padding(.bottom, 18)
    }

    private var categorySummaryHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCategoryFilterOverlayPresented = true
            }
        } label: {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(categorySelectedSummary)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DB.logoRed)
                    .lineLimit(1)
                Text("▼")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DB.logoRed)
                Spacer(minLength: 0)
            }
            .frame(height: HomeMetrics.categorySummaryHeight)
            .contentShape(Rectangle())
            .background(DB.black)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .zIndex(10)
    }

    private var categoryFilterOverlay: some View {
        VStack(spacing: 0) {
            categoryFilterContent

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCategoryFilterOverlayPresented = false
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Collapse")
                    Image(systemName: "chevron.up")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DB.logoRed)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .buttonStyle(.plain)
        }
        .background(DB.black)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(2)
    }

    @ViewBuilder
    private var categoryGridStateContent: some View {
        if viewModel.isCategoryLoading {
            VStack {
                Spacer(minLength: 120)
                ProgressView().tint(DT.Color.textSecondary)
                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity)
        } else if let err = viewModel.categoryErrorMessage, viewModel.categoryDramas.isEmpty {
            VStack(spacing: DT.Space.md) {
                Spacer(minLength: 120)
                Text(err).font(DT.Font.bodyDefault).foregroundColor(DT.Color.textSecondary)
                Button(L10n.retry) { Task { await viewModel.selectCategory(at: viewModel.selectedCategoryIndex) } }
                    .font(DT.Font.button).foregroundColor(DT.brandPink)
                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity)
        } else {
            let dramas = selectedGenre == "All" ? viewModel.featuredDramas : viewModel.categoryDramas
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DT.Space.sm), count: 3), spacing: DT.Space.md) {
                ForEach(dramas) { drama in
                    Button { playerDrama = drama } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0, cornerRadius: DB.posterRadius, width: DB.posterWidth, height: DB.posterHeight)
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

    /// 选中项使用品牌红文字和低对比度背景，位置保持稳定。
    private func catFilterRow(options: [CategoryFilterOption], selected: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { opt in
                    let isSelected = selected.wrappedValue == opt.id
                    Button {
                        selected.wrappedValue = opt.id
                    } label: {
                        Text(opt.title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(isSelected ? DB.logoRed : DB.mutedText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(isSelected ? DB.logoRed.opacity(0.22) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 36)
    }

    // MARK: - Tab 4: Anime

    private func animeTabContent(containerW: CGFloat) -> some View {
        let dramas = viewModel.dramasForAnimeTab
        let heroItems = Array(dramas.prefix(3))
        if dramas.isEmpty { return AnyView(animeEmptyState) }
        return AnyView(ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HomeHeroCarouselSection(dramas: heroItems, playerDrama: $playerDrama, containerW: containerW)
                    .padding(.bottom, 24)
                animeWeeklyFeatured(Array(dramas.prefix(8)), containerW: containerW)
                animeMoreRecommended(Array(dramas.dropFirst(1)), containerW: containerW)
            }
            Color.clear.frame(height: 64)
        }.refreshable { await viewModel.loadData() })
    }

    private var animeEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tv").font(.system(size: 40)).foregroundColor(.white.opacity(0.2))
            Text(L10n.noAnime).font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
        }.frame(maxWidth: .infinity).padding(.top, 80)
    }

    private func animeWeeklyFeatured(_ dramas: [DramaItem], containerW: CGFloat) -> some View {
        let cardW = min(max(containerW * 0.29, 112), 132)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.featured).font(.system(size: 18, weight: .semibold)).foregroundColor(.white).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(dramas) { drama in
                        Button { playerDrama = drama } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0, cornerRadius: DB.posterRadius, width: cardW, height: cardW * 1.5)
                                Text(drama.title).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1).frame(width: cardW)
                                Text(drama.category).font(.system(size: 12)).foregroundColor(DB.mutedText).lineLimit(1).frame(width: cardW)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }
        }.padding(.bottom, 24)
    }

    private func animeMoreRecommended(_ dramas: [DramaItem], containerW: CGFloat) -> some View {
        let coverW = min(max(containerW * 0.28, 104), 122)
        let coverH = coverW * 1.42
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.recommended).font(.system(size: 18, weight: .semibold)).foregroundColor(.white).padding(.horizontal, 16)
            LazyVStack(spacing: 18) {
                ForEach(dramas) { drama in
                    Button { playerDrama = drama } label: {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack(alignment: .topTrailing) {
                                CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0, cornerRadius: DB.posterRadius, width: coverW, height: coverH)
                                if let flag = displayFlag(for: drama) {
                                    Text(flag).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.52, green: 0.38, blue: 0.82))).padding(4)
                                }
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        HStack(spacing: 3) {
                                            Image(systemName: "play.fill").font(.system(size: 8))
                                            Text(drama.formattedViewCount).font(.system(size: 10, weight: .medium))
                                        }.foregroundColor(.white).padding(.horizontal, 5).padding(.vertical, 3)
                                            .background(Color.black.opacity(0.55)).cornerRadius(3).padding(4)
                                    }
                                }
                            }.frame(width: coverW, height: coverH)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(drama.title).font(.system(size: 16, weight: .semibold)).foregroundColor(.white).lineLimit(2)
                                if !drama.synopsis.isEmpty { Text(drama.synopsis).font(.system(size: 13)).foregroundColor(DB.mutedText).lineLimit(3) }
                                HStack(spacing: 8) {
                                    Text(drama.category).font(.system(size: 12)).foregroundColor(DB.mutedText)
                                    if let languageTag = drama.languageTag, !languageTag.isEmpty {
                                        Text(languageTag).font(.system(size: 12)).foregroundColor(DB.mutedText)
                                    }
                                    Text("\(drama.episodeCount) EP").font(.system(size: 12)).foregroundColor(DB.mutedText)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }

    /// 从后端 display_flags 读取运营角标，不下发时返回 nil
    private func displayFlag(for drama: DramaItem) -> String? { drama.displayFlags.first }

    // MARK: - Tab 5: VIP Content Channel

    private func homeVIPTabContent(containerW: CGFloat) -> some View {
        let weeklySection = viewModel.section("vip_weekly_featured", in: "vip")
        let classicsSection = viewModel.section("vip_classics", in: "vip")
        let weeklyItems = weeklySection?.items ?? []
        let classicsItems = classicsSection?.items ?? []
        let hasContent = !weeklyItems.isEmpty || !classicsItems.isEmpty
        return ScrollView(showsIndicators: false) {
            if hasContent {
                VStack(alignment: .leading, spacing: 28) {
                    if !weeklyItems.isEmpty {
                        HomePosterRailSection(
                            title: weeklySection?.titleKey ?? "Weekly Featured",
                            dramas: weeklyItems,
                            playerDrama: $playerDrama,
                            containerW: containerW
                        )
                    }
                    if !classicsItems.isEmpty {
                        HomeDramaListSection(
                            title: classicsSection?.titleKey ?? "VIP Classics",
                            dramas: classicsItems,
                            playerDrama: $playerDrama,
                            containerW: containerW
                        )
                    }
                }
            } else {
                Text("No VIP content yet").font(.system(size: 14)).foregroundColor(DB.mutedText).padding(.top, 80)
            }
            Color.clear.frame(height: 64)
        }
        .refreshable { await viewModel.loadData() }
    }

    // MARK: - Tab 6: Original+

    private func originalPlusTabContent(containerW: CGFloat) -> some View {
        let heroItems = Array((viewModel.section("original_hero", in: "original_plus")?.items ?? []).prefix(3))
        let railSections = [
            ("original_exclusive", "Exclusive Originals"),
            ("original_new_releases", "New Releases"),
            ("original_nextgen", "NextGen Stories"),
            ("original_hidden_identity", "Hidden Identity"),
            ("original_sweet_love", "Sweet Love"),
            ("original_werewolf_mafia", "Werewolf & Mafia")
        ].compactMap { code, fallbackTitle -> (String, [DramaItem])? in
            guard let section = viewModel.section(code, in: "original_plus"), !section.items.isEmpty else { return nil }
            return (section.titleKey ?? fallbackTitle, section.items)
        }
        let topCharts = viewModel.section("original_top_charts", in: "original_plus")?.items ?? []
        let hasContent = !heroItems.isEmpty || !railSections.isEmpty || !topCharts.isEmpty

        return ScrollView(showsIndicators: false) {
            if hasContent {
                VStack(alignment: .leading, spacing: 28) {
                    if !heroItems.isEmpty {
                        HomeHeroCarouselSection(
                            dramas: heroItems,
                            playerDrama: $playerDrama,
                            containerW: containerW
                        )
                    }
                    ForEach(Array(railSections.enumerated()), id: \.offset) { _, section in
                        HomePosterRailSection(
                            title: section.0,
                            dramas: section.1,
                            playerDrama: $playerDrama,
                            containerW: containerW
                        )
                    }
                    if !topCharts.isEmpty {
                        HomeDramaListSection(
                            title: "Top Charts",
                            dramas: topCharts,
                            playerDrama: $playerDrama,
                            containerW: containerW
                        )
                    }
                }
            } else {
                Text("No Original+ content yet").font(.system(size: 14)).foregroundColor(DB.mutedText).padding(.top, 80)
            }
            Color.clear.frame(height: 64)
        }
        .refreshable { await viewModel.loadData() }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: DT.Space.lg) { ProgressView().tint(DT.brandPink).scaleEffect(1.2); Text(L10n.loading).font(DT.Font.caption).foregroundColor(DT.Color.textSecondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
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

// MARK: - New Tab Row

private struct NewDramaRow: View {
    let drama: DramaItem
    let dateBadge: String
    let containerWidth: CGFloat
    let onTap: () -> Void

    private var coverWidth: CGFloat {
        let available = containerWidth - DT.Space.pageH * 2
        return min(max(available * 0.34, 110), 132)
    }

    private var coverHeight: CGFloat {
        coverWidth * 1.28
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                poster

                VStack(alignment: .leading, spacing: 8) {
                    Text(drama.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(drama.synopsis.isEmpty ? "A short drama imported from legacy playable media." : drama.synopsis)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(DB.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        Text(drama.category.isEmpty ? "Drama" : drama.category)
                            .lineLimit(1)
                        if let tag = drama.tags.first, !tag.isEmpty {
                            Text(tag)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("\(drama.episodeCount) Episodes")
                            .lineLimit(1)
                    }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(DB.mutedText)
                }
                .frame(height: coverHeight, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var poster: some View {
        ZStack(alignment: .topTrailing) {
            CoverImageView(
                url: drama.coverURL,
                aspectRatio: 2.0 / 3.0,
                cornerRadius: DB.posterRadius,
                width: coverWidth,
                height: coverHeight
            )

            Text(dateBadge)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedCorner(radius: DB.posterRadius, corners: [.topRight, .bottomLeft]))
        }
        .frame(width: coverWidth, height: coverHeight)
    }
}

private extension RankCategory {
    var homeBackdropColors: [Color] {
        switch self {
        case .hot:
            [
                Color(hex: "#54392F").opacity(0.95),
                Color(hex: "#251A17").opacity(0.78),
                DB.black
            ]
        case .trending:
            [
                Color(red: 0.22, green: 0.17, blue: 0.32).opacity(0.86),
                Color(red: 0.14, green: 0.12, blue: 0.22).opacity(0.72),
                DB.black
            ]
        case .new:
            [
                Color(red: 0.07, green: 0.26, blue: 0.28).opacity(0.82),
                Color(red: 0.05, green: 0.16, blue: 0.18).opacity(0.68),
                DB.black
            ]
        }
    }
}

// MARK: - DramaBoxSearchHeader (NotificationCenter triggers)

/// 首页顶部搜索栏 — 接受闭包替代 NotificationCenter
private struct DramaBoxSearchHeaderView: View {
    private let btnH: CGFloat = 36
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
