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
    @Published var masonryDramas: [DramaItem] = []
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
    /// 分类错误信息
    @Published var categoryErrorMessage: String?
    /// 数据库启用且当前 App 已提供本地化资源的语言编码。
    @Published var supportedLanguageCodes: [String] = AppLanguage.allCases.map(\.rawValue)
    /// 当前分类筛选请求的后端分类 code；为空表示全部分类。
    private var selectedCategoryCode: String?
    /// 当前分类筛选请求的内容语言；为空表示使用默认内容语言。
    private var selectedContentLanguage: String?

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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

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
            self.masonryDramas = Array(dramas.dropFirst(9))
            self.rankingDramas = dramas.sorted { $0.viewCount > $1.viewCount }
            self.banners = banners
            prefetchFirstScreenMedia(dramas: dramas, banners: banners)
        } catch {
            errorMessage = Self.userFacingLoadError(error)
            logError("HomeViewModel.loadData failed: \(error)")
            return
        }

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

        if repository.usesRemoteContentCatalog {
            // 真实目录请求失败时不保留本地语言枚举，避免把静态数据冒充服务端目录。
            supportedLanguageCodes = []
        }
        do {
            let languages = try await repository.fetchSupportedLanguages()
            if !languages.isEmpty {
                supportedLanguageCodes = languages
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
        await loadCategoryDramas(for: selectedCategory, contentLanguage: selectedContentLanguage)
    }

    private static func userFacingLoadError(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription,
           !description.isEmpty {
            return description
        }
        return "network.load_failed_retry".localized
    }

    /// 首屏媒体预热：封面降采样缓存 + 头部卡片预览视频的起始字节。
    /// 后台低优先级执行；点进播放页时封面与 MP4 头部直接命中缓存。
    private func prefetchFirstScreenMedia(dramas: [DramaItem], banners: [BannerItem]) {
        let coverURLs = banners.map(\.imageName) + dramas.prefix(18).map(\.coverURL)
        ImageLoader.prefetch(coverURLs)

        let previewURLs = dramas.prefix(6).compactMap { item -> URL? in
            guard let raw = item.videoURL,
                  let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return url
        }
        MediaPreviewPrefetcher.prefetch(urls: previewURLs)
    }

    // MARK: - Category Drama Loading

    /// 切换分类并加载对应剧集
    func selectCategory(at index: Int, contentLanguage: String? = nil) async {
        guard index >= 0, index < categories.count else { return }
        selectedCategoryIndex = index
        let cat = categories[index]
        selectedCategoryCode = cat.code
        selectedContentLanguage = contentLanguage
        await loadCategoryDramas(for: cat, contentLanguage: contentLanguage)
    }

    /// 选择全部分类，并按当前语言重新请求真实内容。
    func selectAllCategories(contentLanguage: String?) async {
        selectedCategoryCode = nil
        selectedContentLanguage = contentLanguage
        await loadCategoryDramas(for: nil, contentLanguage: contentLanguage)
    }

    /// 选择内容语言，并保留当前分类条件重新请求真实内容。
    func selectLanguage(_ contentLanguage: String?) async {
        selectedContentLanguage = contentLanguage
        let category = selectedCategoryCode.flatMap { code in
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

    private func loadCategoryDramas(for category: HomeCategory?, contentLanguage: String?) async {
        isCategoryLoading = true
        categoryErrorMessage = nil
        defer { isCategoryLoading = false }

        do {
            // Mock 或接口降级得到本地分类时，使用本地过滤。
            if let localCat = category?.localCategory {
                let matches = filterFeatured(by: localCat)
                categoryDramas = matches.isEmpty ? featuredDramas : matches
            } else {
                // 真实后端按分类和内容语言查询；category 为空时请求全部分类内容。
                let country = UserDefaults.standard.string(forKey: "app_country_code")
                categoryDramas = try await repository.fetchCategoryContent(
                    categoryCode: category?.code,
                    contentLang: contentLanguage,
                    country: country
                )
            }
        } catch {
            categoryErrorMessage = "分类数据加载失败"
            logError("HomeViewModel.loadCategoryDramas failed: \(error)")
            // 失败时不覆盖已有数据
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
