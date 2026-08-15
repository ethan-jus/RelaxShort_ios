import SwiftUI
import AVFoundation
import GoogleSignIn

enum AppAudioSessionConfiguration {
    static let category: AVAudioSession.Category = .playback
    static let mode: AVAudioSession.Mode = .moviePlayback

    // `.allowAirPlay` 只适用于 `.playAndRecord`；纯播放类别本身已支持 AirPlay。
    static let options: AVAudioSession.CategoryOptions = []
}

@main
struct RelaxShortApp: App {
    @UIApplicationDelegateAdaptor(FacebookAppDelegate.self)
    private var facebookAppDelegate

    @StateObject private var appStore = AppStore()
    @StateObject private var authStore = AuthStore()
    @StateObject private var coinStore = CoinStore()
    @StateObject private var rewardSummaryStore = RewardSummaryStore()
    @StateObject private var storeKit = StoreKitManager()
    @StateObject private var updateCoordinator = AppUpdateCoordinator()
    @StateObject private var dependencies = DependencyContainer()
    @StateObject private var playerCoordinator = PlayerCoordinator()
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var adService = RealAdService.shared

    /// 控制启动页 → 主界面的过渡
    @State private var showSplash = true
    @State private var showForegroundAdTransition = false
    @State private var foregroundAdTask: Task<Void, Never>?
    @State private var suppressForegroundAdUntil: Date?
    @State private var isSynchronizingPendingStoreKitTransactions = false
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Init

    init() {
        if let commit = Bundle.main.object(forInfoDictionaryKey: "BuildCommit") as? String {
            print("BuildCommit=\(commit)")
        }
        configureAudioSession()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "1003872687588-5fij4u8cr2dr9plm6tbg0gfq19gj68r7.apps.googleusercontent.com",
            serverClientID: "1003872687588-8518sh0gca5q8ei5a1d93pj0vlj36n1i.apps.googleusercontent.com"
        )

    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                AppAudioSessionConfiguration.category,
                mode: AppAudioSessionConfiguration.mode,
                options: AppAudioSessionConfiguration.options
            )
            try session.setActive(true)
        } catch {
            print("[PlayerKit] audioSession configure failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 主界面始终在品牌页下方预构建，让 Home 数据和首屏封面利用品牌展示时间加载。
                MainTabView(playerCoordinator: playerCoordinator, dependencies: dependencies)
                    .environmentObject(appStore)
                    .environmentObject(authStore)
                    .environmentObject(coinStore)
                    .environmentObject(rewardSummaryStore)
                    .environmentObject(storeKit)
                    .environmentObject(dependencies)
                    .environmentObject(themeManager)
                    .opacity(showSplash ? 0 : 1)
                    .disabled(showSplash)
                    .accessibilityHidden(showSplash)

                if showSplash {
                    SplashView(onFinish: finishColdStart, autoFinishAfter: nil)
                        .transition(.opacity)
                }

                if showForegroundAdTransition {
                    ForegroundAdTransitionView()
                        .transition(.opacity)
                        .zIndex(2)
                }

                if let update = updateCoordinator.presentation {
                    AppUpdatePromptView(
                        presentation: update,
                        coordinator: updateCoordinator
                    )
                    .zIndex(10)
                }

            }
            .id(appStore.language)
            .environment(\.locale, Locale(identifier: appStore.language.rawValue))
            .environment(
                \.layoutDirection,
                appStore.language.isRTL ? .rightToLeft : .leftToRight
            )
            .preferredColorScheme(appStore.preferredColorScheme)
            .statusBarHidden(true)
            // 挂在稳定根视图上，避免 Splash 退出时取消尚未完成的 app/init。
            .task {
                guard !AppRuntimeEnvironment.isUnitTesting else { return }
                // 版本门禁属于启动安全策略，立即并发获取；不等开屏广告或品牌页结束。
                if let result = await AppInitService.shared.initialize() {
                    updateCoordinator.handle(result.update)
                }
            }
            .task {
                guard !AppRuntimeEnvironment.isUnitTesting else { return }
                // 只让出一次首帧调度，随后立即启动 UMP；获准后优先加载开屏广告。
                await Task.yield()
                guard !Task.isCancelled else { return }
                await PrivacyConsentManager.shared.gatherConsentAndStartAds()
            }
            .task {
                guard !AppRuntimeEnvironment.isUnitTesting else { return }
                await runColdStartAdFlow()
            }
            .task {
                guard !AppRuntimeEnvironment.isUnitTesting else { return }
                await authStore.bootstrap()
                await synchronizePendingStoreKitTransactions()
            }
            .onOpenURL { url in
                // 热启动深链应直接进入目标内容，不在路由前插入广告。
                if !showSplash {
                    suppressForegroundAdUntil = Date().addingTimeInterval(
                        AdConfig.foregroundAdDeepLinkSuppressionDuration
                    )
                    foregroundAdTask?.cancel()
                    foregroundAdTask = nil
                    hideForegroundAdTransition()
                }
                if !GIDSignIn.sharedInstance.handle(url) {
                    handleDeepLink(url)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && !showSplash {
                    dependencies.discoveryAnalytics.flushPending()
                    handleForegroundAd()
                    Task { await synchronizePendingStoreKitTransactions() }
                }
                if newPhase == .background {
                    foregroundAdTask?.cancel()
                    foregroundAdTask = nil
                    showForegroundAdTransition = false
                    dependencies.discoveryAnalytics.flushForBackground()
                    // 短任务上报观看进度
                    Task {
                        await dependencies.watchProgressReporter.finalize(completed: false)
                    }
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        if let inviteCode = RewardDeepLink.parseInviteCode(url) {
            appStore.pendingInviteCode = inviteCode
            appStore.selectedTab = .home
            appStore.isShowingRewards = true
            return
        }
        guard let route = RewardDeepLink.parse(url) else { return }
        Task { @MainActor in
            do {
                let drama = try await dependencies.detailRepository.fetchDramaDetail(id: route.seriesID)
                appStore.selectedTab = .home
                appStore.navigationTarget = SeriesPlayerNav(
                    drama: drama,
                    startEpisode: route.episodeNumber ?? 1,
                    sourceScene: "shared_link"
                )
            } catch {
                Logger.viewModel.warning("Deep link failed: \(error.localizedDescription)")
            }
        }
    }

    /// 冷启动保留一次开屏广告机会，但总等待时间有硬上限。
    /// 超时后广告继续在后台预加载，只供后续热启动使用，绝不进入首页后补弹。
    private func runColdStartAdFlow() async {
        let startedAt = CACurrentMediaTime()
        let deadline = startedAt
            + AdConfig.brandingDuration
            + AdConfig.coldStartAdLoadTimeout
        try? await Task.sleep(for: .seconds(AdConfig.brandingDuration))
        guard !Task.isCancelled else { return }

        while CACurrentMediaTime() < deadline {
            guard showSplash else { return }
            // `.inactive` 也可能只是 UMP/系统弹窗切换，不能误判成用户离开 App。
            guard scenePhase != .background else {
                let elapsed = (CACurrentMediaTime() - startedAt) * 1000
                Logger.store.info("冷启动已进入后台，放弃开屏广告，耗时=\(Int(elapsed))ms")
                finishColdStart()
                return
            }

            if PrivacyConsentManager.shared.isConsentFlowComplete {
                guard PrivacyConsentManager.shared.isAdRequestAllowed else {
                    let elapsed = (CACurrentMediaTime() - startedAt) * 1000
                    Logger.store.info("冷启动未获广告请求许可，直接进入首页，耗时=\(Int(elapsed))ms")
                    finishColdStart()
                    return
                }
                if adService.isAppOpenAdReady {
                    let elapsed = (CACurrentMediaTime() - startedAt) * 1000
                    Logger.store.info("冷启动开屏广告已就绪，准备耗时=\(Int(elapsed))ms")
                    adService.showAppOpenAd(onDismiss: finishColdStart)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let elapsed = (CACurrentMediaTime() - startedAt) * 1000
        Logger.store.info("冷启动开屏广告超时，直接进入首页，耗时=\(Int(elapsed))ms")
        finishColdStart()
    }

    private func handleForegroundAd() {
        guard adService.consumeBackgroundAppOpenOpportunity() else { return }
        foregroundAdTask?.cancel()
        guard !isForegroundAdSuppressed else {
            suppressForegroundAdUntil = nil
            Logger.store.info("热启动开屏已跳过：正在处理深链")
            return
        }
        suppressForegroundAdUntil = nil
        guard PrivacyConsentManager.shared.isAdRequestAllowed else { return }
        guard isSafeForegroundAdSurface,
              adService.canPresentAppOpenAdFromRoot else {
            Logger.store.info("热启动开屏已跳过：当前不是安全根页面")
            return
        }
        guard adService.isAppOpenAdReady else {
            // 未就绪时只预加载下一次，不在用户已经开始操作后补弹。
            Task { await adService.prepareAds() }
            return
        }

        // 广告已就绪才遮住当前页面，避免恢复后先暴露可交互内容再突然盖广告。
        withAnimation(.easeOut(duration: 0.1)) {
            showForegroundAdTransition = true
        }
        foregroundAdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(AdConfig.foregroundAdTransitionDuration))
            guard !Task.isCancelled,
                  scenePhase == .active,
                  !isForegroundAdSuppressed,
                  isSafeForegroundAdSurface,
                  adService.canPresentAppOpenAdFromRoot else {
                hideForegroundAdTransition()
                return
            }
            adService.showAppOpenAd(onDismiss: hideForegroundAdTransition)
        }
    }

    private var isForegroundAdSuppressed: Bool {
        guard let deadline = suppressForegroundAdUntil else { return false }
        return deadline > Date()
    }

    private var isSafeForegroundAdSurface: Bool {
        guard appStore.navigationTarget == nil,
              !appStore.isShowingSearch,
              !appStore.isShowingMembership,
              !appStore.isShowingRewards,
              !appStore.isBottomTabBarHidden else {
            return false
        }
        switch appStore.selectedTab {
        case .home, .myList, .profile:
            return true
        case .forYou, .member:
            return false
        }
    }

    private func hideForegroundAdTransition() {
        foregroundAdTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            showForegroundAdTransition = false
        }
    }

    private func finishColdStart() {
        guard showSplash else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            showSplash = false
        }
        adService.markColdStartFinished()
    }

    /// 补偿购买后崩溃、断网或后端暂时失败留下的未完成真实 Apple 交易。
    private func synchronizePendingStoreKitTransactions() async {
        guard !isSynchronizingPendingStoreKitTransactions else { return }
        isSynchronizingPendingStoreKitTransactions = true
        defer { isSynchronizingPendingStoreKitTransactions = false }

        // 绝大多数启动没有未完成交易；先查本地 StoreKit，避免每次冷/热启动都请求账户令牌。
        guard await storeKit.hasUnfinishedBackendTransactions() else { return }
        do {
            let token = try await dependencies.detailRepository.fetchAppleAccountToken()
            let receipts = await storeKit.unfinishedPurchaseReceipts(appAccountToken: token)
            for receipt in receipts {
                do {
                    if ProductID(rawValue: receipt.productID)?.isCoinPackage == true {
                        let balance = try await dependencies.detailRepository.verifyCoinPurchase(receipt)
                        await storeKit.completeCoinDelivery(receipt)
                        coinStore.synchronize(balance: balance)
                    } else {
                        let account = try await dependencies.detailRepository.verifyVIPPurchase(receipt)
                        guard account.isVIP else { continue }
                        await storeKit.completeVIPDelivery(receipt)
                        coinStore.synchronize(balance: account.balance)
                    }
                } catch {
                    Logger.store.warning("StoreKit pending delivery failed for \(receipt.productID): \(error.localizedDescription)")
                }
            }
        } catch {
            Logger.store.warning("StoreKit pending sync unavailable: \(error.localizedDescription)")
        }
    }
}

/// 热启动广告的品牌承接页：只在广告已就绪时出现，不额外拉长等待。
private struct ForegroundAdTransitionView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("RelaxShort")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .allowsHitTesting(true)
        .accessibilityHidden(true)
    }
}
