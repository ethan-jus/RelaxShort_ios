import SwiftUI
import AVFoundation
import GoogleMobileAds

@main
struct RelaxShortApp: App {
    @StateObject private var appStore = AppStore()
    @StateObject private var authStore = AuthStore()
    @StateObject private var coinStore = CoinStore()
    @StateObject private var storeKit = StoreKitManager()
    @StateObject private var dependencies = DependencyContainer()
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var adService = RealAdService.shared

    /// 控制启动页 → 主界面的过渡
    @State private var showSplash = true
    /// 热启动 Splash 覆盖层
    @State private var showHotStartSplash = false
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Init

    init() {
        configureAudioSession()

        // 注册测试设备，确保真机+模拟器调试时都能加载测试广告
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
            "00008130-001128D23A2A001C"   // iPhone 15 Pro Max
        ]
        // testDeviceIdentifiers 必须在 start() 之前设置
        GADMobileAds.sharedInstance().start { status in
            print("🦐 [AdMob] SDK 初始化完成")
            DispatchQueue.main.async {
                RealAdService.shared.isSDKReady = true
            }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            print("[PlayerKit] audioSession configure failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                    // Task13: 启动页期间调用 app/init，不阻塞进入主界面
                    .task {
                        await AppInitService.shared.initialize()
                    }
                } else {
                    MainTabView()
                        .environmentObject(appStore)
                        .environmentObject(authStore)
                        .environmentObject(coinStore)
                        .environmentObject(storeKit)
                        .environmentObject(dependencies)
                        .environmentObject(themeManager)
                        .transition(.opacity)
                }

                // 热启动 Splash 覆盖层
                if showHotStartSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showHotStartSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .preferredColorScheme(appStore.preferredColorScheme)
            .statusBarHidden(true)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && !showSplash {
                    handleHotStartAd()
                }
            }
        }
    }

    private func handleHotStartAd() {
        guard adService.wasInBackground else { return }
        guard adService.shouldShowAppOpen, !showHotStartSplash else { return }
        showHotStartSplash = true
    }
}
