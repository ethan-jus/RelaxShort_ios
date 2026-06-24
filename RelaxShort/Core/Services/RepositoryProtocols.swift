import Foundation

// MARK: - Repository Protocols
/// 集中定义所有数据仓库协议，遵循 Protocol-Oriented DI 架构。
/// ViewModel 依赖协议而非具体实现，由 DependencyContainer 统一注入。

// MARK: - Home

/// 首页数据仓库协议
protocol HomeRepositoryProtocol {
    /// 按分类获取短剧列表
    func fetchDramas(category: DramaCategory) async throws -> [DramaItem]
    /// 获取 Banner 轮播数据
    func fetchBanners() async throws -> [BannerItem]
    /// 按榜单类型获取排行（Task16：RankViewModel 通过协议调用后端 rankings）
    func fetchRankings(type: String) async throws -> [DramaItem]
    /// 获取分类列表（Task16 R3：Home Categories tab 用）
    func fetchHomeCategories() async throws -> [HomeCategory]
    /// 按后端分类 code 获取剧集列表（Task17：协议收口，移除 HomeViewModel 对 RealHomeRepository 的直接依赖）
    func fetchCategorySeries(code: String, contentLang: String?, country: String?) async throws -> [DramaItem]
}

extension HomeRepositoryProtocol {
    /// 默认实现：Mock 模式用本地 DramaCategory 列表
    func fetchHomeCategories() async throws -> [HomeCategory] {
        return DramaCategory.allCases.map { HomeCategory(id: $0.rawValue, code: $0.rawValue, title: $0.rawValue, localCategory: $0) }
    }
    /// 默认实现：Mock 模式返回空或全量本地过滤
    func fetchCategorySeries(code: String, contentLang: String?, country: String?) async throws -> [DramaItem] {
        return try await fetchDramas(category: .all)
    }
    /// 默认实现：本地排序降级（Mock 模式）
    func fetchRankings(type: String) async throws -> [DramaItem] {
        let dramas = try await fetchDramas(category: .all)
        switch type {
        case "popular", "hot": return dramas.sorted { $0.viewCount > $1.viewCount }
        case "trending":       return dramas.filter { $0.isTrending }.sorted { $0.viewCount > $1.viewCount }
        case "new":            return dramas.sorted { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) }
        default:        return Array(dramas.prefix(20))
        }
    }
}

// MARK: - Search

/// 搜索数据仓库协议
protocol SearchRepositoryProtocol {
    /// 获取全部短剧（用于搜索过滤）
    func fetchDramas(category: DramaCategory) async throws -> [DramaItem]
    /// 按关键词搜索短剧
    func search(query: String, cursor: String?, limit: Int) async throws -> ([DramaItem], String?, Bool)
    /// 获取 Banner 轮播数据
    func fetchBanners() async throws -> [BannerItem]
}

// MARK: - Detail

/// 详情数据仓库协议
protocol DetailRepositoryProtocol {
    /// 获取短剧详情
    func fetchDramaDetail(id: String) async throws -> DramaItem
    /// 获取剧集列表
    func fetchEpisodes(dramaId: String) async throws -> [Episode]
    /// 获取单集播放源
    func fetchPlayAsset(episodeId: String) async throws -> PlaybackMediaSourceDTO
    /// 获取相关推荐短剧
    func fetchRelatedDramas(dramaId: String) async throws -> [DramaItem]
}

// MARK: - Favorites

/// 收藏/历史数据仓库协议
protocol FavoritesRepositoryProtocol {
    /// 获取观看历史
    func fetchWatchHistory(page: Int) async throws -> [WatchHistoryItem]
    /// 获取收藏列表
    func fetchBookmarks(page: Int) async throws -> [DramaItem]
}

// MARK: - Profile

/// 个人中心数据仓库协议
protocol ProfileRepositoryProtocol {
    /// 获取用户信息
    func fetchUserProfile() async throws -> User
}

// MARK: - Auth

/// 认证数据仓库协议
protocol AuthRepositoryProtocol {
    /// Google 登录
    func signInWithGoogle() async throws -> User
    /// Apple 登录
    func signInWithApple() async throws -> User
    /// 游客登录
    func signInAsGuest() async throws -> User
}

// MARK: - VIP

/// VIP 会员数据仓库协议
protocol VIPRepositoryProtocol {
    /// 获取套餐列表
    func fetchPlans() async throws -> [VIPPlan]
    /// 获取权益列表
    func fetchBenefits() async throws -> [VIPBenefit]
}

// MARK: - Coin Reward

/// 福利中心/赚金币数据仓库协议
protocol CoinRewardRepositoryProtocol {
    /// 获取签到日数据
    func fetchCheckInDays() async throws -> [CheckInDay]
    /// 获取金币余额
    func fetchCoinBalance() async throws -> Int
    /// 获取任务列表
    func fetchTasks() async throws -> [CoinTask]
}
