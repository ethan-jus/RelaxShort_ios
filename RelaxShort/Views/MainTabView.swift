import SwiftUI

// MARK: - Main Tab View

/// 单NavigationStack + 自定义悬浮TabBar架构
/// 外层一个NavigationStack管理所有push导航，Tab切换用ZStack叠加内容 + 悬浮TabBar
///
/// ViewModel 实例保持在 MainTabView 级别，Tab 切换不丢失状态。
///
/// 二级页面（搜索/VIP/金币/SeriesPlayer）通过 navigationDestination push，系统原生返回按钮。
///
/// 架构要点：Tab 内容提取为独立 TabContentHost，隔离导航状态变化，
/// 避免 showSearch/navigationTarget 变化导致 Tab 内容失去 SwiftUI identity。
struct MainTabView: View {
    @EnvironmentObject var appStore: AppStore

    @StateObject private var homeVM = HomeViewModel(repository: MockHomeRepository())
    @StateObject private var recommendVM = RecommendViewModel(repository: MockHomeRepository())
    @StateObject private var recommendSession = RecommendSession()

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // 1. 内容层 — 独立 View 隔离导航状态变化
                    TabContentHost(homeVM: homeVM, recommendVM: recommendVM, recommendSession: recommendSession)
                        .frame(width: geo.size.width, height: geo.size.height)
                    // 2. DramaBox Bottom TabBar
                    DramaBoxBottomTabBar(
                        selectedTab: $appStore.selectedTab,
                        transparent: appStore.selectedTab == .forYou,
                        bottomInset: geo.safeAreaInsets.bottom
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SeriesPlayerNav.self) { nav in
                SeriesPlayerView(drama: nav.drama, startEpisode: nav.startEpisode)
            }
            .navigationDestination(item: $appStore.navigationTarget) { nav in
                SeriesPlayerView(drama: nav.drama, startEpisode: nav.startEpisode)
            }
            .navigationDestination(isPresented: $appStore.isShowingSearch) {
                SearchView()
            }
            .navigationDestination(isPresented: $appStore.isShowingMembership) {
                MembershipView()
            }
            // CoinRewardView is now a bottom tab; no longer a push destination
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

// MARK: - Tab Content Host

/// 常驻所有 Tab 视图，通过 opacity/zIndex/disabled 控制可见性
/// 对标 DramaBox / TikTok 架构，确保视频播放状态不丢失
///
/// 从 MainTabView 中独立出来，隔离导航状态（showSearch 等）变化 —
/// 导航状态变化只触发 MainTabView 重建，不影响 TabContentHost 的 SwiftUI identity。
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

            RecommendView(viewModel: recommendVM, session: recommendSession)
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
