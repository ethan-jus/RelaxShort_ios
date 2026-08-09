import Foundation

// MARK: - Repository Protocols
/// 集中定义所有数据仓库协议，遵循 Protocol-Oriented DI 架构。
/// ViewModel 依赖协议而非具体实现，由 DependencyContainer 统一注入。

// MARK: - Home

/// 首页数据仓库协议
protocol HomeRepositoryProtocol {
    /// 真实后端仓库不允许用本地枚举伪造分类；Mock 仓库保留本地默认实现供预览和单元测试使用。
    var usesRemoteContentCatalog: Bool { get }
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
    /// 按分类和内容语言获取首页分类内容；categoryCode 为空时获取全部分类内容。
    func fetchCategoryContent(categoryCode: String?, contentLang: String?, country: String?) async throws -> [DramaItem]
    /// 获取数据库启用的内容语言目录；不受 App 界面语言资源范围限制。
    func fetchSupportedLanguages() async throws -> [HomeContentLanguage]
    /// 获取真实 For You 推荐流；登录用户由后端基于行为偏好重排，匿名用户使用全局推荐。
    func fetchForYouPaginated(contentLang: String?, country: String?, cursor: String?, limit: Int,
                              feedSeed: String?) async throws -> (
        items: [DramaItem], nextCursor: String?, hasMore: Bool
    )
}

extension HomeRepositoryProtocol {
    var usesRemoteContentCatalog: Bool { false }

    /// 默认实现：Mock 模式用本地 DramaCategory 列表
    func fetchHomeCategories() async throws -> [HomeCategory] {
        return DramaCategory.allCases.map { HomeCategory(id: $0.rawValue, code: $0.rawValue, title: $0.rawValue, localCategory: $0) }
    }
    /// 默认实现：Mock 模式返回空或全量本地过滤
    func fetchCategorySeries(code: String, contentLang: String?, country: String?) async throws -> [DramaItem] {
        return try await fetchDramas(category: .all)
    }
    /// 默认实现：Mock 模式使用本地数据；真实分类查询由 RealHomeRepository 覆盖。
    func fetchCategoryContent(categoryCode: String?, contentLang: String?, country: String?) async throws -> [DramaItem] {
        if let categoryCode, !categoryCode.isEmpty {
            return try await fetchCategorySeries(code: categoryCode, contentLang: contentLang, country: country)
        }
        return try await fetchDramas(category: .all)
    }
    /// 默认实现：Mock 模式暂不提供运营 section 数据
    func fetchHomeTabs(contentLang: String?, country: String?) async throws -> [HomeTabContent] {
        return []
    }
    /// 默认实现：Mock 使用当前 App 已内置的语言资源。
    func fetchSupportedLanguages() async throws -> [HomeContentLanguage] {
        AppLanguage.allCases.map {
            HomeContentLanguage(
                code: $0.rawValue,
                nameEn: $0.nativeDisplayName,
                nameNative: $0.nativeDisplayName
            )
        }
    }
    func fetchForYouPaginated(contentLang: String?, country: String?, cursor: String?, limit: Int,
                              feedSeed: String?) async throws -> (
        items: [DramaItem], nextCursor: String?, hasMore: Bool
    ) {
        let all = try await fetchDramas(category: .all)
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(start + max(limit, 1), all.count)
        let items = start < end ? Array(all[start..<end]) : []
        return (items, end < all.count ? String(end) : nil, end < all.count)
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
    /// 金币解锁；只有服务端返回成功后才允许恢复播放。
    func unlockEpisodeWithCoins(episodeId: String) async throws -> EpisodeUnlockResult
    /// Apple 验单发币，返回服务端最终钱包余额。
    func verifyCoinPurchase(_ receipt: ApplePurchaseReceipt) async throws -> Int
    /// Apple 验单开通 VIP，只有服务端权益已生效才返回账户状态。
    func verifyVIPPurchase(_ receipt: ApplePurchaseReceipt) async throws -> EpisodeUnlockAccount
    /// 获取后端为当前登录用户分配的 StoreKit appAccountToken。
    func fetchAppleAccountToken() async throws -> UUID
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

// MARK: - Wallet

/// 钱包首页数据仓库协议。Repository 负责把钱包 DTO 转为页面领域模型。
protocol WalletRepositoryProtocol {
    func fetchOverview(limit: Int) async throws -> WalletOverview
    func fetchTransactions(
        cursor: String?,
        limit: Int,
        month: String,
        category: WalletTransactionCategory
    ) async throws -> WalletTransactionPage
}

// MARK: - Support

protocol SupportRepositoryProtocol {
    func fetchTickets() async throws -> [SupportTicket]
    func fetchTicket(number: String) async throws -> SupportTicket
    func createTicket(_ ticket: CreateSupportTicket) async throws -> SupportTicket
    func sendMessage(ticketNumber: String, message: String) async throws -> SupportTicket
    func resolveTicket(number: String) async throws -> SupportTicket
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
    let plans: [MemberPlanDisplayOption]
    let benefits: [MemberBenefitDisplayItem]
    let legalLinks: MemberLegalLinks?
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
    func fetchRewardCenter() async throws -> RewardCenterState
    func checkIn() async throws -> RewardCenterState
    func recordShare(
        seriesID: String,
        episodeID: String?,
        channel: String,
        idempotencyKey: String
    ) async throws -> RewardCenterState
    func applyInviteCode(_ code: String) async throws -> RewardCenterState
}

// MARK: - Ads

enum AdFormat: String {
    case appOpen = "app_open"
    case rewarded
    case rewardedInterstitial = "rewarded_interstitial"
    case interstitial
    case unknown
}

struct AdPlacementConfig {
    let placementCode: String
    let enabled: Bool
    let adUnitID: String
    let format: AdFormat
    let rewardCoins: Int
    let maxPerUserPerDay: Int
    let cooldownSeconds: Int
}

struct AdsConfig {
    let adsEnabled: Bool
    let appOpen: AdPlacementConfig
    let rewardedEarnCoins: AdPlacementConfig
    let interstitialUnlockEpisode: AdPlacementConfig
    let interstitial: AdPlacementConfig
}

struct AdRewardSession {
    let id: Int64
    let idempotencyKey: String
    let placement: AdPlacementConfig
    let rewardType: String
    let ssvCustomData: String
}

struct AdRewardCompletion {
    let status: String
    let pendingVerification: Bool

    var isDelivered: Bool {
        status == "completed" && !pendingVerification
    }
}

protocol AdConfigRepositoryProtocol {
    func fetchAdsConfig() async throws -> AdsConfig
}

protocol AdRewardRepositoryProtocol {
    func startSession(
        placementCode: String,
        rewardType: String,
        targetEpisodeID: String?
    ) async throws -> AdRewardSession
    func completeSession(_ session: AdRewardSession) async throws -> AdRewardCompletion
    func cancelSession(_ session: AdRewardSession) async
}
