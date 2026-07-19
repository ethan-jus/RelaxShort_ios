import SwiftUI
import AVFoundation
import GoogleMobileAds
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
    @StateObject private var dependencies = DependencyContainer()
    @StateObject private var playerCoordinator = PlayerCoordinator()
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var adService = RealAdService.shared

    /// 控制启动页 → 主界面的过渡
    @State private var showSplash = true
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

        // 注册测试设备，确保真机+模拟器调试时都能加载测试广告
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
            "00008130-001128D23A2A001C"   // iPhone 15 Pro Max
        ]
        // testDeviceIdentifiers 必须在 start() 之前设置
        GADMobileAds.sharedInstance().start { status in
            print("🦐 [AdMob] SDK 初始化完成")
            DispatchQueue.main.async {
                RealAdService.shared.isSDKReady = true
                Task {
                    await RealAdService.shared.prepareAds()
                }
            }
        }
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
                if showSplash {
                    SplashView(onFinish: finishColdStart, autoFinishAfter: nil)
                    .transition(.opacity)
                } else {
                    MainTabView(playerCoordinator: playerCoordinator, dependencies: dependencies)
                        .environmentObject(appStore)
                        .environmentObject(authStore)
                        .environmentObject(coinStore)
                        .environmentObject(rewardSummaryStore)
                        .environmentObject(storeKit)
                        .environmentObject(dependencies)
                        .environmentObject(themeManager)
                        .transition(.opacity)
                }

            }
            .preferredColorScheme(appStore.preferredColorScheme)
            .statusBarHidden(true)
            // 挂在稳定根视图上，避免 Splash 退出时取消尚未完成的 app/init。
            .task {
                guard !AppRuntimeEnvironment.isUnitTesting else { return }
                await AppInitService.shared.initialize()
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

    private func runColdStartAdFlow() async {
        try? await Task.sleep(for: .seconds(AdConfig.brandingDuration))

        let deadline = Date().addingTimeInterval(AdConfig.coldStartLoadTimeout)
        while !adService.isAppOpenAdReady && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard showSplash, scenePhase == .active else {
            finishColdStart()
            return
        }
        if adService.isAppOpenAdReady {
            adService.showAppOpenAd(onDismiss: finishColdStart)
        } else {
            finishColdStart()
        }
    }

    private func handleForegroundAd() {
        guard adService.consumeBackgroundAppOpenOpportunity() else { return }
        guard adService.isAppOpenAdReady else {
            Task { await adService.prepareAds() }
            return
        }
        adService.showAppOpenAd(onDismiss: {})
    }

    private func finishColdStart() {
        guard showSplash else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            showSplash = false
        }
    }

    /// 补偿购买后崩溃、断网或后端暂时失败留下的未完成真实 Apple 交易。
    private func synchronizePendingStoreKitTransactions() async {
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
