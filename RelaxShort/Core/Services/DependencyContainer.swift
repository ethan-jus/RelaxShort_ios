import Foundation

// MARK: - Dependency Container
/// 集中管理所有 Repository 依赖注入。
/// 在 `RelaxShortApp.swift` 中创建为 `@StateObject`，通过 `.environmentObject()` 传递。
/// 切换 Mock / Real 实现只需修改此文件的工厂方法。
@MainActor
final class DependencyContainer: ObservableObject {

    // MARK: - Repositories

    let homeRepository: HomeRepositoryProtocol
    let searchRepository: SearchRepositoryProtocol
    let detailRepository: DetailRepositoryProtocol
    let favoritesRepository: FavoritesRepositoryProtocol
    let profileRepository: ProfileRepositoryProtocol
    let authRepository: AuthRepositoryProtocol
    let vipRepository: VIPRepositoryProtocol
    let coinRewardRepository: CoinRewardRepositoryProtocol

    // MARK: - Init

    init(
        homeRepository: HomeRepositoryProtocol = MockHomeRepository(),
        searchRepository: SearchRepositoryProtocol = MockSearchRepository(),
        detailRepository: DetailRepositoryProtocol = MockDetailRepository(),
        favoritesRepository: FavoritesRepositoryProtocol = MockFavoritesRepository(),
        profileRepository: ProfileRepositoryProtocol = MockProfileRepository(),
        authRepository: AuthRepositoryProtocol = MockAuthRepository(),
        vipRepository: VIPRepositoryProtocol = MockVIPRepository(),
        coinRewardRepository: CoinRewardRepositoryProtocol = MockCoinRewardRepository()
    ) {
        self.homeRepository = homeRepository
        self.searchRepository = searchRepository
        self.detailRepository = detailRepository
        self.favoritesRepository = favoritesRepository
        self.profileRepository = profileRepository
        self.authRepository = authRepository
        self.vipRepository = vipRepository
        self.coinRewardRepository = coinRewardRepository
    }
}
