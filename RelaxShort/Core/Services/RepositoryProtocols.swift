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
    /// 按榜单类型获取排行（Task30 R4B-1：返回 RankingEntry 领域模型）
    func fetchRankingEntries(type: String) async throws -> [RankingEntry]
    /// 获取 Home Categories tab 的分类列表。
    func fetchHomeCategories() async throws -> [HomeCategory]
    /// 获取首页 tab/section 运营配置内容
    func fetchHomeTabs(contentLang: String?, country: String?) async throws -> [HomeTabContent]
    /// 按后端分类 code 获取剧集列表。
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
    /// 默认实现：Mock 模式暂不提供运营 section 数据
    func fetchHomeTabs(contentLang: String?, country: String?) async throws -> [HomeTabContent] {
        return []
    }
    /// 默认实现：Mock 模式用 viewCount 生成测试指标
    func fetchRankingEntries(type: String) async throws -> [RankingEntry] {
        let dramas = try await fetchDramas(category: .all)
        return dramas.prefix(20).enumerated().map { index, drama in
            RankingEntry(
                rankPosition: index + 1,
                metricType: "mock_view_count",
                metricValue: Int64(drama.viewCount),
                drama: drama
            )
        }
    }
}

// MARK: - Search

/// 搜索数据仓库协议
protocol SearchRepositoryProtocol {
    /// 获取搜索默认页的热门搜索词
    func fetchSuggestions() async throws -> [String]
    /// 按关键词搜索短剧
    func search(query: String, cursor: String?, limit: Int) async throws -> ([DramaItem], String?, Bool)
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
    /// 获取服务端钱包与 VIP 权益，作为解锁 UI 的唯一余额来源。
    func fetchUnlockAccount() async throws -> EpisodeUnlockAccount
    /// 金币/广告解锁；只有服务端返回成功后才允许恢复播放。
    func unlockEpisode(episodeId: String, method: EpisodeUnlockMethod) async throws -> EpisodeUnlockResult
    /// Apple 验单发币，返回服务端最终钱包余额。
    func verifyCoinPurchase(_ receipt: ApplePurchaseReceipt) async throws -> Int
    /// Apple 验单开通 VIP，只有服务端权益已生效才返回账户状态。
    func verifyVIPPurchase(_ receipt: ApplePurchaseReceipt) async throws -> EpisodeUnlockAccount
    /// 获取相关推荐短剧
    func fetchRelatedDramas(dramaId: String) async throws -> [DramaItem]
}

// MARK: - Favorites

/// 收藏/历史数据仓库协议
protocol FavoritesRepositoryProtocol: Sendable {
    /// 获取观看历史（游标分页）
    func fetchWatchHistory(cursor: String?, limit: Int) async throws
        -> CursorPage<WatchHistoryItem>
    /// 删除当前用户指定短剧的观看历史
    func deleteWatchHistory(seriesID: String) async throws
    /// 获取收藏列表（游标分页）
    func fetchBookmarks(cursor: String?, limit: Int) async throws
        -> CursorPage<DramaItem>
    /// 批量查询收藏状态，返回当前已收藏的 series ID 集合
    func fetchBookmarkedSeriesIDs(_ seriesIDs: [String]) async throws -> Set<String>
    /// 设置/取消收藏，返回服务端最终状态
    func setBookmarked(_ bookmarked: Bool, seriesID: String) async throws -> Bool
    /// 上报观看进度
    func reportProgress(_ report: WatchProgressReport) async throws
}

// MARK: - Profile

/// 个人中心数据仓库协议
protocol ProfileRepositoryProtocol {
    /// 获取用户信息
    func fetchUserProfile() async throws -> User
}

// MARK: - VIP

/// VIP 会员数据仓库协议
protocol VIPRepositoryProtocol {
    /// 获取套餐列表
    func fetchPlans() async throws -> [VIPPlan]
    /// 获取权益列表
    func fetchBenefits() async throws -> [VIPBenefit]
}

// MARK: - Member

/// Member 页面 UI 模型，由 Repository 从 DTO 转换而来。
struct MemberContent {
    let backgroundPosters: [DramaItem]
    let memberOnlyDramas: [DramaItem]
}

/// Member 订阅页数据仓库协议
protocol MemberRepositoryProtocol {
    /// 获取 Member 页面内容：封面背景 + 会员专属剧集
    func fetchMemberContent(
        contentLanguage: String?,
        countryCode: String?
    ) async throws -> MemberContent
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
