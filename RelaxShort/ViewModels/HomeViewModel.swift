import SwiftUI
import Combine

// MARK: - Home ViewModel
@MainActor
final class HomeViewModel: ObservableObject {
    private let repository: HomeRepositoryProtocol

    @Published var featuredDramas: [DramaItem] = []
    @Published var fixedDramas: [DramaItem] = []
    @Published var masonryDramas: [DramaItem] = []
    @Published var rankingDramas: [DramaItem] = []
    @Published var banners: [BannerItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedTab: Int = 0

    let tabs: [String] = [
        "Popular", "New", "Rankings", "Categories", "Anime", "VIP", "Original+"
    ]

    /// 是否有内容可展示
    var hasContent: Bool { !fixedDramas.isEmpty }

    // MARK: - Per-Tab Drama Lists

    /// Tab 1 "New" — 最新剧集（按 id 降序，模拟最新）
    var dramasForNewTab: [DramaItem] {
        featuredDramas.sorted { lhs, rhs in
            (Int(lhs.id) ?? 0) > (Int(rhs.id) ?? 0)
        }
    }

    /// Tab 2 "Rankings" — 按 viewCount 降序
    var dramasForRankingsTab: [DramaItem] {
        rankingDramas
    }

    /// 所有分类（排除 .all）
    var browseCategories: [DramaCategory] {
        DramaCategory.allCases.filter { $0 != .all }
    }

    /// Tab 4 "Anime" — tags 含 anime / animation / comics 的剧集
    /// 不允许空白：无 tag 数据时 fallback 到 fantasy → featuredDramas.prefix(12)
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

    /// Tab 6 "Original+" — badge == .vip 或 isHot 为 true 的精选
    var dramasForOriginalPlusTab: [DramaItem] {
        featuredDramas.filter { $0.badge == .vip || $0.isHot }
    }

    /// 按 DramCategory 过滤剧集（用于 Categories tab）
    func dramas(for category: DramaCategory) -> [DramaItem] {
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

    init(repository: HomeRepositoryProtocol) {
        self.repository = repository
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let dramasTask = repository.fetchDramas(category: DramaCategory.all)
        async let bannersTask = repository.fetchBanners()

        do {
            let (dramas, banners) = try await (dramasTask, bannersTask)
            self.featuredDramas = dramas
            self.fixedDramas = Array(dramas.prefix(9))
            self.masonryDramas = Array(dramas.dropFirst(9))
            self.rankingDramas = dramas.sorted { $0.viewCount > $1.viewCount }
            self.banners = banners
        } catch {
            errorMessage = "加载失败，请检查网络后重试"
            logError("HomeViewModel.loadData failed: \(error)")
            // 降级：保持空数组，由 View 展示 Error/Empty 状态
        }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
