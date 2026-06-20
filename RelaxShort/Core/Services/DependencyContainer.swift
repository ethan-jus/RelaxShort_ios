import Foundation

// MARK: - Dependency Container
/// 集中管理所有 Repository 依赖注入。
/// 在 `RelaxShortApp.swift` 中创建为 `@StateObject`，通过 `.environmentObject()` 传递。
///
/// Mock/Real 切换：通过 UserDefaults 键 `use_real_api` 控制。
/// - `false` / 未设置 → 使用 Mock（默认）
/// - `true` → Home & Detail 使用真实后端 `/api/v2/**`
///
/// Debug 下可在代码中切换，也可通过 UserDefaults 命令行设置：
/// `defaults write com.relaxshort.ios use_real_api -bool true`
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

    // MARK: - Toggle

    /// 是否使用真实 API（UserDefaults 驱动，默认 false=Mock）
    static var useRealAPI: Bool {
        UserDefaults.standard.bool(forKey: "use_real_api")
    }

    // MARK: - Init

    init(
        homeRepository: HomeRepositoryProtocol? = nil,
        searchRepository: SearchRepositoryProtocol = MockSearchRepository(),
        detailRepository: DetailRepositoryProtocol? = nil,
        favoritesRepository: FavoritesRepositoryProtocol = MockFavoritesRepository(),
        profileRepository: ProfileRepositoryProtocol = MockProfileRepository(),
        authRepository: AuthRepositoryProtocol = MockAuthRepository(),
        vipRepository: VIPRepositoryProtocol = MockVIPRepository(),
        coinRewardRepository: CoinRewardRepositoryProtocol = MockCoinRewardRepository()
    ) {
        // Home：根据开关选择 Real 或 Mock
        if let hr = homeRepository {
            self.homeRepository = hr
        } else {
            self.homeRepository = Self.useRealAPI ? RealHomeRepository() : MockHomeRepository()
        }
        // Detail：根据开关选择 Real 或 Mock
        if let dr = detailRepository {
            self.detailRepository = dr
        } else {
            self.detailRepository = Self.useRealAPI ? RealDetailRepository() : MockDetailRepository()
        }
        self.searchRepository = searchRepository
        self.favoritesRepository = favoritesRepository
        self.profileRepository = profileRepository
        self.authRepository = authRepository
        self.vipRepository = vipRepository
        self.coinRewardRepository = coinRewardRepository
    }
}
