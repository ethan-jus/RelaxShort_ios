import SwiftUI
import AVKit
import UIKit

/// Series 的播放器冷启动必须等系统导航转场结束，避免 AVFoundation 首次初始化阻塞 push 动画。
private struct NavigationTransitionCompletionObserver: UIViewControllerRepresentable {
    let onCompletion: @MainActor () -> Void

    func makeUIViewController(context: Context) -> ObserverViewController {
        ObserverViewController(onCompletion: onCompletion)
    }

    func updateUIViewController(_ controller: ObserverViewController, context: Context) {
        controller.onCompletion = onCompletion
    }

    final class ObserverViewController: UIViewController {
        var onCompletion: @MainActor () -> Void
        private var hasCompleted = false
        private var hasRegisteredTransition = false

        init(onCompletion: @escaping @MainActor () -> Void) {
            self.onCompletion = onCompletion
            super.init(nibName: nil, bundle: nil)
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !hasRegisteredTransition else { return }
            guard let coordinator = transitionCoordinator
                ?? navigationController?.transitionCoordinator
                ?? parent?.transitionCoordinator else { return }
            hasRegisteredTransition = true
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.completeOnce()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // 无转场协调器（预览或直接展示）时，viewDidAppear 仍能提供可靠的完成时机。
            completeOnce()
        }

        private func completeOnce() {
            guard !hasCompleted else { return }
            hasCompleted = true
            Task { @MainActor [onCompletion] in
                onCompletion()
            }
        }
    }
}

enum EpisodeUnlockPanelLayout {
    /// 首层解锁面板统一使用同一高度，VIP 专享与普通付费集不再随内容多少伸缩。
    /// 小屏压缩到约半屏以内；大屏保留足够留白，但不超过 430pt。
    static func primaryHeight(containerHeight: CGFloat) -> CGFloat {
        min(430, max(320, containerHeight * 0.46))
    }

    static func bottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        max(34, safeAreaBottom + 18)
    }
}

// MARK: - Series Player View (接入 ShortVideoPlayerEngine)

struct SeriesPlayerView: View {

    let drama: DramaItem
    let startEpisode: Int
    let initialEpisodeID: String?
    let initialResumeTime: TimeInterval?
    @EnvironmentObject var dependencies: DependencyContainer
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var coinStore: CoinStore
    @EnvironmentObject var storeKitManager: StoreKitManager
    let handoff: PlayerHandoffContext?
    let sourceScene: String
    /// 标记 My List 初始 resume 是否已被消费
    @State private var hasConsumedInitialResume = false

    @State private var currentEpisode: Int
    @StateObject private var pagerState = VerticalVideoPagerState()
    @State private var showSpeedHUD = false
    @State private var showEpisodeList = false
    @State private var episodes: [Episode] = []
    /// 缓存每集的后端 resumeTime，切集时使用当前 episode 的值
    @State private var episodeResumeTimes: [String: TimeInterval] = [:]
    @State private var unlockedEpisodes: Set<Int> = []
    @State private var isUIVisible = true
    @State private var autoHideTask: Task<Void, Never>?
    /// 缓存播放接口返回的媒体源（key = episodeId），避免切回已访问剧集时重复请求。
    @State private var episodeMediaSources: [String: PlayerMediaSource] = [:]
    /// 单一 sheet router，避免多 .sheet 互抢。
    @State private var activeSheet: PlayerSheet?
    /// 购买中心使用播放器内全宽 Overlay，避免系统 Sheet 在新 iOS 上自动产生两侧留白。
    @State private var unlockPurchaseTab: EpisodeUnlockPurchaseTab?
    @State private var isSpeeding = false
    @State private var episodeSwitchTask: Task<Void, Never>?
    @State private var playbackState: PlayerPlaybackState = .idle
    /// 当前目标集的非权益类加载错误。锁集由 unlockState 独立呈现。
    @State private var episodeLoadError: String?
    @State private var playbackProgress = PlayerProgress()
    @State private var selectedPlaybackRate: Float = 1.0
    @State private var selectedQualityID = "auto"
    @State private var hasTrackedImpression = false
    @State private var qualifiedEpisodeIDs: Set<String> = []
    @State private var completedEpisodeIDs: Set<String> = []
    @State private var episodePrefetchTask: Task<Bool, Never>?
    /// 与预取 Task 对应的目标集。切到该集时直接等待同一任务，禁止重复请求 /play。
    @State private var episodePrefetchTarget: Int?
    /// 卡片缺直链时，与剧集列表并行请求目标集播放合同，避免固定的两段串行等待。
    @State private var initialPlayAssetTask: Task<Bool, Never>?
    /// 播放链路耗时追踪：open/switch 开始时间，用于定位接口、播放器、首帧慢点。
    @State private var playbackTraceStartedAt = CACurrentMediaTime()
    @State private var playbackTraceReason = "open"
    /// 锁集状态独占 Series 页面交互；出现后不得继续切集或触发播放器手势。
    @State private var unlockState: EpisodeUnlockFlowState?
    /// 顶部返回动作已提前完成 Series → For You 所有权交接，onDisappear 不再重复释放。
    @State private var hasPreparedReturn = false
    /// 首次 AVPlayer/AVPlayerLayer 创建不得与 NavigationStack 的横向转场竞争主线程。
    @State private var hasCompletedNavigationTransition = false

    private enum ChromeMetrics {
        static let horizontalPadding: CGFloat = 16
        static let actionRailWidth: CGFloat = 50
        static let bottomGap: CGFloat = 10
        static let progressIdleHeight: CGFloat = 14
        static let progressScrubbingHeight: CGFloat = 36
        static let topGapBelowSafeArea: CGFloat = 8
        static let topBarHeight: CGFloat = 44
        static let membershipRowHeight: CGFloat = 30
        static let unlockPurchasePanelFraction: CGFloat = 0.62
        static let purchasePlanRowHeight: CGFloat = 78
    }

    private enum PlayerSheet: Identifiable {
        case share, speed, quality

        var id: String {
            switch self {
            case .share: "share"
            case .speed: "speed"
            case .quality: "quality"
            }
        }
    }

    @EnvironmentObject var playerCoordinator: PlayerCoordinator
    @Environment(\.dismiss) private var dismiss

    /// 剧集列表加载后以接口返回为准；加载前用卡片字段兜底，避免展示不存在的集数。
    private var totalEpisodes: Int { episodes.isEmpty ? max(1, drama.episodeCount) : episodes.count }

    init(
        drama: DramaItem,
        startEpisode: Int? = nil,
        initialEpisodeID: String? = nil,
        initialResumeTime: TimeInterval? = nil,
        handoff: PlayerHandoffContext? = nil,
        sourceScene: String = "unknown"
    ) {
        self.drama = drama
        self.initialEpisodeID = initialEpisodeID
        self.initialResumeTime = initialResumeTime
        self.startEpisode = startEpisode ?? max(1, drama.currentEpisode)
        self.handoff = handoff
        self.sourceScene = sourceScene
        self._currentEpisode = State(initialValue: self.startEpisode)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 底层全屏手势层：空白视频区域点击切换 UI 显隐。
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(longPressGesture)
                    .simultaneousGesture(tapPauseGesture(in: geo))
                    .simultaneousGesture(edgeBackGesture(in: geo))

                // 视频和常规播放 UI 必须位于同一个分页页面内，拖动时整体同步移动。
                episodePager(in: geo)

                if showSpeedHUD {
                    speedProgressOverlay(in: geo)
                        .zIndex(45)
                }

                if showSpeedHUD {
                    SpeedHUDView()
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.16)
                        .transition(.opacity)
                }

                if showEpisodeList, unlockState == nil {
                    EpisodePickerSheet(
                        drama: drama,
                        episodes: episodes,
                        currentEpisode: $currentEpisode,
                        unlockedEpisodes: unlockedEpisodes,
                        isPresented: $showEpisodeList,
                        onSelectEpisode: { ep in
                            showEpisodeList = false
                            requestEpisodeSwitch(ep)
                        }
                    )
                    .zIndex(200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let unlockState {
                    if let unlockPurchaseTab {
                        unlockPurchaseOverlay(
                            unlockState,
                            initialTab: unlockPurchaseTab,
                            in: geo
                        )
                        .zIndex(300)
                    } else {
                        episodeUnlockOverlay(unlockState, in: geo)
                            .zIndex(250)
                    }
                } else if let episodeLoadError {
                    episodeLoadFailureOverlay(episodeLoadError)
                        .zIndex(240)
                }

            }
            .contentShape(Rectangle())
            // 与 For You 共用同一套分页手势；挂在页面根层，避免控制层吃掉拖拽事件。
            .verticalVideoPaging(
                state: pagerState,
                pageCount: totalEpisodes,
                currentIndex: currentEpisode - 1,
                canHandle: canHandleEpisodeDrag,
                onPageCommit: { _, targetIndex in
                    requestEpisodeSwitch(targetIndex + 1, animatePage: false)
                }
            )
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background {
            NavigationTransitionCompletionObserver {
                hasCompletedNavigationTransition = true
            }
            .frame(width: 0, height: 0)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .share:
                ShareSheet(dramaTitle: drama.title)
                    .shareSheetPresentationStyle()
            case .speed:
                PlayerSpeedSheet(
                    selectedRate: selectedPlaybackRate,
                    onSelect: applyPlaybackRate
                )
                    .presentationDetents([.fraction(0.34)])
                    .presentationDragIndicator(.hidden)
            case .quality:
                PlayerQualitySheet(
                    qualities: qualityOptions(),
                    currentQuality: selectedQualityID,
                    onSelect: { qualityID in
                        selectedQualityID = qualityID
                        resetAutoHide()
                    }
                )
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.hidden)
            }
        }
        .task(id: hasCompletedNavigationTransition) {
            guard hasCompletedNavigationTransition else { return }
            await startPlaybackSession()
            await dependencies.bookmarkStore.loadStatus(seriesIDs: [drama.id])
        }
        .onReceive(playerCoordinator.engine.$state) { state in
            playbackState = state
            if state == .playing { resetAutoHide() }
            else if state == .pausedByUser { autoHideTask?.cancel() }
        }
        .onReceive(playerCoordinator.engine.$hasVisiblePlaybackStarted) { started in
            guard started else { return }
            let elapsed = (CACurrentMediaTime() - playbackTraceStartedAt) * 1000
            Logger.player.info("SeriesTrace 首帧可见 原因=\(playbackTraceReason) 当前集=\(currentEpisode) 总耗时=\(Int(elapsed))ms")
        }
        .onReceive(playerCoordinator.engine.$progress) { progress in
            playbackProgress = progress
            trackPlaybackMilestones(progress)
            // 传递进度快照给 reporter（actor 内部节流）
            if progress.duration > 0 {
                Task {
                    await dependencies.watchProgressReporter.observe(
                        seconds: progress.currentTime,
                        duration: progress.duration
                    )
                }
            }
            if let preview = seriesSeekPreviewFraction, progress.duration > 0 {
                let actual = CGFloat(progress.currentTime / progress.duration)
                if abs(actual - preview) < 0.02 {
                    seriesSeekPreviewFraction = nil
                }
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
            episodeSwitchTask?.cancel()
            episodePrefetchTask?.cancel()
            initialPlayAssetTask?.cancel()
            Task { await dependencies.watchProgressReporter.finalize(completed: false) }
            if !hasPreparedReturn {
                playerCoordinator.release(.series(dramaID: drama.id))
            }
        }
    }

    /// 网络或媒体失败不阻断上下滑动；用户可以重试当前集，也可以继续浏览其他集。
    private func episodeLoadFailureOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Retry") {
                retryCurrentEpisodePlayback()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .frame(height: 42)
            .background(.white, in: Capsule())
            Text("You can also swipe to another episode")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(20)
        .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Episode Unlock

    @ViewBuilder
    private func episodeUnlockOverlay(_ state: EpisodeUnlockFlowState, in geo: GeometryProxy) -> some View {
        // 以普通锁集挽留层的标准高度为基准统一顶部位置；VIP 内容更少时只缩短底部，不改变起点。
        let standardRetentionHeight: CGFloat = 206
        let upwardAdjustment: CGFloat = 32
        let retentionBottomInset = max(geo.safeAreaInsets.bottom + 44, geo.size.height * 0.1)
        let retentionTopInset = max(
            geo.safeAreaInsets.top + 24,
            geo.size.height - retentionBottomInset - standardRetentionHeight - upwardAdjustment
        )

        ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            switch state.presentation {
            case .primary:
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    unlockPrimaryPanel(
                        state,
                        containerHeight: geo.size.height,
                        safeBottom: geo.safeAreaInsets.bottom
                    )
                        .frame(width: geo.size.width)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            case .retention:
                unlockRetentionDialog(state)
                    .frame(width: min(geo.size.width - 40, 420))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, retentionTopInset)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            case .lockedFrame:
                unlockFinalLockedFrame()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(true)
    }

    /// 金币与 VIP 购买中心共用播放器内的全宽底部面板，不再依赖系统浮动 Sheet。
    private func unlockPurchaseOverlay(
        _ state: EpisodeUnlockFlowState,
        initialTab: EpisodeUnlockPurchaseTab,
        in geo: GeometryProxy
    ) -> some View {
        let panelHeight = max(
            460,
            min(620, geo.size.height * ChromeMetrics.unlockPurchasePanelFraction)
                - ChromeMetrics.purchasePlanRowHeight
        )

        return ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                EpisodeUnlockPurchaseSheet(
                    coinStore: coinStore,
                    storeKit: storeKitManager,
                    coinCost: state.coinCost,
                    balance: state.balance,
                    initialTab: initialTab,
                    safeAreaBottom: geo.safeAreaInsets.bottom,
                    onDismiss: dismissUnlockPurchaseCenter,
                    verifyCoinPurchase: { receipt in
                        try await dependencies.detailRepository.verifyCoinPurchase(receipt)
                    },
                    verifyVIPPurchase: { receipt in
                        try await dependencies.detailRepository.verifyVIPPurchase(receipt)
                    },
                    refreshAccount: {
                        try await dependencies.detailRepository.fetchUnlockAccount()
                    },
                    onCoinPurchaseCompleted: { balance in
                        if var latest = unlockState {
                            latest.balance = balance
                            latest.selection = .coins
                            unlockState = latest
                        }
                        unlockPurchaseTab = nil
                        Task { await performUnlock(method: .coins) }
                    },
                    onVIPPurchaseCompleted: { account in
                        coinStore.synchronize(balance: account.balance)
                        unlockPurchaseTab = nil
                        Task { await resumeCurrentEpisodeAfterUnlock() }
                    }
                )
                .id(initialTab)
                .frame(width: geo.size.width, height: panelHeight)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(true)
    }

    private var unlockGold: Color { Color(red: 1.0, green: 0.76, blue: 0.20) }
    private var unlockPaleGold: Color { Color(red: 1.0, green: 0.90, blue: 0.62) }

    private var unlockSheetGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.13, green: 0.11, blue: 0.08), Color(red: 0.055, green: 0.05, blue: 0.044), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func unlockPrimaryPanel(
        _ state: EpisodeUnlockFlowState,
        containerHeight: CGFloat,
        safeBottom: CGFloat
    ) -> some View {
        let panelHeight = EpisodeUnlockPanelLayout.primaryHeight(containerHeight: containerHeight)
        let isCompact = panelHeight < 370
        let choiceHeight: CGFloat = isCompact ? 62 : 76

        return VStack(spacing: 0) {
            HStack {
                if !state.vipOnly {
                    unlockMetadata(state)
                } else {
                    Label("VIP 专享", systemImage: "crown.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(unlockPaleGold)
                }
                Spacer()
                Button(action: closeUnlockPanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.09), in: Circle())
                }
                .accessibilityLabel("关闭")
            }

            VStack(spacing: isCompact ? 8 : 10) {
                unlockChoice(
                    title: "VIP 全剧畅看",
                    subtitle: "无限畅看 · 1080P · 离线下载",
                    icon: "crown.fill",
                    selected: state.selection == .vip,
                    height: choiceHeight
                ) { selectUnlockMethod(.vip) }

                if state.canUnlockWithCoins {
                    unlockChoice(
                        title: "金币解锁",
                        subtitle: "按集解锁 · 永久观看",
                        icon: "bitcoinsign.circle.fill",
                        selected: state.selection == .coins,
                        height: choiceHeight
                    ) { selectUnlockMethod(.coins) }
                }
            }
            .padding(.top, isCompact ? 10 : 18)

            // VIP 专享只有一个选项；保留统一的内容区高度，让 CTA 与普通锁集对齐。
            Spacer(minLength: isCompact ? 8 : 14)

            if let message = state.errorMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.43, blue: 0.38))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }

            Button(action: handlePrimaryUnlockAction) {
                HStack(spacing: 8) {
                    if state.isProcessing {
                        ProgressView().tint(.black)
                    }
                    Text(state.primaryButtonTitle)
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: isCompact ? 52 : 58)
                .background(
                    LinearGradient(
                        colors: [.white, unlockPaleGold, unlockGold],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .shadow(color: unlockGold.opacity(0.25), radius: 18, y: 8)
            }
            .disabled(state.isProcessing)

            Group {
                if state.canUnlockWithAd {
                    Button { Task { await performUnlock(method: .ads) } } label: {
                        Text("看广告免费解锁")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .underline(color: .white.opacity(0.28))
                    }
                    .disabled(state.isProcessing)
                } else {
                    // VIP 专享没有广告路径，但保留同高占位，避免首层面板按钮上下跳动。
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(height: 18)
            .padding(.top, isCompact ? 8 : 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, isCompact ? 14 : 22)
        .padding(.bottom, EpisodeUnlockPanelLayout.bottomPadding(safeAreaBottom: safeBottom))
        .frame(height: panelHeight, alignment: .top)
        .background(
            unlockSheetGradient,
            in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .stroke(
                    LinearGradient(colors: [unlockGold.opacity(0.5), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .environment(\.colorScheme, .dark)
    }

    private func unlockMetadata(_ state: EpisodeUnlockFlowState) -> some View {
        HStack(spacing: 13) {
            unlockMetadataItem(label: "本集：", value: state.coinCost)
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 18)
            unlockMetadataItem(label: "余额：", value: state.balance)
        }
    }

    private func unlockMetadataItem(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Image(systemName: "bitcoinsign.circle.fill")
                .foregroundStyle(unlockGold)
            Text("\(value)")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white.opacity(0.86))
    }

    private func unlockChoice(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? unlockGold : .white.opacity(0.55))
                    .frame(width: 36, height: 36)
                    .background(selected ? unlockGold.opacity(0.12) : .white.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(selected ? unlockGold.opacity(0.12) : .white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(selected ? unlockGold : .white.opacity(0.08), lineWidth: selected ? 1.6 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func unlockRetentionDialog(_ state: EpisodeUnlockFlowState) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(state.vipOnly ? "继续观看" : "选择解锁方式")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(unlockPaleGold)
                Spacer()
                Button(action: closeUnlockPanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.09), in: Circle())
                }
                .accessibilityLabel("关闭")
            }

            retentionActionButton(
                title: state.vipOnly ? "开通 VIP 继续观看" : "继续解锁",
                icon: state.vipOnly ? "crown.fill" : "lock.fill",
                selected: true,
                disabled: state.isProcessing,
                action: openPrimaryUnlockPanel
            )

            if state.canUnlockWithAd {
                retentionActionButton(
                    title: "看广告免费解锁",
                    icon: "play.rectangle.fill",
                    selected: false,
                    disabled: state.isProcessing
                ) { Task { await performUnlock(method: .ads) } }
            }

            if state.isProcessing {
                ProgressView().tint(unlockGold)
            } else if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.43, blue: 0.38))
            }

        }
        .padding(18)
        .background(
            unlockSheetGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(colors: [unlockGold.opacity(0.5), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
    }

    private func retentionActionButton(
        title: String,
        icon: String,
        selected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(selected ? .black : unlockPaleGold)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [.white, unlockPaleGold, unlockGold], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(unlockGold.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(unlockGold.opacity(selected ? 0 : 0.72), lineWidth: selected ? 0 : 1.4)
                )
        }
        .disabled(disabled)
        .opacity(disabled ? 0.58 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func unlockFinalLockedFrame() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(unlockGold)
            Text("本集未解锁")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Button(action: { dismiss() }) {
                Text("退出播放")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(unlockPaleGold)
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .overlay(Capsule().stroke(unlockGold.opacity(0.62), lineWidth: 1))
            }
        }
    }

    private func selectUnlockMethod(_ selection: EpisodeUnlockFlowState.Selection) {
        guard var state = unlockState, !state.vipOnly || selection == .vip else { return }
        state.selection = selection
        state.errorMessage = nil
        unlockState = state
    }

    private func closeUnlockPanel() {
        guard var state = unlockState else { return }
        state.close()
        unlockState = state
    }

    private func openPrimaryUnlockPanel() {
        guard var state = unlockState else { return }
        state.reopenFromRetention()
        state.errorMessage = nil
        unlockState = state
    }

    private func handlePrimaryUnlockAction() {
        guard let state = unlockState else { return }
        if state.selection == .vip {
            unlockPurchaseTab = .vip
        } else if state.hasEnoughCoins {
            Task { await performUnlock(method: .coins) }
        } else {
            unlockPurchaseTab = .coins
        }
    }

    private func dismissUnlockPurchaseCenter() {
        unlockPurchaseTab = nil
        guard var state = unlockState else { return }
        state.close()
        state.errorMessage = nil
        unlockState = state
    }

    @MainActor
    private func presentEpisodeUnlock(_ episodeNumber: Int) {
        guard unlockState?.episodeNumber != episodeNumber else { return }
        let episode = episodes.first(where: { $0.episodeNumber == episodeNumber })
        unlockState = EpisodeUnlockFlowState(
            episodeNumber: episodeNumber,
            coinCost: max(0, episode?.unlockCoinPrice ?? 30),
            balance: coinStore.coinBalance,
            vipOnly: episode?.requiresVIP ?? false
        )
        showEpisodeList = false
        isUIVisible = true
        autoHideTask?.cancel()
        playerCoordinator.engine.endContentTransitionWithoutMedia()

        Task { @MainActor in
            do {
                let account = try await dependencies.detailRepository.fetchUnlockAccount()
                guard var state = unlockState, state.episodeNumber == episodeNumber else { return }
                coinStore.synchronize(balance: account.balance)
                if account.isVIP {
                    await resumeCurrentEpisodeAfterUnlock()
                    return
                }
                state.balance = account.balance
                state.selection = state.vipOnly || account.balance < state.coinCost ? .vip : .coins
                unlockState = state
            } catch {
                guard var state = unlockState, state.episodeNumber == episodeNumber else { return }
                state.errorMessage = "余额加载失败，请稍后重试"
                unlockState = state
            }
        }
    }

    @MainActor
    private func performUnlock(method: EpisodeUnlockMethod) async {
        guard var state = unlockState,
              !state.isProcessing,
              let episodeID = episodeID(for: state.episodeNumber),
              method != .ads || state.canUnlockWithAd else { return }
        state.isProcessing = true
        state.errorMessage = nil
        unlockState = state
        do {
            let result = try await dependencies.detailRepository.unlockEpisode(episodeId: episodeID, method: method)
            guard result.unlocked else {
                throw APIError(code: "UNLOCK_FAILED", message: "解锁失败，请重试")
            }
            if let balance = result.balanceAfter {
                coinStore.synchronize(balance: balance)
            }
            await resumeCurrentEpisodeAfterUnlock()
        } catch let error as APIError {
            guard var latest = unlockState else { return }
            latest.isProcessing = false
            latest.errorMessage = error.code == "INSUFFICIENT_COINS" ? "金币余额不足，请先充值" : error.localizedDescription
            unlockState = latest
        } catch {
            guard var latest = unlockState else { return }
            latest.isProcessing = false
            latest.errorMessage = "解锁失败，请检查网络后重试"
            unlockState = latest
        }
    }

    @MainActor
    private func resumeCurrentEpisodeAfterUnlock() async {
        let episodeNumber = currentEpisode
        initialPlayAssetTask?.cancel()
        initialPlayAssetTask = nil
        if let id = episodeID(for: episodeNumber) {
            episodeMediaSources.removeValue(forKey: id)
        }
        guard await ensurePlayAsset(for: episodeNumber) else {
            guard var state = unlockState else { return }
            state.isProcessing = false
            state.errorMessage = "权益已更新，但播放地址加载失败，请重试"
            unlockState = state
            return
        }
        unlockedEpisodes.insert(episodeNumber)
        unlockState = nil
        unlockPurchaseTab = nil
        initializeEpisodePlayer()
        playerCoordinator.engine.play()
    }

    @MainActor
    private func refreshEntitlementAfterMembership() async {
        guard var state = unlockState else { return }
        do {
            let account = try await dependencies.detailRepository.fetchUnlockAccount()
            coinStore.synchronize(balance: account.balance)
            if account.isVIP {
                await resumeCurrentEpisodeAfterUnlock()
            } else {
                state.balance = account.balance
                unlockState = state
            }
        } catch {
            state.errorMessage = "会员状态刷新失败，请重试"
            unlockState = state
        }
    }

    // MARK: - 自动隐藏

    private func resetAutoHide() {
        autoHideTask?.cancel()
        guard playerCoordinator.engine.state == .playing else { return }
        isUIVisible = true
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { isUIVisible = false }
        }
    }

    // MARK: - Episode Loading

    private func startPlaybackSession() async {
        playbackTraceStartedAt = CACurrentMediaTime()
        playbackTraceReason = "open"
        let trace = PlaybackDiagnosticsTrace(scene: "series", seriesID: drama.id, episodeNumber: currentEpisode)
        playerCoordinator.engine.startPlaybackTrace(trace)
        Logger.player.info("SeriesTrace 打开播放页开始 剧ID=\(drama.id) 起始集=\(currentEpisode) 来源=\(sourceScene)")
        playerCoordinator.beginSeries(dramaID: drama.id)
        playerCoordinator.setSeriesPlaybackFinishedHandler(dramaID: drama.id) {
            handlePlaybackFinished()
        }
        if !hasTrackedImpression {
            hasTrackedImpression = true
            dependencies.discoveryAnalytics.trackContentImpression(
                seriesID: drama.id,
                sourceScene: sourceScene
            )
        }

        // 仅当卡片预览确实对应本次目标集时先播，历史/收藏指定其他集时不能误播第 1 集。
        let cardPreviewMatchesTarget = initialEpisodeID == nil
            || initialEpisodeID == drama.previewEpisodeID
        if cardPreviewMatchesTarget, let previewItem = drama.toPlayerMediaItem() {
            Logger.player.info("SeriesTrace 使用卡片预览源先播 剧ID=\(drama.id) 集数=\(previewItem.episodeNumber ?? -1)")
            playerCoordinator.engine.markTrace("卡片预览源")
            playerCoordinator.claimSeries(
                drama: drama,
                items: [previewItem],
                startIndex: 0,
                handoff: handoff
            )
        } else if let targetEpisodeID = initialEpisodeID ?? drama.previewEpisodeID {
            // 没有卡片直链时立即并行请求播放合同；无需先等 episodes 接口返回。
            let targetEpisodeNumber = currentEpisode
            initialPlayAssetTask = Task { @MainActor in
                await fetchInitialPlayAsset(
                    episodeID: targetEpisodeID,
                    episodeNumber: targetEpisodeNumber
                )
            }
        }

        await loadEpisodes()
    }

    /// Series 播放完成后优先切换下一集；最后一集回到首帧并等待用户重播。
    private func handlePlaybackFinished() {
        autoHideTask?.cancel()
        if currentEpisode < totalEpisodes {
            requestEpisodeSwitch(currentEpisode + 1, previousCompleted: true)
            return
        }

        playerCoordinator.engine.pause(reason: .user)
        playerCoordinator.engine.seek(to: 0)
        withAnimation(.easeOut(duration: 0.2)) {
            isUIVisible = true
        }
    }

    private func loadEpisodes() async {
        let repo = dependencies.detailRepository
        let startedAt = CACurrentMediaTime()
        do {
            episodes = try await repo.fetchEpisodes(dramaId: drama.id)
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.info("SeriesTrace 剧集列表加载完成 剧ID=\(drama.id) 数量=\(episodes.count) 耗时=\(Int(elapsed))ms")
            playerCoordinator.engine.markTrace("剧集列表")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            Logger.viewModel.error("SeriesPlayerView: fetchEpisodes failed: \(error)")
            if playerCoordinator.engine.currentItem?.id != PlayerMediaItem.stableID(
                dramaID: drama.id,
                episodeNumber: currentEpisode
            ) {
                episodeLoadError = "Unable to load episodes. Please try again."
                playerCoordinator.engine.deactivate()
            }
            return
        }

        guard !Task.isCancelled else { return }
        // 必须在请求播放资源和初始化播放器之前匹配 My List 指定剧集，
        // 避免先加载默认集、随后再切集造成错误续播和重复请求。
        if let eid = initialEpisodeID,
           let matched = episodes.first(where: {
               String($0.id) == eid || String($0.episodeNumber) == eid
           }) {
            currentEpisode = matched.episodeNumber
        }
        // Task36B-2 返工：播放源标记移到 ensurePlayAsset 内部，成功/锁集/失败分别标记
        _ = await ensurePlayAsset(for: currentEpisode)
        guard !Task.isCancelled else { return }
        initializeEpisodePlayer()
    }

    /// 首屏播放合同快速通道。成功后直接把媒体交给共享 Coordinator/Engine 起播，
    /// 同时写入页面级播放源缓存，后续 episodes 流程复用结果，不再重复请求。
    @MainActor
    private func fetchInitialPlayAsset(episodeID: String, episodeNumber: Int) async -> Bool {
        if episodeMediaSources[episodeID] != nil { return true }
        let startedAt = CACurrentMediaTime()
        Logger.player.info("SeriesTrace 并行请求首屏播放源 集数=\(episodeNumber) 剧集ID=\(episodeID)")
        do {
            let dto = try await dependencies.detailRepository.fetchPlayAsset(episodeId: episodeID)
            guard !Task.isCancelled,
                  let source = dto.toPlayerMediaSource() else { return false }
            episodeMediaSources[episodeID] = source
            episodeLoadError = nil
            if let resume = dto.resumeTime, resume > 0 {
                episodeResumeTimes[episodeID] = TimeInterval(resume)
            }
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.info("SeriesTrace 首屏播放源并行请求成功 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms")
            playerCoordinator.engine.markTrace("播放源")

            guard playerCoordinator.owner == .series(dramaID: drama.id) else { return true }
            let item = PlayerMediaItem(
                id: PlayerMediaItem.stableID(dramaID: drama.id, episodeNumber: episodeNumber),
                title: drama.title,
                episodeNumber: episodeNumber,
                coverURL: drama.coverURL,
                source: source,
                resumeTime: dto.resumeTime.map(TimeInterval.init)
            )
            playerCoordinator.claimSeries(
                drama: drama,
                items: [item],
                startIndex: 0,
                handoff: handoff,
                backendResumeTime: dto.resumeTime.map(TimeInterval.init)
            )
            return true
        } catch is CancellationError {
            return false
        } catch let error as APIError where error.code == "EPISODE_LOCKED" {
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.warning("SeriesTrace 首屏剧集被锁定 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms")
            playerCoordinator.engine.markTrace("锁集阻断-EP\(episodeNumber)")
            playerCoordinator.engine.finishTrace(termination: "锁集阻断")
            episodeLoadError = nil
            presentEpisodeUnlock(episodeNumber)
            return false
        } catch {
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.warning("SeriesTrace 首屏播放源并行请求失败 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms 错误=\(error.localizedDescription)")
            return false
        }
    }

    private func initializeEpisodePlayer() {
        let playable = buildPlayableItems(from: episodes)
        guard !playable.isEmpty else {
            // 正式播放接口失败时保留已启动的卡片预览，不得回落到其他剧或 Mock。
            if playerCoordinator.engine.currentItem?.id != PlayerMediaItem.stableID(
                dramaID: drama.id,
                episodeNumber: currentEpisode
            ) {
                playerCoordinator.engine.deactivate()
            }
            return
        }
        let startIndex = playable.firstIndex(where: { $0.episodeNumber == currentEpisode }) ?? 0
        let playerItems = playable.map(\.item)
        let currentEpisodeID = episodeID(for: currentEpisode)
        let backendResume = currentEpisodeID.flatMap { episodeResumeTimes[$0] }

        // My List 显式 resume 优先级：仅初始剧集、无 handoff、未消费时生效
        let myListResume: TimeInterval? = {
            guard !hasConsumedInitialResume, handoff == nil,
                  let rt = initialResumeTime, rt > 0 else { return nil }
            hasConsumedInitialResume = true
            return rt
        }()
        let effectiveResume = handoff?.resumeTime ?? myListResume ?? backendResume

        if playerCoordinator.engine.currentItem != playerItems[safe: startIndex] {
            playerCoordinator.claimSeries(
                drama: drama,
                items: playerItems,
                startIndex: startIndex,
                handoff: handoff,
                backendResumeTime: handoff == nil ? effectiveResume : backendResume
            )
        }

        // 绑定 reporter session
        if let epID = currentEpisodeID {
            Task {
                await dependencies.watchProgressReporter.begin(
                    seriesID: drama.id,
                    episodeID: epID
                )
            }
        }

        prefetchNextEpisode(after: currentEpisode)
        resetAutoHide()
    }

    private func episodeID(for episodeNumber: Int) -> String? {
        episodes.first(where: { $0.episodeNumber == episodeNumber })?.id
    }

    // MARK: - Bottom Chrome

    private func seriesChromeOverlay(in geo: GeometryProxy, isCurrent: Bool) -> some View {
        let horizontalPadding = ChromeMetrics.horizontalPadding
        let actionRailWidth = ChromeMetrics.actionRailWidth
        let actionRailGap = max(18, geo.size.width * 0.055)
        let progressWidth = max(0, geo.size.width - horizontalPadding * 2)
        let contentMaxWidth = max(0, progressWidth - actionRailWidth - actionRailGap)
        let contentWidth = contentMaxWidth
        let bottomInset = UIApplication.safeAreaInsets.bottom + ChromeMetrics.bottomGap

        return VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: actionRailGap) {
                    seriesInfoBlock(width: contentWidth)

                    RightActionBar(
                        isBookmarked: .init(
                            get: { dependencies.bookmarkStore.isBookmarked(drama.id) },
                            set: { _ in }
                        ),
                        viewCount: drama.formattedViewCount,
                        onBookmark: {
                            Task {
                                await dependencies.bookmarkStore.toggle(seriesID: drama.id, sourceScene: sourceScene)
                            }
                            resetAutoHide()
                        },
                        onShare: {
                            dependencies.discoveryAnalytics.trackShare(
                                seriesID: drama.id,
                                sourceScene: sourceScene
                            )
                            activeSheet = .share
                        },
                        onEpisodes: { showEpisodeList = true }
                    )
                    .frame(width: actionRailWidth)
                    .offset(x: 16)
                }

                if isCurrent {
                    seriesProgressBar(totalWidth: progressWidth, engine: playerCoordinator.engine)
                        .frame(width: progressWidth, height: seriesIsScrubbing ? ChromeMetrics.progressScrubbingHeight : ChromeMetrics.progressIdleHeight)
                        .padding(.top, 2)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: progressWidth, height: 2)
                        .frame(height: ChromeMetrics.progressIdleHeight, alignment: .bottom)
                        .padding(.top, 2)
                }

                membershipDownloadRow
                    .frame(width: progressWidth)
                    .padding(.top, 2)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomInset)
        }
        .zIndex(50)
    }

    private func seriesInfoBlock(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showEpisodeList = true
                resetAutoHide()
            } label: {
                HStack(spacing: 4) {
                    Text(drama.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            let badgeTags = L10n.dramaBadgeTags(for: drama)
            if !badgeTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(badgeTags.enumerated()), id: \.offset) { _, tag in
                        DramaBadgeTagView(tag: tag, drama: drama)
                    }
                }
            }

            (Text("Trailer | ").font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
            + Text(drama.synopsis).font(.system(size: 13)).foregroundColor(.white.opacity(0.65)))
            .lineLimit(2)
            .lineSpacing(3)
        }
        .frame(width: width, alignment: .leading)
    }

    private var membershipDownloadRow: some View {
        HStack {
            Button {} label: {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Join membership")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DB.gold)
                .padding(.horizontal, 14)
                .frame(height: ChromeMetrics.membershipRowHeight)
                .background(Capsule().fill(DB.gold.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {} label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14, weight: .medium))
                    Text("Download")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.72))
                .frame(height: ChromeMetrics.membershipRowHeight)
            }
            .buttonStyle(.plain)
        }
    }

    private func speedProgressOverlay(in geo: GeometryProxy) -> some View {
        let horizontalPadding = ChromeMetrics.horizontalPadding
        let progressWidth = geo.size.width - horizontalPadding * 2
        let bottomInset = UIApplication.safeAreaInsets.bottom + ChromeMetrics.bottomGap
        let progressBottomGap = bottomInset + ChromeMetrics.membershipRowHeight + 4

        return VStack(spacing: 0) {
            Spacer()
            seriesProgressBar(totalWidth: progressWidth, engine: playerCoordinator.engine)
                .frame(width: progressWidth, height: seriesIsScrubbing ? ChromeMetrics.progressScrubbingHeight : ChromeMetrics.progressIdleHeight)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, progressBottomGap)
        }
        .allowsHitTesting(false)
    }

    // MARK: - 进度条（带拖动和点击）
    @State private var seriesScrubFraction: CGFloat = 0
    @State private var seriesIsScrubbing = false
    @State private var seriesWasPlayingBeforeScrub = false
    @State private var seriesSeekPreviewFraction: CGFloat?

    private func seriesProgressBar(totalWidth: CGFloat, engine: ShortVideoPlayerEngine) -> some View {
        let progress = playbackProgress
        let fraction = progress.duration > 0
            ? Double(seriesSeekPreviewFraction ?? (seriesIsScrubbing ? seriesScrubFraction : CGFloat(progress.currentTime / progress.duration))) : 0
        let clampedProgress = max(0, min(1, CGFloat(fraction)))
        let barWidth = totalWidth

        return ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(height: seriesIsScrubbing ? ChromeMetrics.progressScrubbingHeight : ChromeMetrics.progressIdleHeight)
            let trackH: CGFloat = seriesIsScrubbing ? 8 : 2
            let activeH: CGFloat = seriesIsScrubbing ? 8 : 2.5
            let knobDiameter: CGFloat = seriesIsScrubbing ? 14 : 4
            Capsule().fill(Color.white.opacity(0.25)).frame(height: trackH)
            Capsule().fill(DT.logoRed)
                .frame(width: max(activeH, barWidth * clampedProgress), height: activeH)
            Circle().fill(.white)
                .frame(width: knobDiameter, height: knobDiameter)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                .offset(
                    x: max(0, min(barWidth, barWidth * clampedProgress)) - knobDiameter / 2,
                    y: (knobDiameter - activeH) / 2
                )
        }
        .frame(width: barWidth, height: seriesIsScrubbing ? ChromeMetrics.progressScrubbingHeight : ChromeMetrics.progressIdleHeight, alignment: .bottom)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard engine.progress.duration > 0 else { return }
                    if !seriesIsScrubbing {
                        seriesWasPlayingBeforeScrub = engine.state == .playing
                    }
                    seriesIsScrubbing = true
                    seriesScrubFraction = max(0, min(1, value.location.x / barWidth))
                }
                .onEnded { _ in
                    let clamped = max(0, min(1, seriesScrubFraction))
                    seriesSeekPreviewFraction = clamped
                    engine.seek(to: Double(clamped))
                    if seriesWasPlayingBeforeScrub { engine.play() }
                    seriesIsScrubbing = false
                    seriesScrubFraction = 0
                    seriesWasPlayingBeforeScrub = false
                    clearSeekPreviewAfterProgressCatchUp()
                }
        )
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard playbackProgress.duration > 0 else { return }
                    let clamped = max(0, min(1, value.location.x / barWidth))
                    seriesSeekPreviewFraction = clamped
                    engine.seek(to: Double(clamped))
                    resetAutoHide()
                    clearSeekPreviewAfterProgressCatchUp()
                }
        )
    }

    private func clearSeekPreviewAfterProgressCatchUp() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            seriesSeekPreviewFraction = nil
        }
    }

    // MARK: - Quality Helpers

    private func qualityOptions() -> [PlayerQualitySheet.QualityOption] {
        [
            .init(id: "auto", label: "Auto", isVIP: false, isSelected: selectedQualityID == "auto"),
            .init(id: "1080p", label: "1080P", isVIP: true, isSelected: selectedQualityID == "1080p"),
            .init(id: "720p", label: "720P", isVIP: false, isSelected: selectedQualityID == "720p"),
            .init(id: "540p", label: "540P", isVIP: false, isSelected: selectedQualityID == "540p")
        ]
    }

    private func applyPlaybackRate(_ rate: Float) {
        selectedPlaybackRate = rate
        playerCoordinator.engine.setRate(rate)
        resetAutoHide()
    }

    // MARK: - Episode Switching

    /// 统一切集入口：先同步进入目标页，再异步加载播放合同或展示锁集权益。
    @discardableResult
    private func requestEpisodeSwitch(
        _ target: Int,
        previousCompleted: Bool = false,
        animatePage: Bool = true
    ) -> Bool {
        guard target != currentEpisode, target >= 1, target <= totalEpisodes else { return false }
        episodeLoadError = nil
        let previous = currentEpisode
        episodeSwitchTask?.cancel()

        playbackTraceStartedAt = CACurrentMediaTime()
        playbackTraceReason = "switch"
        Logger.player.info("SeriesGesture 接受切集手势 原集=\(previous) 目标集=\(target)")
        playerCoordinator.engine.startPlaybackTrace(
            PlaybackDiagnosticsTrace(
                scene: "series_switch",
                seriesID: drama.id,
                episodeNumber: target
            )
        )

        // 手势翻页由共享分页器提供外层原子动画；选集、自动下一集仍在这里动画。
        if animatePage {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                currentEpisode = target
            }
        } else {
            currentEpisode = target
        }

        episodeSwitchTask = Task { @MainActor in
            guard !Task.isCancelled,
                  let transitionToken = playerCoordinator.beginSeriesEpisodeTransition(
                    dramaID: drama.id
                  ) else { return }

            // 进度收尾可以等待网络，但绝不能阻塞已预加载目标集的播放器接管。
            async let finalizePreviousProgress: Void = dependencies.watchProgressReporter.finalize(
                completed: previousCompleted
            )

            guard !Task.isCancelled,
                  playerCoordinator.isCurrentSeriesEpisodeTransition(
                    dramaID: drama.id,
                    token: transitionToken
                  ) else { return }

            let reusedPrefetch: Bool
            if episodePrefetchTarget == target, let episodePrefetchTask {
                reusedPrefetch = await episodePrefetchTask.value
                if reusedPrefetch {
                    playerCoordinator.engine.markTrace("预取命中")
                    Logger.player.info("SeriesTrace 复用预取播放源 目标集=\(target)")
                }
            } else {
                reusedPrefetch = false
            }

            // 预取失败时重新走一次前台解析，以便准确呈现锁集或网络错误。
            let hasPlayAsset = reusedPrefetch ? true : await ensurePlayAsset(for: target)
            guard hasPlayAsset else {
                guard playerCoordinator.isCurrentSeriesEpisodeTransition(
                    dramaID: drama.id,
                    token: transitionToken
                ) else { return }
                playerCoordinator.engine.endContentTransitionWithoutMedia()
                Logger.player.warning("SeriesTrace 切集被阻断 目标集=\(target) 原集=\(previous) 原因=播放源缺失或剧集锁定")
                return
            }

            guard !Task.isCancelled,
                  playerCoordinator.isCurrentSeriesEpisodeTransition(
                    dramaID: drama.id,
                    token: transitionToken
                  ) else { return }
            let playable = buildPlayableItems(from: episodes)
            guard let playableIndex = playable.firstIndex(where: { $0.episodeNumber == target }) else {
                playerCoordinator.engine.endContentTransitionWithoutMedia()
                Logger.player.warning("SeriesTrace 切集失败 目标集=\(target) 原因=没有可播放索引")
                return
            }
            let targetEpisodeID = episodeID(for: target)
            let backendResume = targetEpisodeID.flatMap { episodeResumeTimes[$0] }
            let committed = playerCoordinator.commitSeriesEpisodeTransition(
                drama: drama,
                items: playable.map(\.item),
                startIndex: playableIndex,
                handoff: nil,
                backendResumeTime: backendResume,
                token: transitionToken
            )
            guard committed else { return }
            prefetchNextEpisode(after: target)
            Logger.player.info("SeriesTrace 切集已提交播放器 目标集=\(target) 播放索引=\(playableIndex)")

            // 播放已经开始后再等待上一集 final report，并建立新一集的上报会话。
            await finalizePreviousProgress
            guard !Task.isCancelled,
                  playerCoordinator.isCurrentSeriesEpisodeTransition(
                    dramaID: drama.id,
                    token: transitionToken
                  ),
                  let targetEpisodeID = episodeID(for: target) else { return }
            await dependencies.watchProgressReporter.begin(
                seriesID: drama.id,
                episodeID: targetEpisodeID
            )
        }
        return true
    }

    /// 重试当前目标集，不改变集数，也不复用已经明确失败的首屏请求 Task。
    private func retryCurrentEpisodePlayback() {
        episodeLoadError = nil
        initialPlayAssetTask?.cancel()
        initialPlayAssetTask = nil

        episodeSwitchTask?.cancel()
        episodeSwitchTask = Task { @MainActor in
            if episodes.isEmpty {
                await loadEpisodes()
                return
            }

            guard await ensurePlayAsset(for: currentEpisode) else {
                guard unlockState == nil else { return }
                playerCoordinator.engine.endContentTransitionWithoutMedia()
                if episodeLoadError == nil {
                    episodeLoadError = "Unable to load this episode. Please try again."
                }
                return
            }
            initializeEpisodePlayer()
        }
    }

    /// 页面只提前获取下一集播放合同；真正的媒体预加载统一交给共享 PlayerSlotPool。
    /// 这样 For You 与 Series 使用完全相同的静音 next + 原生 preroll 规则。
    private func prefetchNextEpisode(after episodeNumber: Int) {
        guard let nextEpisode = episodes.first(where: { $0.episodeNumber == episodeNumber + 1 }) else { return }
        if episodePrefetchTarget == nextEpisode.episodeNumber, episodePrefetchTask != nil {
            return
        }

        episodePrefetchTask?.cancel()
        episodePrefetchTarget = nextEpisode.episodeNumber

        episodePrefetchTask = Task { @MainActor in
            if episodeMediaSources[nextEpisode.id] == nil {
                guard await ensurePlayAsset(
                    for: nextEpisode.episodeNumber,
                    recordTrace: false
                ) else { return false }
            }
            guard !Task.isCancelled,
                  episodeMediaSources[nextEpisode.id] != nil else { return false }
            let playableItems = buildPlayableItems(from: episodes).map(\.item)
            playerCoordinator.updateSeriesPlaylist(
                dramaID: drama.id,
                items: playableItems
            )
            return true
        }
    }

    /// 播放源按内存缓存、Episode URL、后端播放合同依次解析。
    /// recordTrace: 是否记录 trace 标记。当前播放目标集为 true，预取为 false。
    @MainActor
    private func ensurePlayAsset(for episodeNumber: Int, recordTrace: Bool = true) async -> Bool {
        guard let epIndex = episodes.firstIndex(where: { $0.episodeNumber == episodeNumber }) else { return false }
        let ep = episodes[epIndex]
        let episodeId = ep.id

        // 内存缓存命中
        if episodeMediaSources[episodeId] != nil {
            if recordTrace { episodeLoadError = nil }
            Logger.player.info("SeriesTrace 播放源命中内存缓存 集数=\(episodeNumber)")
            if recordTrace { playerCoordinator.engine.markTrace("缓存命中") }
            return true
        }

        // Episode 自带 videoURL
        if let url = URL(string: ep.videoURL),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            episodeMediaSources[episodeId] = .mp4(url)
            if recordTrace { episodeLoadError = nil }
            Logger.player.info("SeriesTrace 播放源使用剧集URL 集数=\(episodeNumber)")
            if recordTrace { playerCoordinator.engine.markTrace("剧集URL") }
            return true
        }

        // 首屏播放合同可能正在与剧集列表并行请求；等待同一 Task，禁止重复调用 /play。
        if episodeId == (initialEpisodeID ?? drama.previewEpisodeID),
           let initialPlayAssetTask {
            let success = await initialPlayAssetTask.value
            if success, episodeMediaSources[episodeId] != nil {
                if recordTrace { playerCoordinator.engine.markTrace("首屏播放源复用") }
                return true
            }
            // 同一次请求已经明确失败或被权益拦截，本轮不再立即重试相同接口。
            if recordTrace, unlockState == nil {
                episodeLoadError = "Unable to load this episode. Please try again."
            }
            return false
        }

        // 请求后端播放合同
        let startedAt = CACurrentMediaTime()
        Logger.player.info("SeriesTrace 请求播放源 集数=\(episodeNumber) 剧集ID=\(episodeId)")
        do {
            let dto = try await dependencies.detailRepository.fetchPlayAsset(episodeId: episodeId)
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            if let url = dto.preferredPlaybackURL {
                episodes[epIndex].videoURL = url
            }
            if let source = dto.toPlayerMediaSource() {
                episodeMediaSources[episodeId] = source
                if let resume = dto.resumeTime, resume > 0 {
                    episodeResumeTimes[episodeId] = TimeInterval(resume)
                }
                unlockedEpisodes.insert(episodeNumber)
                if recordTrace { episodeLoadError = nil }
                Logger.player.info("SeriesTrace 播放源请求成功 集数=\(episodeNumber) 类型=\(dto.sourceType) 耗时=\(Int(elapsed))ms")
                if recordTrace { playerCoordinator.engine.markTrace("播放源") }
                return true
            }
            Logger.player.warning("SeriesTrace 播放源为空 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms")
            if recordTrace {
                episodeLoadError = "This episode is temporarily unavailable."
                playerCoordinator.engine.markTrace("播放源失败-EP\(episodeNumber)")
                playerCoordinator.engine.finishTrace(termination: "播放源失败")
            }
            return false
        } catch let error as APIError where error.code == "EPISODE_LOCKED" {
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.warning("SeriesTrace 剧集被锁定 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms 已进入解锁流程")
            if recordTrace {
                episodeLoadError = nil
                playerCoordinator.engine.markTrace("锁集阻断-EP\(episodeNumber)")
                playerCoordinator.engine.finishTrace(termination: "锁集阻断")
            }
            if recordTrace {
                presentEpisodeUnlock(episodeNumber)
            }
            return false
        } catch {
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.warning("SeriesTrace 播放源请求失败 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms 错误=\(error.localizedDescription)")
            if recordTrace {
                episodeLoadError = "Unable to load this episode. Please try again."
                playerCoordinator.engine.markTrace("网络失败-EP\(episodeNumber)")
                playerCoordinator.engine.finishTrace(termination: "网络失败")
            }
            return false
        }
    }

    /// 从可用播放源构建播放器列表，保证 episodeNumber 与 player index 不错位。
    private struct EpisodePlayableItem: Identifiable {
        let id: String
        let episodeNumber: Int
        let item: PlayerMediaItem
    }

    private func sourceForEpisode(_ ep: Episode) -> PlayerMediaSource? {
        if let cached = episodeMediaSources[ep.id] { return cached }
        if let url = URL(string: ep.videoURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return .mp4(url)
        }
        return nil
    }

    private func buildPlayableItems(from eps: [Episode]) -> [EpisodePlayableItem] {
        eps.compactMap { ep in
            guard let source = sourceForEpisode(ep) else {
                return nil
            }
            let resume = episodeResumeTimes[ep.id]
            return EpisodePlayableItem(
                id: ep.id,
                episodeNumber: ep.episodeNumber,
                item: PlayerMediaItem(
                    id: PlayerMediaItem.stableID(dramaID: drama.id, episodeNumber: ep.episodeNumber),
                    title: drama.title,
                    episodeNumber: ep.episodeNumber,
                    coverURL: drama.coverURL,
                    source: source,
                    resumeTime: resume,
                    // 普通免费集与 For You 共用公开 MP4 Range 缓存；付费/VIP 内容不落普通缓存。
                    allowsPersistentCache: !ep.isLocked && !ep.requiresVIP
                )
            )
        }
    }

    private func trackPlaybackMilestones(_ progress: PlayerProgress) {
        guard playbackState == .playing,
              let episodeID = currentBackendEpisodeID else { return }

        if progress.currentTime >= 5, qualifiedEpisodeIDs.insert(episodeID).inserted {
            dependencies.discoveryAnalytics.trackQualifiedPlay(
                seriesID: drama.id,
                episodeID: episodeID,
                sourceScene: sourceScene
            )
        }

        if progress.duration > 0,
           progress.currentTime / progress.duration >= 0.9,
           completedEpisodeIDs.insert(episodeID).inserted {
            dependencies.discoveryAnalytics.trackPlayComplete(
                seriesID: drama.id,
                episodeID: episodeID,
                sourceScene: sourceScene
            )
        }
    }

    private var currentBackendEpisodeID: String? {
        episodes.first(where: { $0.episodeNumber == currentEpisode })?.id
    }

    // MARK: - Top Chrome

    private func topChromeTopInset(in geo: GeometryProxy) -> CGFloat {
        let windowTopInset = UIApplication.safeAreaInsets.top
        let topInset = max(geo.safeAreaInsets.top, windowTopInset)
        return topInset + ChromeMetrics.topGapBelowSafeArea
    }

    private func topControlBar(episodeNumber: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                dismissSeries()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 36)
                    .contentShape(Rectangle())
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)

            Text("EP.\(episodeNumber)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

            Spacer()

            Button {
                activeSheet = .speed
            } label: {
                Label {
                    Text(speedControlTitle)
                        .font(.system(size: 14, weight: .bold))
                } icon: {
                    Image(systemName: "timer")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(height: ChromeMetrics.topBarHeight)
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    activeSheet = .speed
                } label: {
                    Label("Speed", systemImage: "timer")
                }

                Button {
                    activeSheet = .quality
                } label: {
                    Label("Quality", systemImage: "4k.tv")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(90))
            }
            .buttonStyle(.plain)
        }
        .frame(height: ChromeMetrics.topBarHeight)
        .padding(.horizontal, ChromeMetrics.horizontalPadding)
    }

    private var speedControlTitle: String {
        abs(selectedPlaybackRate - 1.0) < 0.01 ? "Speed" : String(format: "%.1fx", selectedPlaybackRate)
    }

    private var centerPlaybackButton: some View {
        Button {
            if playbackState == .playing {
                playerCoordinator.engine.pause(reason: .user)
                autoHideTask?.cancel()
                Task { await dependencies.watchProgressReporter.finalize(completed: false) }
            } else {
                if let epID = currentBackendEpisodeID {
                    Task {
                        await dependencies.watchProgressReporter.begin(
                            seriesID: drama.id,
                            episodeID: epID
                        )
                    }
                }
                playerCoordinator.engine.play()
                resetAutoHide()
            }
        } label: {
            let isPlaying = playbackState == .playing
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 74, height: 74)
                .background(Circle().fill(Color.black.opacity(0.42)))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .id(String(describing: playbackState))
        .buttonStyle(.plain)
        .accessibilityLabel(playbackState == .playing ? "Pause" : "Play")
    }

    // MARK: - Episode Pager

    private func episodePager(in geo: GeometryProxy) -> some View {
        VerticalVideoPager(
            state: pagerState,
            pageCount: totalEpisodes,
            currentIndex: currentEpisode - 1,
            pageHeight: { _ in
                geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            }
        ) { index, isCurrent in
            let episodeNumber = index + 1
            ZStack {
                ShortVideoPlayerView(
                    player: isCurrent ? playerForEpisode(episodeNumber) : nil,
                    coverURL: drama.coverURL,
                    engine: playerCoordinator.engine,
                    showsSystemPlaybackButton: false
                )
                .allowsHitTesting(false)

                if isUIVisible, !showSpeedHUD {
                    topControlBar(episodeNumber: episodeNumber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, topChromeTopInset(in: geo))
                        .zIndex(60)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 280)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                    seriesChromeOverlay(in: geo, isCurrent: isCurrent)

                    if isCurrent, playerCoordinator.engine.currentPlayer != nil {
                        centerPlaybackButton
                            .zIndex(40)
                    }
                }
            }
            .allowsHitTesting(isCurrent)
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    /// 只有播放器当前 item 确实属于该集时才挂载 AVPlayer。
    /// 锁集或播放源加载中时目标页只显示封面，避免 EP2 页面继续显示 EP1 画面。
    private func playerForEpisode(_ episodeNumber: Int) -> AVPlayer? {
        guard playerCoordinator.engine.currentItem?.episodeNumber == episodeNumber else {
            return nil
        }
        return playerCoordinator.engine.currentPlayer
    }

    // MARK: - Gestures

    /// Series 全屏切集必须像 For You 一样从页面大部分区域可触发，
    /// 但要避开左边缘返回、进度条拖动、弹层和明显横滑。
    private func canHandleEpisodeDrag(_ value: DragGesture.Value) -> Bool {
        guard unlockState == nil, !seriesIsScrubbing, !showEpisodeList,
              activeSheet == nil, !showSpeedHUD else { return false }
        guard value.startLocation.x > 24 else { return false }
        guard abs(value.translation.height) > abs(value.translation.width) * 1.2 else { return false }
        return true
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard unlockState == nil else { return }
                switch value {
                case .second(true, _):
                    if !showSpeedHUD, playerCoordinator.engine.progress.duration > 0 {
                        autoHideTask?.cancel()
                        if playerCoordinator.engine.state == .pausedByUser {
                            playerCoordinator.engine.play()
                        }
                        playerCoordinator.engine.setRate(2.0)
                        withAnimation(.spring(response: 0.3)) { showSpeedHUD = true }
                    }
                default: break
                }
            }
            .onEnded { _ in
                guard unlockState == nil else { return }
                playerCoordinator.engine.setRate(selectedPlaybackRate)
                withAnimation(.spring(response: 0.3)) { showSpeedHUD = false }
                if isUIVisible, playerCoordinator.engine.state == .playing {
                    resetAutoHide()
                }
            }
    }

    /// Task36B-1: 屏幕左边缘右滑返回上一页。
    /// 限制起点 x ≤ 24 避免与上下切集手势冲突；要求横向位移 > 80 且横向明显大于纵向，
    /// 防止垂直翻页被误判为返回。
    private func edgeBackGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onEnded { value in
                // 只在左边缘触发（起点 x ≤ 24pt），避免全屏滑动干扰上下切集
                guard value.startLocation.x <= 24 else { return }
                // 水平位移足够且主导（横向 > 80pt，横向 > 纵向 × 1.5）
                guard value.translation.width > 80,
                      abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                dismissSeries()
            }
    }

    /// 从 For You 进入且仍停留同一集时交还同一个播放器；切到其他集时返回原短剧卡片。
    private func dismissSeries() {
        guard !hasPreparedReturn else {
            dismiss()
            return
        }
        if sourceScene == "for_you", let mediaID = handoff?.mediaID {
            _ = playerCoordinator.prepareSeriesReturnToForYou(expectedMediaID: mediaID)
        } else {
            playerCoordinator.release(.series(dramaID: drama.id))
        }
        hasPreparedReturn = true
        dismiss()
    }

    private func tapPauseGesture(in geo: GeometryProxy) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard unlockState == nil else { return }
                guard !isTapInsideVisibleChrome(value.location, in: geo) else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    isUIVisible.toggle()
                }
                if isUIVisible, playerCoordinator.engine.state == .playing {
                    resetAutoHide()
                } else {
                    autoHideTask?.cancel()
                }
            }
    }

    private func isTapInsideVisibleChrome(_ location: CGPoint, in geo: GeometryProxy) -> Bool {
        guard isUIVisible, !showSpeedHUD else { return false }

        let topStart = topChromeTopInset(in: geo)
        let topEnd = topStart + ChromeMetrics.topBarHeight + 12
        if location.y <= topEnd { return true }

        let bottomSafeArea = UIApplication.safeAreaInsets.bottom
        let bottomChromeHeight = bottomSafeArea
            + ChromeMetrics.bottomGap
            + ChromeMetrics.membershipRowHeight
            + ChromeMetrics.progressScrubbingHeight
            + 180
        return location.y >= geo.size.height - bottomChromeHeight
    }

    // MARK: - Episode Lock Check

    private func isEpisodeLocked(_ ep: Int) -> Bool {
        if unlockedEpisodes.contains(ep) { return false }
        let freeRange = drama.freeEpisodeRange ?? 1...3
        return !freeRange.contains(ep)
    }

}

// MARK: - Episode Picker Sheet

private struct EpisodePickerSheet: View {
    let drama: DramaItem
    let episodes: [Episode]
    @Binding var currentEpisode: Int
    let unlockedEpisodes: Set<Int>
    @Binding var isPresented: Bool
    var onSelectEpisode: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
    private let rangeSize = 30
    @State private var selectedRange = 0

    private var ranges: [ClosedRange<Int>] {
        let total = episodes.isEmpty ? max(1, drama.episodeCount) : episodes.count
        guard total > 0 else { return [1...1] }
        var result: [ClosedRange<Int>] = []
        var start = 1
        while start <= total {
            let end = min(start + rangeSize - 1, total)
            result.append(start...end)
            start += rangeSize
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { dismiss() }
            VStack(spacing: 0) {
                // Drag handle + close X
                ZStack {
                    Capsule().fill(Color.white.opacity(0.14)).frame(width: 40, height: 5)
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 36, height: 36)
                        }
                    }
                }
                .padding(.top, 10).padding(.bottom, 8)

                // Header: poster + title
                HStack(alignment: .top, spacing: 14) {
                    CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0, cornerRadius: DB.posterRadius, width: 72, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(drama.title).font(.system(size: 20, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Text("\(drama.formattedViewCount) Views").font(.system(size: 16)).foregroundColor(.white.opacity(0.5))
                        HStack(spacing: 4) {
                            Image(systemName: "star").font(.system(size: 12))
                            Text(String(format: "%.1f(5.5K)", drama.rating))
                            Text("Rate").font(.system(size: 12))
                        }.foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 16)

                // Range tabs
                if ranges.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(Array(ranges.enumerated()), id: \.offset) { idx, range in
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) { selectedRange = idx }
                                } label: {
                                    Text("\(range.lowerBound)-\(range.upperBound)")
                                        .font(.system(size: 16, weight: selectedRange == idx ? .bold : .regular))
                                        .foregroundColor(selectedRange == idx ? .white : .white.opacity(0.45))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 14)
                }

                // 6-column grid
                ScrollView {
                    let range = ranges.indices.contains(selectedRange) ? ranges[selectedRange] : (1...1)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(range), id: \.self) { ep in
                            episodeCell(ep)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxHeight: 300)
            }
            .padding(.bottom, 20)
            .background(DB.panelElevated)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private func episodeCell(_ ep: Int) -> some View {
        let isCurrent = ep == currentEpisode
        let freeRange = drama.freeEpisodeRange ?? 1...3
        let isLocked = !unlockedEpisodes.contains(ep) && !freeRange.contains(ep)
        Button {
            // 锁图标仅作预提示；最终权限以播放接口为准，支持已登录 VIP 直接播放。
            onSelectEpisode(ep)
            dismiss()
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isCurrent ? DB.pink.opacity(0.5) : (isLocked ? Color.white.opacity(0.05) : Color.white.opacity(0.12)))
                    .frame(height: 48)

                Text("\(ep)")
                    .font(.system(size: 20, weight: isCurrent ? .bold : .medium))
                    .foregroundColor(isCurrent ? .white : (isLocked ? DB.mutedText : .white.opacity(0.85)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Lock badge
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(DB.mutedText)
                        .padding(3)
                }

                // Playing indicator
                if isCurrent {
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 2, height: 6)
                        RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 2, height: 10)
                        RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 2, height: 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dismiss() { withAnimation(.easeOut(duration: 0.25)) { isPresented = false } }
}

#if DEBUG
#Preview("Series Player") {
    NavigationStack {
        SeriesPlayerView(drama: DramaItem(id: "1", title: "友情博弈", coverURL: "", category: "都市", tags: ["独家", "现代言情"], viewCount: 234000, episodeCount: 63, currentEpisode: 3, synopsis: "...", isHot: true, isTrending: false, rating: 4.8))
    }
}
#endif
