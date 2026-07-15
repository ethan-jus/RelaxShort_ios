import SwiftUI

// MARK: - 主标签视图

/// 单导航栈和自定义悬浮标签栏架构
/// 外层一个导航栈管理所有入栈导航，标签切换用叠加内容和悬浮标签栏实现
///
/// 视图模型实例保持在主标签视图级别，标签切换不丢失状态。
///
/// 二级页面通过导航目标入栈，使用系统原生返回按钮。
///
/// 架构要点：标签内容提取为独立内容容器，隔离导航状态变化，
/// 避免搜索和播放页导航状态变化导致标签内容失去视图身份。
struct MainTabView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var dependencies: DependencyContainer

    @ObservedObject private var playerCoordinator: PlayerCoordinator
    @StateObject private var homeVM: HomeViewModel
    @StateObject private var recommendVM: RecommendViewModel
    @StateObject private var recommendSession: RecommendSession

    init(playerCoordinator: PlayerCoordinator, dependencies: DependencyContainer) {
        self.playerCoordinator = playerCoordinator
        _homeVM = StateObject(wrappedValue: HomeViewModel(repository: dependencies.homeRepository))
        _recommendVM = StateObject(wrappedValue: RecommendViewModel(repository: dependencies.homeRepository))
        // For You 常驻预加载，但 App 默认进入 Home，必须等用户切入后才取得播放权。
        _recommendSession = StateObject(
            wrappedValue: RecommendSession(coordinator: playerCoordinator, playbackEnabled: false)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                TabContentHost(
                    homeVM: homeVM,
                    homeRepository: dependencies.homeRepository,
                    recommendVM: recommendVM,
                    recommendSession: recommendSession
                )
                .environmentObject(playerCoordinator)
                .ignoresSafeArea(edges: .bottom)

                if !appStore.isBottomTabBarHidden {
                    DramaBoxBottomTabBar(
                        selectedTab: $appStore.selectedTab,
                        transparent: appStore.selectedTab == .forYou
                    )
                    .transition(.opacity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SeriesPlayerNav.self) { nav in
                SeriesPlayerView(
                    drama: nav.drama,
                    startEpisode: nav.startEpisode,
                    initialEpisodeID: nav.episodeID,
                    initialResumeTime: nav.resumeTime,
                    handoff: nav.handoff,
                    sourceScene: nav.sourceScene
                )
                    .environmentObject(playerCoordinator)
            }
            .navigationDestination(item: $appStore.navigationTarget) { nav in
                SeriesPlayerView(
                    drama: nav.drama,
                    startEpisode: nav.startEpisode,
                    initialEpisodeID: nav.episodeID,
                    initialResumeTime: nav.resumeTime,
                    handoff: nav.handoff,
                    sourceScene: nav.sourceScene
                )
                    .environmentObject(playerCoordinator)
            }
            .navigationDestination(isPresented: $appStore.isShowingSearch) {
                SearchView(
                    searchRepository: dependencies.searchRepository,
                    discoveryRepository: dependencies.homeRepository,
                    analytics: dependencies.discoveryAnalytics
                )
            }
            .navigationDestination(isPresented: $appStore.isShowingMembership) {
                MemberView(
                    mode: .push,
                    repository: dependencies.memberRepository
                )
            }
        }
        .persistentSystemOverlays(appStore.selectedTab == .forYou ? .hidden : .visible)
        .onReceive(NotificationCenter.default.publisher(for: .showSearch)) { _ in
            appStore.isShowingSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMembership)) { _ in
            appStore.isShowingMembership = true
        }
    }
}

// MARK: - 标签内容容器

/// 常驻所有标签视图，通过透明度、层级和禁用状态控制可见性
/// 对标短视频应用架构，确保视频播放状态不丢失
///
/// 从主标签视图中独立出来，隔离导航状态变化。
/// 导航状态变化只触发主标签视图重建，不影响标签内容容器的视图身份。
private struct TabContentHost: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var dependencies: DependencyContainer
    let homeVM: HomeViewModel
    let homeRepository: HomeRepositoryProtocol
    let recommendVM: RecommendViewModel
    let recommendSession: RecommendSession

    var body: some View {
        ZStack {
            HomeView(viewModel: homeVM, rankingRepository: homeRepository)
                .id(AppStore.Tab.home.rawValue)
                .zIndex(appStore.selectedTab == .home ? 1 : 0)
                .opacity(appStore.selectedTab == .home ? 1 : 0)
                .disabled(appStore.selectedTab != .home)

            RecommendView(viewModel: recommendVM, session: recommendSession, isVisible: appStore.selectedTab == .forYou)
                .id(AppStore.Tab.forYou.rawValue)
                .zIndex(appStore.selectedTab == .forYou ? 1 : 0)
                .opacity(appStore.selectedTab == .forYou ? 1 : 0)
                .disabled(appStore.selectedTab != .forYou)

            /// Task32：底部 Member Tab 使用新的 MemberView（Real-only）
            MemberView(
                mode: .tab,
                repository: dependencies.memberRepository
            )
                .id(AppStore.Tab.member.rawValue)
                .zIndex(appStore.selectedTab == .member ? 1 : 0)
                .opacity(appStore.selectedTab == .member ? 1 : 0)
                .disabled(appStore.selectedTab != .member)

            FavoritesView(viewModel: FavoritesViewModel(
                repository: dependencies.favoritesRepository,
                bookmarkStore: dependencies.bookmarkStore,
                homeRepository: dependencies.homeRepository
            ))
                .id(AppStore.Tab.myList.rawValue)
                .zIndex(appStore.selectedTab == .myList ? 1 : 0)
                .opacity(appStore.selectedTab == .myList ? 1 : 0)
                .disabled(appStore.selectedTab != .myList)

            ProfileView(viewModel: ProfileViewModel(repository: dependencies.profileRepository))
                .id(AppStore.Tab.profile.rawValue)
                .zIndex(appStore.selectedTab == .profile ? 1 : 0)
                .opacity(appStore.selectedTab == .profile ? 1 : 0)
                .disabled(appStore.selectedTab != .profile)
        }
    }
}
