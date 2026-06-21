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

    @StateObject private var playerCoordinator: PlayerCoordinator
    @StateObject private var homeVM: HomeViewModel
    @StateObject private var recommendVM: RecommendViewModel
    @StateObject private var recommendSession: RecommendSession

    init() {
        let coordinator = PlayerCoordinator()
        let homeRepo = DependencyContainer.useRealAPI
            ? RealHomeRepository() as HomeRepositoryProtocol
            : MockHomeRepository() as HomeRepositoryProtocol
        _playerCoordinator = StateObject(wrappedValue: coordinator)
        _homeVM = StateObject(wrappedValue: HomeViewModel(repository: homeRepo))
        _recommendVM = StateObject(wrappedValue: RecommendViewModel(repository: homeRepo))
        _recommendSession = StateObject(wrappedValue: RecommendSession(engine: coordinator.engine))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    TabContentHost(homeVM: homeVM, recommendVM: recommendVM, recommendSession: recommendSession)
                        .environmentObject(playerCoordinator)
                        .frame(width: geo.size.width, height: geo.size.height)
                    // 2. 底部标签栏
                    if !appStore.isBottomTabBarHidden {
                        DramaBoxBottomTabBar(
                            selectedTab: $appStore.selectedTab,
                            transparent: appStore.selectedTab == .forYou,
                            bottomInset: geo.safeAreaInsets.bottom
                        )
                        .transition(.opacity)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SeriesPlayerNav.self) { nav in
                SeriesPlayerView(drama: nav.drama, startEpisode: nav.startEpisode, handoff: nav.handoff)
                    .environmentObject(playerCoordinator)
            }
            .navigationDestination(item: $appStore.navigationTarget) { nav in
                SeriesPlayerView(drama: nav.drama, startEpisode: nav.startEpisode, handoff: nav.handoff)
                    .environmentObject(playerCoordinator)
            }
            .navigationDestination(isPresented: $appStore.isShowingSearch) {
                SearchView()
            }
            .navigationDestination(isPresented: $appStore.isShowingMembership) {
                MembershipView()
            }
            // 金币福利页已调整为底部标签，不再作为入栈页面
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
    let homeVM: HomeViewModel
    let recommendVM: RecommendViewModel
    let recommendSession: RecommendSession

    var body: some View {
        ZStack {
            HomeView(viewModel: homeVM)
                .id(AppStore.Tab.home.rawValue)
                .zIndex(appStore.selectedTab == .home ? 1 : 0)
                .opacity(appStore.selectedTab == .home ? 1 : 0)
                .disabled(appStore.selectedTab != .home)

            RecommendView(viewModel: recommendVM, session: recommendSession, isVisible: appStore.selectedTab == .forYou)
                .id(AppStore.Tab.forYou.rawValue)
                .zIndex(appStore.selectedTab == .forYou ? 1 : 0)
                .opacity(appStore.selectedTab == .forYou ? 1 : 0)
                .disabled(appStore.selectedTab != .forYou)

            MembershipView(mode: .tab)
                .id(AppStore.Tab.member.rawValue)
                .zIndex(appStore.selectedTab == .member ? 1 : 0)
                .opacity(appStore.selectedTab == .member ? 1 : 0)
                .disabled(appStore.selectedTab != .member)

            FavoritesView()
                .id(AppStore.Tab.myList.rawValue)
                .zIndex(appStore.selectedTab == .myList ? 1 : 0)
                .opacity(appStore.selectedTab == .myList ? 1 : 0)
                .disabled(appStore.selectedTab != .myList)

            ProfileView()
                .id(AppStore.Tab.profile.rawValue)
                .zIndex(appStore.selectedTab == .profile ? 1 : 0)
                .opacity(appStore.selectedTab == .profile ? 1 : 0)
                .disabled(appStore.selectedTab != .profile)
        }
    }
}
