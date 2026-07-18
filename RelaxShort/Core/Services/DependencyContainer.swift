import Foundation

// MARK: - Dependency Container
/// 集中管理所有 Repository 依赖注入。
/// 在 `RelaxShortApp.swift` 中创建为 `@StateObject`，通过 `.environmentObject()` 传递。
///
/// Task32：真实 API 模块均直接注入 Real Repository，不再通过 use_real_api 开关切换。
/// Task34A：认证由 `AuthSessionCoordinator` 独立管理；未开发的 VIP / CoinReward 暂不扩面。
@MainActor
final class DependencyContainer: ObservableObject {

    // MARK: - Repositories

    let homeRepository: HomeRepositoryProtocol
    let searchRepository: SearchRepositoryProtocol
    let detailRepository: DetailRepositoryProtocol
    let favoritesRepository: FavoritesRepositoryProtocol
    let profileRepository: ProfileRepositoryProtocol
    let memberRepository: MemberRepositoryProtocol
    let vipRepository: VIPRepositoryProtocol
    let coinRewardRepository: CoinRewardRepositoryProtocol
    let adConfigRepository: AdConfigRepositoryProtocol
    let adRewardRepository: AdRewardRepositoryProtocol
    let adService: any AdServiceProtocol
    let discoveryAnalytics: any DiscoveryAnalyticsTracking

    // MARK: - Stores

    let bookmarkStore: BookmarkStore
    let watchProgressReporter: WatchProgressReporter

    // MARK: - Init

    init(
        homeRepository: HomeRepositoryProtocol? = nil,
        searchRepository: SearchRepositoryProtocol? = nil,
        detailRepository: DetailRepositoryProtocol? = nil,
        favoritesRepository: FavoritesRepositoryProtocol? = nil,
        profileRepository: ProfileRepositoryProtocol? = nil,
        memberRepository: MemberRepositoryProtocol? = nil,
        vipRepository: VIPRepositoryProtocol = MockVIPRepository(),
        coinRewardRepository: CoinRewardRepositoryProtocol = RealCoinRewardRepository(),
        adConfigRepository: AdConfigRepositoryProtocol = RealAdConfigRepository(),
        adRewardRepository: AdRewardRepositoryProtocol = RealAdRewardRepository(),
        adService: (any AdServiceProtocol)? = nil,
        discoveryAnalytics: (any DiscoveryAnalyticsTracking)? = nil
    ) {
        // 已完成真实接入的模块：直接注入 Real Repository，不依赖 use_real_api 开关
        self.homeRepository = homeRepository ?? RealHomeRepository()
        self.searchRepository = searchRepository ?? RealSearchRepository()
        self.detailRepository = detailRepository ?? RealDetailRepository()
        self.favoritesRepository = favoritesRepository ?? RealFavoritesRepository()
        self.profileRepository = profileRepository ?? RealProfileRepository()
        self.memberRepository = memberRepository ?? RealMemberRepository()

        // 未完成真实接入的模块：保持原有注入方式
        self.vipRepository = vipRepository
        self.coinRewardRepository = coinRewardRepository
        self.adConfigRepository = adConfigRepository
        self.adRewardRepository = adRewardRepository
        self.adService = adService ?? RealAdService.shared

        // Analytics：使用真实 Client
        self.discoveryAnalytics = discoveryAnalytics ?? DiscoveryAnalyticsClient()

        // BookmarkStore：使用选定的 favoritesRepository + analytics
        self.bookmarkStore = BookmarkStore(
            repository: self.favoritesRepository,
            analytics: self.discoveryAnalytics
        )
        // WatchProgressReporter：使用选定的 favoritesRepository
        self.watchProgressReporter = WatchProgressReporter(
            repository: self.favoritesRepository
        )
    }
}
