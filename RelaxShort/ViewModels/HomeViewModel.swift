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

    let tabs: [String] = [
        "Popular", "New", "Rankings", "Categories", "Anime", "VIP", "Original+"
    ]

    var hasContent: Bool { !fixedDramas.isEmpty }

    // MARK: - Per-Tab Drama Lists

    var dramasForNewTab: [DramaItem] {
        featuredDramas.sorted { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) }
    }

    var dramasForRankingsTab: [DramaItem] {
        rankingDramas
    }

    var dramasForAnimeTab: [DramaItem] {
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let bannersTask = repository.fetchBanners()
        async let categoriesTask = repository.fetchHomeCategories()
        async let homeTabsTask = repository.fetchHomeTabs(contentLang: nil, country: nil)

        do {
            let tabs = try await homeTabsTask
            homeTabsByCode = Dictionary(tabs.map { ($0.code, $0) }, uniquingKeysWith: { _, latest in latest })
        } catch {
            homeTabsByCode = [:]
            logError("HomeViewModel.loadHomeTabs failed: \(error)")
        }

        do {
            let configuredDramas = homeTabsByCode["popular"]?.sections
                .first(where: { !$0.items.isEmpty })?.items ?? []
            let dramas = configuredDramas.isEmpty
                ? try await repository.fetchDramas(category: DramaCategory.all)
                : configuredDramas
            let banners = try await bannersTask
            self.featuredDramas = dramas
            self.fixedDramas = Array(dramas.prefix(9))
            self.masonryDramas = Array(dramas.dropFirst(9))
            self.rankingDramas = dramas.sorted { $0.viewCount > $1.viewCount }
            self.banners = banners
        } catch {
            errorMessage = "加载失败，请检查网络后重试"
            logError("HomeViewModel.loadData failed: \(error)")
        }

        // 分类独立加载；失败时回退本地枚举，再加载默认分类内容。
        do {
            let cats = try await categoriesTask
            self.categories = cats
        } catch {
            logError("HomeViewModel.loadCategories failed: \(error)")
            self.categories = DramaCategory.allCases.map {
                HomeCategory(id: $0.rawValue, code: $0.rawValue, title: $0.rawValue, localCategory: $0)
            }
        }
        if !categories.isEmpty {
            selectedCategoryIndex = 0
            await loadCategoryDramas(for: categories[0])
        }
    }

    // MARK: - Category Drama Loading

    /// 切换分类并加载对应剧集
    func selectCategory(at index: Int) async {
        guard index >= 0, index < categories.count else { return }
        selectedCategoryIndex = index
        let cat = categories[index]
        await loadCategoryDramas(for: cat)
    }

    private func loadCategoryDramas(for category: HomeCategory) async {
        isCategoryLoading = true
        categoryErrorMessage = nil
        defer { isCategoryLoading = false }

        do {
            // Mock 或接口降级得到本地分类时，使用本地过滤。
            if let localCat = category.localCategory {
                let matches = filterFeatured(by: localCat)
                categoryDramas = matches.isEmpty ? featuredDramas : matches
            } else {
                // 真实后端分类（localCategory == nil）：通过协议方法调 categorySeries（Task17 收口）
                let contentLang = UserDefaults.standard.string(forKey: "app_content_language")
                let country = UserDefaults.standard.string(forKey: "app_country_code")
                categoryDramas = try await repository.fetchCategorySeries(
                    code: category.code, contentLang: contentLang, country: country
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
