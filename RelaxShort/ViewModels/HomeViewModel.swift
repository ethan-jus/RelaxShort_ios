import SwiftUI
import Combine

// MARK: - Home ViewModel
@MainActor
final class HomeViewModel: ObservableObject {
    private let repository: HomeRepositoryProtocol

    @Published var featuredDramas: [DramaItem] = []
    /// Home API section data keyed by tab code.
    @Published var homeTabsByCode: [String: HomeTabContent] = [:]
    @Published var fixedDramas: [DramaItem] = []
    @Published var forYouDramas: [DramaItem] = []
    @Published var homeCategoryCollections: [HomeCategoryCollection] = []
    @Published private(set) var isLoadingMoreForYou = false
    @Published var rankingDramas: [DramaItem] = []
    @Published var banners: [BannerItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedTab: Int = 0

    // MARK: - Categories

    /// 分类列表：真实模式来自后端 categories API，Mock 来自 DramaCategory 枚举
    @Published var categories: [HomeCategory] = []
    /// 当前选中的分类索引（对应 categories 数组）
    @Published var selectedCategoryIndex: Int = 0
    /// 当前分类的剧集列表
    @Published var categoryDramas: [DramaItem] = []
    /// 分类加载状态
    @Published var isCategoryLoading: Bool = false
    /// 切换筛选时保留旧网格，只显示轻量刷新提示，避免整页闪空。
    @Published private(set) var isCategoryRefreshing: Bool = false
    /// 分类错误信息
    @Published var categoryErrorMessage: String?
    /// 数据库启用的内容语言；与 App 界面语言资源范围相互独立。
    @Published var supportedLanguages: [HomeContentLanguage] = AppLanguage.allCases.map {
        HomeContentLanguage(
            code: $0.rawValue,
            nameEn: $0.nativeDisplayName,
            nameNative: $0.nativeDisplayName,
            localizedName: $0.displayName
        )
    }
    /// 当前分类筛选请求的后端分类 code；为空表示全部分类。
    private var selectedCategoryCode: String?
    /// 当前分类筛选请求的内容语言；为空表示使用默认内容语言。
    private var selectedContentLanguage: String?
    private var forYouCursor: String?
    private var forYouHasMore = true
    private var forYouSessionID: String?
    private let forYouPageSize = 20
    private var isForYouRequestInFlight = false
    private var enrichmentTask: Task<Void, Never>?
    private var playbackWarmupTask: Task<Void, Never>?
    private var categoryRequestGeneration = 0

    var canLoadMoreForYou: Bool { forYouHasMore }

    var tabs: [String] {
        [
            "home.tab.popular".localized,
            "home.tab.new".localized,
            "home.tab.rankings".localized,
            "home.tab.categories".localized,
            "home.tab.anime".localized,
            "home.tab.vip".localized,
            "home.tab.original_plus".localized
        ]
    }

    var hasContent: Bool { !fixedDramas.isEmpty }

    // MARK: - Per-Tab Drama Lists

    var dramasForNewTab: [DramaItem] {
        featuredDramas.sorted { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) }
    }

    var dramasForRankingsTab: [DramaItem] {
        rankingDramas
    }

    var dramasForAnimeTab: [DramaItem] {
        if repository.usesRemoteContentCatalog {
            return homeTabsByCode["anime"]?.sections.flatMap(\.items) ?? []
        }

        // 仅供 Mock/预览使用：真实 App 不再根据静态标签或分类名猜测动漫内容。
        let anime = featuredDramas.filter { drama in
            drama.tags.contains { tag in
                let lower = tag.lowercased()
                return lower.contains("anime") || lower.contains("animation") || lower.contains("comics")
            }
        }
        if !anime.isEmpty { return anime }
        let fantasy = featuredDramas.filter { $0.category == "玄幻" }
        if !fantasy.isEmpty { return fantasy }
        return Array(featuredDramas.prefix(12))
    }

    init(repository: HomeRepositoryProtocol) {
        self.repository = repository
    }

    func section(_ sectionCode: String, in tabCode: String) -> HomeSectionContent? {
        homeTabsByCode[tabCode]?.sections.first { $0.code == sectionCode }
    }

    func loadData() async {
        guard !isLoading else { return }
        enrichmentTask?.cancel()
        playbackWarmupTask?.cancel()
        isLoading = true
        errorMessage = nil
        forYouDramas = []
        homeCategoryCollections = []
        forYouCursor = nil
        forYouHasMore = true
        forYouSessionID = UUID().uuidString

        do {
            // Home 是首页关键请求；明确失败后立即结束，不再自动请求其他 feed。
            let tabs = try await repository.fetchHomeTabs(contentLang: nil, country: nil)
            let loadedTabs = Dictionary(tabs.map { ($0.code, $0) }, uniquingKeysWith: { _, latest in latest })
            let configuredDramas = loadedTabs["popular"]?.sections
                .first(where: { !$0.items.isEmpty })?.items ?? []
            let dramas = configuredDramas.isEmpty
                ? try await repository.fetchDramas(category: DramaCategory.all)
                : configuredDramas
            let banners = try await repository.fetchBanners()
            homeTabsByCode = loadedTabs
            self.featuredDramas = dramas
            self.fixedDramas = Array(dramas.prefix(9))
            // /home 已经返回热门前 20 条。先用第 10 条起即时填充“猜你喜欢”，
            // 个性化 Feed 随后成功时再无缝替换，网络抖动也不会只剩 9 张卡片。
            self.forYouDramas = Array(dramas.dropFirst(9)).uniquedByID()
            self.rankingDramas = dramas.sorted { $0.viewCount > $1.viewCount }
            self.banners = banners
        } catch {
            isLoading = false
            errorMessage = Self.userFacingLoadError(error)
            logError("HomeViewModel.loadData failed: \(error)")
            return
        }

        // 首屏 Home 数据一到立即结束骨架；分类字典、猜你喜欢和筛选数据转入非阻塞增强链路。
        isLoading = false
        schedulePlaybackWarmup(dramas: fixedDramas)
        enrichmentTask = Task { [weak self] in
            // 先提交首屏并处理第一轮封面解码，避免推荐流更新与首帧渲染同时挤占主线程。
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.loadSecondaryContent()
        }
    }

    private func loadSecondaryContent() async {
        // 先补齐首屏下方的猜你喜欢，再加载筛选字典和更深层分类合集。
        await loadForYouPage(reset: true)
        guard !Task.isCancelled else { return }
        schedulePlaybackWarmup(dramas: fixedDramas + Array(forYouDramas.prefix(3)))

        // 分类是后端运营字典的唯一来源；真实仓库失败时不能展示另一套本地分类。
        do {
            let cats = try await repository.fetchHomeCategories()
            self.categories = cats
        } catch {
            logError("HomeViewModel.loadCategories failed: \(error)")
            self.categories = repository.usesRemoteContentCatalog ? [] : DramaCategory.allCases.map {
                HomeCategory(id: $0.rawValue, code: $0.rawValue, title: $0.rawValue, localCategory: $0)
            }
        }
        guard !Task.isCancelled else { return }

        if repository.usesRemoteContentCatalog {
            // 真实目录请求失败时不保留本地语言枚举，避免把静态数据冒充服务端目录。
            supportedLanguages = []
        }
        do {
            let languages = try await repository.fetchSupportedLanguages()
            if !languages.isEmpty {
                supportedLanguages = languages
            }
        } catch {
            logError("HomeViewModel.loadSupportedLanguages failed: \(error)")
        }
        let selectedCategory = selectedCategoryCode.flatMap { code in
            categories.first(where: { $0.code == code })
        }
        if let selectedCategory,
           let index = categories.firstIndex(where: { $0.code == selectedCategory.code }) {
            selectedCategoryIndex = index
        }
        rebuildHomeCategoryCollections()
    }

    /// 使用已加载的真实推荐流在本地组装分类合集。
    /// 后端同时返回稳定 categoryCode 和本地化 category 名称，因此无需为 12 个分类逐个发请求。
    private func rebuildHomeCategoryCollections() {
        guard !categories.isEmpty else {
            homeCategoryCollections = []
            return
        }

        var chunksByCategory: [(HomeCategory, [[DramaItem]])] = []

        for category in categories {
            let unique = forYouDramas.filter { drama in
                if drama.categoryCode == category.code { return true }
                // 兼容后端升级前的短时缓存；只有展示名称确实相同时才采用。
                return drama.category.localizedCaseInsensitiveCompare(category.title) == .orderedSame
            }.uniquedByID()
            let chunks = stride(from: 0, to: unique.count, by: 4).compactMap { start -> [DramaItem]? in
                let end = min(start + 4, unique.count)
                guard end - start == 4 else { return nil }
                return Array(unique[start..<end])
            }
            if !chunks.isEmpty { chunksByCategory.append((category, chunks)) }
        }

        // 先覆盖不同分类，再使用同一分类的后续 4 部剧，保证真实数据不足时仍能维持原布局节奏。
        var collections: [HomeCategoryCollection] = []
        let maxChunkCount = chunksByCategory.map { $0.1.count }.max() ?? 0
        for chunkIndex in 0..<maxChunkCount {
            for (category, chunks) in chunksByCategory where chunkIndex < chunks.count {
                collections.append(HomeCategoryCollection(category: category, dramas: chunks[chunkIndex]))
                if collections.count == 5 { break }
            }
            if collections.count == 5 { break }
        }
        homeCategoryCollections = collections
    }

    func loadMoreForYou() async {
        guard forYouHasMore,
              !isForYouRequestInFlight,
              !isLoadingMoreForYou else { return }
        await loadForYouPage(reset: false)
    }

    private func loadForYouPage(reset: Bool) async {
        guard !isForYouRequestInFlight else { return }
        if !reset {
            guard forYouHasMore, !isLoadingMoreForYou else { return }
            isLoadingMoreForYou = true
        }
        isForYouRequestInFlight = true
        defer {
            isForYouRequestInFlight = false
            isLoadingMoreForYou = false
        }

        let contentLanguage = UserDefaults.standard.string(forKey: "app_content_language")
        let country = UserDefaults.standard.string(forKey: "app_country_code")
        do {
            let homeFallback = reset ? forYouDramas : []
            let result = try await repository.fetchForYouPaginated(
                contentLang: contentLanguage,
                country: country,
                cursor: reset ? nil : forYouCursor,
                limit: forYouPageSize,
                feedSeed: forYouSessionID
            )
            forYouCursor = result.nextCursor
            forYouHasMore = result.hasMore

            // 聚集卡是内容导航模块，允许与热门/推荐流交叉；只防止 For You 自身分页重复。
            let blockedIDs: Set<String> = reset ? [] : Set(forYouDramas.map(\.id))
            let unique = result.items.filter { !blockedIDs.contains($0.id) }.uniquedByID()
            if reset {
                forYouDramas = (unique + homeFallback).uniquedByID()
            } else {
                forYouDramas.append(contentsOf: unique)
            }
            rebuildHomeCategoryCollections()
        } catch {
            guard !Task.isCancelled else { return }
            logError("HomeViewModel.loadForYou failed: \(error)")
        }
    }

    private static func userFacingLoadError(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription,
           !description.isEmpty {
            return description
        }
        return "network.load_failed_retry".localized
    }

    /// 首屏稳定后再低优先级预热少量旧 MP4；HLS 由播放器按分片加载。
    /// 可见封面自身已经按需加载，这里不再重复下载和解码同一批图片。
    private func schedulePlaybackWarmup(dramas: [DramaItem]) {
        playbackWarmupTask?.cancel()
        let previewURLs = dramas.compactMap { item -> URL? in
            guard let raw = item.videoURL,
                  let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.pathExtension.lowercased() == "mp4" else { return nil }
            return url
        }
        guard !previewURLs.isEmpty else { return }
        playbackWarmupTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            MediaPreviewPrefetcher.prefetch(urls: previewURLs, maxCount: 2)
        }
    }

    // MARK: - Category Drama Loading

    /// 分类与语言作为同一份筛选状态提交，避免两个按钮各自创建异步任务后互相覆盖。
    func selectFilters(categoryCode: String?, contentLanguage: String?) async {
        selectedCategoryCode = categoryCode
        selectedContentLanguage = contentLanguage
        if let categoryCode,
           let index = categories.firstIndex(where: { $0.code == categoryCode }) {
            selectedCategoryIndex = index
        }
        let category = categoryCode.flatMap { code in
            categories.first(where: { $0.code == code })
        }
        await loadCategoryDramas(for: category, contentLanguage: contentLanguage)
    }

    /// 重试当前分类/语言筛选请求。
    func reloadCategoryContent() async {
        let category = selectedCategoryCode.flatMap { code in
            categories.first(where: { $0.code == code })
        }
        await loadCategoryDramas(for: category, contentLanguage: selectedContentLanguage)
    }

    /// App 界面语言切换后重新请求分类字典；分类 code 和内容语言筛选保持不变。
    func reloadCategoryLocalizations() async {
        do {
            categories = try await repository.fetchHomeCategories()
            if let selectedCategoryCode,
               let index = categories.firstIndex(where: { $0.code == selectedCategoryCode }) {
                selectedCategoryIndex = index
            }
            rebuildHomeCategoryCollections()
        } catch {
            logError("HomeViewModel.reloadCategoryLocalizations failed: \(error)")
        }
        do {
            let languages = try await repository.fetchSupportedLanguages()
            if !languages.isEmpty { supportedLanguages = languages }
        } catch {
            logError("HomeViewModel.reloadLanguageLocalizations failed: \(error)")
        }
    }

    private func loadCategoryDramas(for category: HomeCategory?, contentLanguage: String?) async {
        categoryRequestGeneration += 1
        let requestGeneration = categoryRequestGeneration
        isCategoryLoading = categoryDramas.isEmpty
        isCategoryRefreshing = !categoryDramas.isEmpty
        categoryErrorMessage = nil

        do {
            let loadedDramas: [DramaItem]
            // Mock 或接口降级得到本地分类时，使用本地过滤。
            if let localCat = category?.localCategory {
                let matches = filterFeatured(by: localCat)
                loadedDramas = matches.isEmpty ? featuredDramas : matches
            } else {
                // 真实后端按分类和内容语言查询；category 为空时请求全部分类内容。
                let country = UserDefaults.standard.string(forKey: "app_country_code")
                loadedDramas = try await repository.fetchCategoryContent(
                    categoryCode: category?.code,
                    contentLang: contentLanguage,
                    country: country
                )
            }
            guard requestGeneration == categoryRequestGeneration else { return }
            categoryDramas = loadedDramas
        } catch {
            guard requestGeneration == categoryRequestGeneration else { return }
            guard !Task.isCancelled else {
                isCategoryLoading = false
                isCategoryRefreshing = false
                return
            }
            categoryErrorMessage = "分类数据加载失败"
            logError("HomeViewModel.loadCategoryDramas failed: \(error)")
            // 失败时不覆盖已有数据
        }
        if requestGeneration == categoryRequestGeneration {
            isCategoryLoading = false
            isCategoryRefreshing = false
        }
    }

    /// 本地 DramaCategory 过滤（Mock 降级用）
    private func filterFeatured(by category: DramaCategory) -> [DramaItem] {
        let matches: [String] = {
            switch category {
            case .modernRomance: return ["现代言情"]
            case .ancientCostume: return ["古代言情"]
            case .sweetPet:      return ["甜宠"]
            case .revenge:       return ["逆袭"]
            case .billionaire:   return ["总裁"]
            case .urban:         return ["都市"]
            case .fantasy:       return ["玄幻"]
            default:             return [category.rawValue]
            }
        }()
        return featuredDramas.filter { matches.contains($0.category) }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}

private extension Array where Element == DramaItem {
    func uniquedByID() -> [DramaItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
