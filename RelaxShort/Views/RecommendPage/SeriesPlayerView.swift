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
    @StateObject private var offlineDownloads = OfflineDownloadManager.shared
    let handoff: PlayerHandoffContext?
    let sourceScene: String
    /// 标记 My List 初始 resume 是否已被消费
    @State private var hasConsumedInitialResume = false

    @State private var currentEpisode: Int
    @StateObject private var pagerState = VerticalVideoPagerState()
    @State private var showSpeedHUD = false
    @State private var showEpisodeList = false
    @State private var episodes: [Episode] = []
    @State private var episodesLoaded = false
    @State private var episodesLoadError: String?
    /// 缓存每集的后端 resumeTime，切集时使用当前 episode 的值
    @State private var episodeResumeTimes: [String: TimeInterval] = [:]
    @State private var unlockedEpisodes: Set<Int> = []
    @State private var episodeUnlockAdPlacement: AdPlacementConfig?
    @State private var isUIVisible = true
    @State private var autoHideTask: Task<Void, Never>?
    /// 缓存播放接口返回的媒体源（key = episodeId），避免切回已访问剧集时重复请求。
    @State private var episodeMediaSources: [String: PlayerMediaSource] = [:]
    /// 保留完整播放合同，清晰度和字幕菜单必须以当前集真实返回为准。
    @State private var episodePlayContracts: [String: PlaybackMediaSourceDTO] = [:]
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
    @State private var isSynopsisExpanded = false
    @State private var activePlayerPanel: PlayerPanel?
    /// 服务端播放合同是画质权益的唯一依据；StoreKit 本地状态只负责触发合同刷新。
    @State private var lastKnownVIPSubscriptionActive = false
    /// 会员状态变化时递增；旧代际的异步播放合同响应不得写回当前播放器。
    @State private var qualityEntitlementGeneration = 0
    @State private var selectedSubtitleID: String?
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
    /// 广告结束后的奖励确认在后台完成；确认期间隐藏完整解锁弹窗，只保留轻量加载态。
    @State private var isRewardedUnlockVerifying = false
    @State private var rewardedUnlockConfirmationTask: Task<Void, Never>?
    /// 同一解锁结果只允许恢复一次播放器，防止购买、账户刷新等回调并发重复提交。
    @State private var activeUnlockResumeEpisode: Int?
    /// 顶部返回动作已提前完成 Series → For You 所有权交接，onDisappear 不再重复释放。
    @State private var hasPreparedReturn = false
    /// 首次 AVPlayer/AVPlayerLayer 创建不得与 NavigationStack 的横向转场竞争主线程。
    @State private var hasCompletedNavigationTransition = false
    @State private var isPreparingDownload = false
    @State private var downloadNotice: String?

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
        case share

        var id: String {
            switch self {
            case .share: "share"
            }
        }
    }

    private enum PlayerPanel {
        case speed
        case settings
    }

    private enum UnlockAction {
        case coins
        case rewardedAd
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

                if let downloadNotice {
                    VStack {
                        Spacer()
                        Text(downloadNotice)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(.black.opacity(0.82))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.12), lineWidth: 0.8)
                            }
                            .padding(.horizontal, 28)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 96)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(300)
                }

                if showSpeedHUD {
                    speedProgressOverlay(in: geo)
                        .zIndex(45)
                }

                if showSpeedHUD {
                    SpeedHUDView()
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.16)
                        .transition(.opacity)
                }

                if let activePlayerPanel, unlockState == nil {
                    playerPanelOverlay(activePlayerPanel, in: geo)
                        .zIndex(220)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showEpisodeList, unlockState == nil {
                    EpisodePickerSheet(
                        drama: drama,
                        episodes: episodes,
                        currentEpisode: currentEpisode,
                        unlockedEpisodes: unlockedEpisodes,
                        episodesLoaded: episodesLoaded,
                        episodesLoadError: episodesLoadError,
                        isPresented: $showEpisodeList,
                        onSelectEpisode: { ep in
                            requestEpisodeSwitch(ep)
                        },
                        onRetryEpisodes: {
                            Task { @MainActor in
                                await loadEpisodes()
                            }
                        }
                    )
                    .zIndex(200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let unlockState {
                    if isRewardedUnlockVerifying {
                        EpisodeUnlockVerificationOverlay()
                            .zIndex(250)
                    } else if let unlockPurchaseTab {
                        unlockPurchaseOverlay(
                            unlockState,
                            initialTab: unlockPurchaseTab,
                            in: geo
                        )
                        .zIndex(300)
                    } else {
                        EpisodeUnlockOverlay(
                            state: unlockState,
                            containerWidth: geo.size.width,
                            containerHeight: geo.size.height,
                            safeAreaTop: geo.safeAreaInsets.top,
                            safeAreaBottom: geo.safeAreaInsets.bottom,
                            onClose: closeUnlockPanel,
                            onOpenPrimary: openPrimaryUnlockPanel,
                            onSelectMethod: selectUnlockMethod,
                            onPrimaryAction: handlePrimaryUnlockAction,
                            onRewardedAd: {
                                // 未命中预加载时保留弹窗并显示按钮 loading；广告就绪后再关闭。
                                Task { await performUnlock(action: .rewardedAd) }
                            },
                            onExitPlayback: { dismiss() }
                        )
                            .zIndex(250)
                    }
                } else if let episodeLoadError, !showEpisodeList, !isCurrentEpisodeVisible {
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
        .interactivePopGestureEnabled()
        .background {
            NavigationTransitionCompletionObserver {
                hasCompletedNavigationTransition = true
            }
            .frame(width: 0, height: 0)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .share:
                ShareSheet(
                    dramaTitle: drama.title,
                    seriesID: drama.id,
                    episodeNumber: currentEpisode
                )
                    .shareSheetPresentationStyle()
            }
        }
        .task(id: hasCompletedNavigationTransition) {
            guard hasCompletedNavigationTransition else { return }
            await startPlaybackSession()
            await dependencies.bookmarkStore.loadStatus(seriesIDs: [drama.id])
        }
        .onReceive(playerCoordinator.engine.$state) { state in
            playbackState = state
            if state == .playing {
                if isCurrentEpisodeVisible {
                    episodeLoadError = nil
                }
                resetAutoHide()
            }
            else if state == .pausedByUser { autoHideTask?.cancel() }
            else if case .failed(let message) = state, !isCurrentEpisodeVisible {
                episodeLoadError = message ?? "player.episode_load_failed_retry".localized
            }
        }
        .onReceive(playerCoordinator.engine.$hasVisiblePlaybackStarted) { started in
            guard started else { return }
            if isCurrentEpisodeVisible {
                episodeLoadError = nil
            }
            let elapsed = (CACurrentMediaTime() - playbackTraceStartedAt) * 1000
            Logger.player.info("SeriesTrace 首帧可见 原因=\(playbackTraceReason) 当前集=\(currentEpisode) 总耗时=\(Int(elapsed))ms")
        }
        .onReceive(playerCoordinator.engine.$selectedSubtitleID) { selectedSubtitleID = $0 }
        .onReceive(storeKitManager.$vipPurchaseState) { state in
            let isActive = state.hasActiveSubscription
            defer { lastKnownVIPSubscriptionActive = isActive }
            guard isActive != lastKnownVIPSubscriptionActive else { return }
            if !isActive {
                downgradeCurrentPlaybackAfterLocalVIPLoss()
                playerCoordinator.engine.setAdaptiveQualityPolicy(.standard)
                playerCoordinator.engine.applyAutomaticQualityPolicy()
            }
            let generation = invalidateCachedQualityEntitlements()
            Task {
                await refreshCurrentPlayContractForQualityEntitlement(
                    expectedGeneration: generation
                )
            }
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
            rewardedUnlockConfirmationTask?.cancel()
            Task { await dependencies.watchProgressReporter.finalize(completed: false) }
            if !hasPreparedReturn {
                playerCoordinator.release(.series(dramaID: drama.id))
            }
        }
    }

    /// 当前集已经有可见首帧时，任何旧的加载/失败提示都不能盖住视频。
    private var isCurrentEpisodeVisible: Bool {
        playerCoordinator.owner == .series(dramaID: drama.id)
            && playerCoordinator.engine.currentItem?.episodeNumber == currentEpisode
            && playerCoordinator.engine.hasVisiblePlaybackStarted
    }

    /// 网络或媒体失败不阻断上下滑动；用户可以重试当前集，也可以继续浏览其他集。
    private var isCurrentEpisodePlaying: Bool {
        isCurrentEpisodeVisible
            && playerCoordinator.engine.state == .playing
    }

    /// 播放设置使用页面内全宽底部面板，避免系统 Sheet 在不同设备上产生两侧留白。
    @ViewBuilder
    private func playerPanelOverlay(_ panel: PlayerPanel, in geo: GeometryProxy) -> some View {
        let safeBottom = max(geo.safeAreaInsets.bottom, UIApplication.safeAreaInsets.bottom)

        ZStack(alignment: .bottom) {
            Color.black.opacity(0.46)
                .contentShape(Rectangle())
                .onTapGesture { closePlayerPanel() }

            VStack(spacing: 0) {
                switch panel {
                case .speed:
                    PlayerSpeedPanel(
                        selectedRate: selectedPlaybackRate,
                        onSelectRate: applyPlaybackRate,
                        onClose: closePlayerPanel
                    )
                case .settings:
                    PlayerQualitySheet(
                        selectedRate: selectedPlaybackRate,
                        qualities: qualityOptions(),
                        subtitles: subtitleOptions(),
                        selectedSubtitleID: selectedSubtitleID,
                        onSelectRate: applyPlaybackRate,
                        onSelectQuality: applyQuality,
                        onSelectSubtitle: { subtitleID in
                            selectedSubtitleID = subtitleID
                            playerCoordinator.engine.selectSubtitle(subtitleID)
                        },
                        onClose: closePlayerPanel
                    )
                    .frame(height: max(0, geo.size.height * 0.7 - safeBottom))
                }

                Color(hex: "#111111")
                    .frame(height: safeBottom)
            }
            .frame(width: geo.size.width)
            .background(Color(hex: "#111111"))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    private func presentPlayerPanel(_ panel: PlayerPanel) {
        autoHideTask?.cancel()
        isUIVisible = true
        withAnimation(.easeOut(duration: 0.2)) {
            activePlayerPanel = panel
        }
    }

    private func closePlayerPanel() {
        withAnimation(.easeOut(duration: 0.2)) {
            activePlayerPanel = nil
        }
        resetAutoHide()
    }

    private func episodeLoadFailureOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button(L10n.retry) {
                retryCurrentEpisodePlayback()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .frame(height: 42)
            .background(.white, in: Capsule())
            Text("player.swipe_another_episode".localized)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(20)
        .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 金币与 VIP 购买中心共用播放器内的全宽底部面板，不依赖系统浮动 Sheet。
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
                    fetchAppleAccountToken: {
                        try await dependencies.detailRepository.fetchAppleAccountToken()
                    },
                    onCoinPurchaseCompleted: { balance in
                        if var latest = unlockState {
                            latest.balance = balance
                            latest.selection = .coins
                            unlockState = latest
                        }
                        unlockPurchaseTab = nil
                        Task { await performUnlock(action: .coins) }
                    },
                    onVIPPurchaseCompleted: { account in
                        coinStore.synchronize(balance: account.balance)
                        unlockPurchaseTab = nil
                        guard let targetEpisode = unlockState?.playbackTargetEpisode else { return }
                        Task { await resumeEpisodeAfterUnlock(targetEpisode) }
                    }
                )
                .id(initialTab)
                .frame(width: geo.size.width, height: panelHeight)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(true)
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
            Task { await performUnlock(action: .coins) }
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
        isRewardedUnlockVerifying = false
        rewardedUnlockConfirmationTask?.cancel()
        rewardedUnlockConfirmationTask = nil
        let episode = episodes.first(where: { $0.episodeNumber == episodeNumber })
        unlockState = EpisodeUnlockFlowState(
            episodeNumber: episodeNumber,
            coinCost: max(0, episode?.unlockCoinPrice ?? Episode.defaultUnlockCoinCost),
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
                    await resumeEpisodeAfterUnlock(state.playbackTargetEpisode)
                    return
                }
                state.balance = account.balance
                state.selection = state.vipOnly || account.balance < state.coinCost ? .vip : .coins
                unlockState = state
            } catch {
                guard var state = unlockState, state.episodeNumber == episodeNumber else { return }
                state.errorMessage = "player.balance_load_failed".localized
                unlockState = state
            }
        }
    }

    @MainActor
    private func performUnlock(action: UnlockAction) async {
        guard var state = unlockState,
              !state.isProcessing,
              let episodeID = episodeID(for: state.episodeNumber),
              action != .rewardedAd || state.canUnlockWithAd else { return }
        let targetEpisode = state.playbackTargetEpisode
        state.isProcessing = true
        state.isPreparingRewardedAd = action == .rewardedAd
        state.errorMessage = nil
        unlockState = state
        do {
            if action == .rewardedAd {
                let session = try await unlockEpisodeWithRewardedInterstitial(episodeID: episodeID)
                // 广告已经看完，立即收起完整解锁弹窗；奖励确认和播放恢复在后台继续。
                isRewardedUnlockVerifying = true
                rewardedUnlockConfirmationTask?.cancel()
                rewardedUnlockConfirmationTask = Task { @MainActor in
                    await completeRewardedUnlock(session, targetEpisode: targetEpisode)
                }
                return
            }
            let result = try await dependencies.detailRepository.unlockEpisodeWithCoins(episodeId: episodeID)
            guard result.unlocked else {
                throw APIError(code: "UNLOCK_FAILED", message: "player.unlock_failed".localized)
            }
            if let balance = result.balanceAfter {
                coinStore.synchronize(balance: balance)
            }
            await resumeEpisodeAfterUnlock(targetEpisode)
        } catch let error as APIError {
            if action == .rewardedAd {
                isRewardedUnlockVerifying = false
            }
            guard var latest = unlockState else { return }
            latest.isProcessing = false
            latest.isPreparingRewardedAd = false
            latest.errorMessage = error.code == "INSUFFICIENT_COINS"
                ? "player.insufficient_balance".localized
                : error.localizedDescription
            unlockState = latest
        } catch {
            if action == .rewardedAd {
                isRewardedUnlockVerifying = false
            }
            guard var latest = unlockState else { return }
            latest.isProcessing = false
            latest.isPreparingRewardedAd = false
            latest.errorMessage = "player.unlock_network_failed".localized
            unlockState = latest
        }
    }

    @MainActor
    private func unlockEpisodeWithRewardedInterstitial(episodeID: String) async throws -> AdRewardSession {
        let placement = try await resolvedEpisodeUnlockAdPlacement()

        // 点击时先确认缓存广告确实就绪；未命中时弹窗继续显示按钮 loading。
        guard await dependencies.adService.preloadRewardedAd(placement: placement) else {
            throw APIError(code: "AD_LOAD_FAILED", message: "reward.ad_load_failed".localized)
        }

        let session = try await dependencies.adRewardRepository.startSession(
            placementCode: placement.placementCode,
            rewardType: "unlock_episode",
            targetEpisodeID: episodeID
        )
        guard session.placement.format == .rewardedInterstitial else {
            await dependencies.adRewardRepository.cancelSession(session)
            throw APIError(code: "AD_FORMAT_MISMATCH", message: "reward.ad_config_mismatch".localized)
        }

        // 广告与后端会话均准备完成，下一步会立即 present；此时才关闭完整解锁弹窗。
        isRewardedUnlockVerifying = true

        let result = await dependencies.adService.showRewardedAd(
            placement: session.placement,
            ssvCustomData: session.ssvCustomData
        )
        switch result {
        case .rewarded:
            return session
        case .cancelled:
            await dependencies.adRewardRepository.cancelSession(session)
            throw APIError(code: "AD_NOT_COMPLETED", message: "player.ad_not_completed".localized)
        case .failed:
            await dependencies.adRewardRepository.cancelSession(session)
            throw APIError(code: "AD_LOAD_FAILED", message: "reward.ad_load_failed".localized)
        }
    }

    @MainActor
    private func completeRewardedUnlock(
        _ session: AdRewardSession,
        targetEpisode: Int
    ) async {
        defer { rewardedUnlockConfirmationTask = nil }

        do {
            try await confirmRewardedUnlock(session)
            guard unlockState?.playbackTargetEpisode == targetEpisode else {
                unlockState = nil
                unlockPurchaseTab = nil
                isRewardedUnlockVerifying = false
                return
            }

            await resumeEpisodeAfterUnlock(targetEpisode)

            // 播放源或播放器恢复失败时，不重新打开完整解锁弹窗，改成普通可重试提示。
            if let state = unlockState {
                let message = state.errorMessage ?? "player.entitlement_source_failed".localized
                let playbackVisible = isCurrentEpisodeVisible
                unlockState = nil
                unlockPurchaseTab = nil
                isRewardedUnlockVerifying = false
                episodeLoadError = playbackVisible ? nil : message
                if !playbackVisible {
                    playerCoordinator.engine.endContentTransitionWithoutMedia()
                }
            }
        } catch {
            unlockPurchaseTab = nil
            isRewardedUnlockVerifying = false
            // 确认失败时不留下死胡同重试层：重新打开解锁面板并给出错误，
            // 用户可以立即重试广告、金币或 VIP，播放页状态保持不动。
            if var state = unlockState {
                state.isProcessing = false
                state.isPreparingRewardedAd = false
                state.presentation = .primary
                state.errorMessage = (error as? APIError)?.code == "AD_REWARD_PENDING"
                    ? "player.unlock_pending".localized
                    : "player.unlock_network_failed".localized
                unlockState = state
            } else if !isCurrentEpisodeVisible {
                episodeLoadError = "player.entitlement_source_failed".localized
                playerCoordinator.engine.endContentTransitionWithoutMedia()
            }
        }
    }

    private func confirmRewardedUnlock(_ session: AdRewardSession) async throws {
        // 服务端客户端确认即发货；仅在网络异常时重试，不再长时间轮询等待 SSV。
        for attempt in 0..<3 {
            let completion: AdRewardCompletion
            do {
                completion = try await dependencies.adRewardRepository.completeSession(session)
            } catch {
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(500))
                    continue
                }
                throw error
            }
            if completion.isDelivered {
                return
            }
            if attempt < 2 {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw APIError(code: "AD_REWARD_PENDING", message: "player.unlock_pending".localized)
    }

    @MainActor
    private func resumeEpisodeAfterUnlock(_ episodeNumber: Int) async {
        guard let state = unlockState,
              state.playbackTargetEpisode == episodeNumber else {
            Logger.player.debug("忽略失效的解锁恢复回调 集数=\(episodeNumber)")
            return
        }
        guard activeUnlockResumeEpisode == nil else {
            Logger.player.debug("忽略重复的解锁恢复回调 集数=\(episodeNumber)")
            return
        }
        activeUnlockResumeEpisode = episodeNumber
        defer {
            if activeUnlockResumeEpisode == episodeNumber {
                activeUnlockResumeEpisode = nil
            }
        }

        let resumeStartedAt = CACurrentMediaTime()
        currentEpisode = episodeNumber
        episodeSwitchTask?.cancel()
        episodeSwitchTask = nil
        episodePrefetchTask?.cancel()
        episodePrefetchTask = nil
        episodePrefetchTarget = nil
        initialPlayAssetTask?.cancel()
        initialPlayAssetTask = nil

        guard let transitionToken = playerCoordinator.beginSeriesEpisodeTransition(
            dramaID: drama.id
        ) else {
            guard var state = unlockState else { return }
            state.isProcessing = false
            state.errorMessage = "player.state_changed_reenter".localized
            unlockState = state
            return
        }

        // 已通过权益确认后直接复用仍有效的播放合同；锁集阶段本来就不会缓存正式地址。
        // 不再无条件清空 episodeMediaSources，避免合法缓存命中时重复请求 /play。
        guard await ensurePlayAsset(for: episodeNumber) else {
            guard var state = unlockState else { return }
            state.isProcessing = false
            state.errorMessage = "player.entitlement_source_failed".localized
            unlockState = state
            return
        }

        prepareSelectedQuality(for: episodeNumber)
        let playable = buildPlayableItems(from: episodes)
        guard let playableIndex = playable.firstIndex(where: {
            $0.episodeNumber == episodeNumber
        }) else {
            playerCoordinator.engine.endContentTransitionWithoutMedia()
            guard var state = unlockState else { return }
            state.isProcessing = false
            state.errorMessage = "player.entitlement_episode_unavailable".localized
            unlockState = state
            return
        }

        let targetEpisodeID = episodeID(for: episodeNumber)
        let committed = playerCoordinator.commitSeriesEpisodeTransition(
            drama: drama,
            items: playable.map(\.item),
            startIndex: playableIndex,
            handoff: nil,
            // 本次权益刚刚解锁，必须从头连续起播。若传入 /play 返回的历史 resumeTime，
            // Coordinator 会先自动播放再异步 seek，形成“播一下、重新缓冲、再播放”。
            backendResumeTime: nil,
            token: transitionToken
        )
        guard committed else {
            guard var state = unlockState else { return }
            state.isProcessing = false
            state.errorMessage = "player.state_changed_retry".localized
            unlockState = state
            return
        }

        unlockedEpisodes.insert(episodeNumber)

        if let targetEpisodeID {
            Task {
                await dependencies.watchProgressReporter.begin(
                    seriesID: drama.id,
                    episodeID: targetEpisodeID
                )
            }
        }
        prefetchNextEpisode(after: episodeNumber)

        let contractAndCommitMs = (CACurrentMediaTime() - resumeStartedAt) * 1000
        Logger.player.info(
            "SeriesTrace 解锁后播放源已提交 集数=\(episodeNumber) 耗时=\(Int(contractAndCommitMs))ms"
        )

        // 解锁浮层继续覆盖准备中的播放器，避免用户看到播放器重新初始化或黑屏。
        // 首帧可见后立即关闭；弱网下最多等待 3 秒，超时后交给页面正常加载态。
        let firstFrameVisible = await waitForUnlockedEpisodeFirstFrame(
            episodeNumber,
            timeout: .seconds(3)
        )
        let totalResumeMs = (CACurrentMediaTime() - resumeStartedAt) * 1000
        Logger.player.info(
            "SeriesTrace 解锁后恢复完成 集数=\(episodeNumber) 首帧=\(firstFrameVisible) 总耗时=\(Int(totalResumeMs))ms"
        )

        isRewardedUnlockVerifying = false
        episodeLoadError = nil
        unlockState = nil
        unlockPurchaseTab = nil
        resetAutoHide()
    }

    @MainActor
    private func waitForUnlockedEpisodeFirstFrame(
        _ episodeNumber: Int,
        timeout: Duration
    ) async -> Bool {
        let targetMediaID = PlayerMediaItem.stableID(
            dramaID: drama.id,
            episodeNumber: episodeNumber
        )
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            guard playerCoordinator.owner == .series(dramaID: drama.id),
                  currentEpisode == episodeNumber else { return false }
            if playerCoordinator.engine.currentItem?.id == targetMediaID,
               playerCoordinator.engine.hasVisiblePlaybackStarted {
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return false
    }

    @MainActor
    private func refreshEntitlementAfterMembership() async {
        guard var state = unlockState else { return }
        do {
            let account = try await dependencies.detailRepository.fetchUnlockAccount()
            coinStore.synchronize(balance: account.balance)
            if account.isVIP {
                await resumeEpisodeAfterUnlock(state.playbackTargetEpisode)
            } else {
                state.balance = account.balance
                unlockState = state
            }
        } catch {
            state.errorMessage = "player.membership_refresh_failed".localized
            unlockState = state
        }
    }

    // MARK: - 自动隐藏

    private func resetAutoHide() {
        autoHideTask?.cancel()
        isUIVisible = true
        guard playerCoordinator.engine.state == .playing,
              activePlayerPanel == nil else { return }
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
        episodesLoaded = false
        episodesLoadError = nil
        do {
            episodes = try await repo.fetchEpisodes(dramaId: drama.id)
            unlockedEpisodes = Set(
                episodes.lazy
                    .filter { $0.isLocked && $0.isUnlocked }
                    .map(\.episodeNumber)
            )
            episodesLoaded = true
            Task { @MainActor in
                await preloadEpisodeUnlockAd()
            }
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.info("SeriesTrace 剧集列表加载完成 剧ID=\(drama.id) 数量=\(episodes.count) 耗时=\(Int(elapsed))ms")
            playerCoordinator.engine.markTrace("剧集列表")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            Logger.viewModel.error("SeriesPlayerView: fetchEpisodes failed: \(error)")
            episodesLoaded = false
            episodesLoadError = "player.load_failed_retry".localized
            if playerCoordinator.engine.currentItem?.id != PlayerMediaItem.stableID(
                dramaID: drama.id,
                episodeNumber: currentEpisode
            ), !isCurrentEpisodePlaying {
                episodeLoadError = "player.load_failed_retry".localized
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
        let hasPlayAsset = await ensurePlayAsset(for: currentEpisode)
        guard !Task.isCancelled,
              hasPlayAsset,
              unlockState == nil else { return }
        initializeEpisodePlayer()
    }

    /// 首屏播放合同快速通道。成功后直接把媒体交给共享 Coordinator/Engine 起播，
    /// 同时写入页面级播放源缓存，后续 episodes 流程复用结果，不再重复请求。
    @MainActor
    private func fetchInitialPlayAsset(episodeID: String, episodeNumber: Int) async -> Bool {
        if episodeMediaSources[episodeID] != nil { return true }
        let entitlementGeneration = qualityEntitlementGeneration
        let startedAt = CACurrentMediaTime()
        Logger.player.info("SeriesTrace 并行请求首屏播放源 集数=\(episodeNumber) 剧集ID=\(episodeID)")
        do {
            let dto = try await dependencies.detailRepository.fetchPlayAsset(episodeId: episodeID)
            guard !Task.isCancelled,
                  entitlementGeneration == qualityEntitlementGeneration,
                  let source = dto.toPlayerMediaSource() else { return false }
            episodeMediaSources[episodeID] = source
            episodePlayContracts[episodeID] = dto
            if episodeNumber == currentEpisode, selectedQualityID == "auto" {
                applyAutomaticQualityPolicy(from: dto)
            }
            if episodeNumber == currentEpisode {
                episodeLoadError = nil
            }
            if let resume = dto.resumeTime, resume > 0 {
                episodeResumeTimes[episodeID] = TimeInterval(resume)
            }
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.info("SeriesTrace 首屏播放源并行请求成功 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms")
            playerCoordinator.engine.markTrace("播放源")

            guard playerCoordinator.owner == .series(dramaID: drama.id),
                  unlockState == nil else { return true }
            let item = PlayerMediaItem(
                id: PlayerMediaItem.stableID(dramaID: drama.id, episodeNumber: episodeNumber),
                title: drama.title,
                episodeNumber: episodeNumber,
                coverURL: drama.coverURL,
                source: source,
                externalSubtitles: dto.toPlayerSubtitleTracks(),
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
        prepareSelectedQuality(for: currentEpisode)
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

            let synopsis = drama.synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
            if !synopsis.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isSynopsisExpanded.toggle()
                    }
                    resetAutoHide()
                } label: {
                    HStack(alignment: .bottom, spacing: 6) {
                        Text(synopsis)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(isSynopsisExpanded ? nil : 2)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Image(systemName: isSynopsisExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.88))
                            .frame(width: 18, height: 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var membershipDownloadRow: some View {
        HStack {
            Button {} label: {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("membership.join".localized)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DB.gold)
                .padding(.horizontal, 14)
                .frame(height: ChromeMetrics.membershipRowHeight)
                .background(Capsule().fill(DB.gold.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Task { await downloadCurrentEpisode() }
            } label: {
                HStack(spacing: 5) {
                    if isPreparingDownload {
                        ProgressView()
                            .tint(.white.opacity(0.72))
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: currentDownloadIcon)
                    }
                    Text(currentDownloadTitle)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.72))
                .frame(height: ChromeMetrics.membershipRowHeight)
            }
            .buttonStyle(.plain)
            .disabled(isPreparingDownload)
        }
    }

    private var currentDownloadItem: OfflineDownloadItem? {
        guard let episodeID = episodes.first(
            where: { $0.episodeNumber == currentEpisode }
        )?.id else { return nil }
        return offlineDownloads.item(episodeID: episodeID)
    }

    private var currentDownloadIcon: String {
        switch currentDownloadItem?.status {
        case .completed:
            return "checkmark.circle.fill"
        case .queued, .downloading, .paused:
            return "arrow.down.circle.fill"
        case .failed, .none:
            return "arrow.down.circle"
        }
    }

    private var currentDownloadTitle: String {
        switch currentDownloadItem?.status {
        case .completed:
            return "downloads.completed".localized
        case .queued, .downloading:
            return "downloads.downloading_short".localized
        case .paused:
            return "downloads.paused".localized
        case .failed, .none:
            return L10n.download
        }
    }

    @MainActor
    private func downloadCurrentEpisode() async {
        guard !isPreparingDownload else { return }
        guard let episode = episodes.first(
            where: { $0.episodeNumber == currentEpisode }
        ) else {
            showDownloadNotice("downloads.error.episode_unavailable".localized)
            return
        }

        if let existing = offlineDownloads.item(episodeID: episode.id) {
            switch existing.status {
            case .paused, .failed:
                offlineDownloads.resume(existing.id)
                showDownloadNotice("downloads.resumed".localized)
            case .queued, .downloading:
                showDownloadNotice("downloads.already_downloading".localized)
            case .completed:
                showDownloadNotice("downloads.already_downloaded".localized)
            }
            return
        }

        // 受保护内容必须使用 FairPlay 离线合同；当前播放接口仅返回在线 URL，
        // 不能把受保护 MP4 直接落到普通文件目录。
        guard !episode.isLocked, !episode.requiresVIP else {
            showDownloadNotice("downloads.error.protected_unavailable".localized)
            return
        }

        isPreparingDownload = true
        defer { isPreparingDownload = false }
        do {
            let contract: PlaybackMediaSourceDTO
            if let cached = episodePlayContracts[episode.id] {
                contract = cached
            } else {
                let entitlementGeneration = qualityEntitlementGeneration
                contract = try await dependencies.detailRepository.fetchPlayAsset(
                    episodeId: episode.id
                )
                if entitlementGeneration == qualityEntitlementGeneration {
                    episodePlayContracts[episode.id] = contract
                }
            }
            guard let rawURL = contract.fallbackMp4Url
                    ?? (contract.sourceType == "mp4" ? contract.preferredPlaybackURL : nil),
                  let remoteURL = URL(string: rawURL) else {
                showDownloadNotice("downloads.error.mp4_required".localized)
                return
            }

            try offlineDownloads.enqueue(
                OfflineDownloadRequest(
                    dramaID: drama.id,
                    episodeID: episode.id,
                    dramaTitle: drama.title,
                    coverURL: drama.coverURL,
                    episodeNumber: episode.episodeNumber,
                    totalEpisodes: totalEpisodes,
                    remoteURL: remoteURL,
                    isProtected: false
                )
            )
            showDownloadNotice("downloads.started".localized)
        } catch {
            showDownloadNotice(error.localizedDescription)
        }
    }

    private func showDownloadNotice(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            downloadNotice = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard downloadNotice == message else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                downloadNotice = nil
            }
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
        let autoMaxHeight = currentPlayContract?.autoMaxHeight ?? 720
        let auto = PlayerQualitySheet.QualityOption(
            id: "auto",
            label: "Auto",
            detail: autoMaxHeight >= 1080
                ? "player.quality_auto_vip".localized
                : "player.quality_auto_standard".localized,
            isVIP: false,
            isAvailable: true,
            isSelected: selectedQualityID == "auto"
        )
        guard let contract = currentPlayContract else { return [auto] }

        var seen = Set<String>()
        let renditions = contract.qualities
            .sorted { qualityResolution($0) > qualityResolution($1) }
            .compactMap { quality -> PlayerQualitySheet.QualityOption? in
                guard let id = normalizedQualityID(quality.quality),
                      id != "auto" else { return nil }

                let resolution = qualityResolution(quality)
                let isVIP = resolution == 1080
                if isVIP {
                    // 非会员只展示真实合同中的 1080P VIP 入口；会员合同若缺 URL
                    // 或明确不可选，视为异常合同并隐藏，避免一个无法工作的按钮。
                    if contract.has1080Entitlement,
                       (quality.selectable != true || renditionURL(quality) == nil) {
                        return nil
                    }
                    guard seen.insert(id).inserted else { return nil }
                    return .init(
                        id: id,
                        label: qualityLabel(quality),
                        detail: nil,
                        isVIP: true,
                        isAvailable: isManualRenditionAvailable(quality, in: contract),
                        isSelected: selectedQualityID == id
                    )
                }

                // 540P/720P 等免费档只在合同真实给出可用 URL 时出现；
                // 异常的免费档直接隐藏，不再错误显示锁图标。
                guard quality.vipRequired != true,
                      quality.selectable != false,
                      renditionURL(quality) != nil,
                      seen.insert(id).inserted else { return nil }
                return .init(
                    id: id,
                    label: qualityLabel(quality),
                    detail: nil,
                    isVIP: false,
                    isAvailable: true,
                    isSelected: selectedQualityID == id
                )
        }
        return [auto] + renditions
    }

    private func normalizedQualityID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy(\.isNumber) {
            return "\(trimmed)p"
        }
        return trimmed
    }

    private func qualityResolution(_ quality: QualityDTO) -> Int {
        if let id = normalizedQualityID(quality.quality) {
            let digits = id.filter(\.isNumber)
            if let value = Int(digits), value > 0 { return value }
        }
        let dimensions = [quality.width, quality.height].compactMap { $0 }.filter { $0 > 0 }
        return dimensions.min() ?? 0
    }

    private func qualityLabel(_ quality: QualityDTO) -> String {
        let resolution = qualityResolution(quality)
        if resolution > 0 { return "\(resolution)P" }
        return quality.quality?.uppercased() ?? ""
    }

    private func renditionURL(_ quality: QualityDTO) -> URL? {
        guard let rawURL = quality.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func source(for quality: QualityDTO) -> PlayerMediaSource? {
        guard let url = renditionURL(quality) else { return nil }
        return url.pathExtension.lowercased() == "m3u8"
            ? .hls(masterURL: url)
            : .mp4(url)
    }

    private func isManualRenditionAvailable(
        _ quality: QualityDTO,
        in contract: PlaybackMediaSourceDTO
    ) -> Bool {
        guard renditionURL(quality) != nil else { return false }
        if qualityResolution(quality) == 1080 {
            return contract.has1080Entitlement && quality.selectable == true
        }
        return quality.vipRequired != true && quality.selectable != false
    }

    private func manualSource(
        qualityID: String,
        in contract: PlaybackMediaSourceDTO
    ) -> PlayerMediaSource? {
        guard let rendition = contract.qualities.first(where: {
            normalizedQualityID($0.quality) == qualityID
        }), isManualRenditionAvailable(rendition, in: contract) else { return nil }
        return source(for: rendition)
    }

    /// 将本剧用户选择的手动画质解析成目标集真实 URL。
    /// 合同尚未拿到时保留用户选择；只有完整合同确认缺档时，切集入口才允许回 Auto。
    @discardableResult
    private func prepareSelectedQuality(
        for episodeNumber: Int,
        updateSelectionOnFallback: Bool = true
    ) -> Bool {
        guard let episodeID = episodeID(for: episodeNumber) else { return false }
        guard let contract = episodePlayContracts[episodeID] else {
            return selectedQualityID == "auto" && episodeMediaSources[episodeID] != nil
        }

        if selectedQualityID != "auto" {
            if let selectedSource = manualSource(qualityID: selectedQualityID, in: contract) {
                episodeMediaSources[episodeID] = selectedSource
                applyManualQualityPolicy(selectedQualityID)
                return true
            }

            // 预取阶段不提前改变当前页面的用户选择，也不拿 Auto 源冒充固定画质预热。
            guard updateSelectionOnFallback else { return false }
            selectedQualityID = "auto"
        }

        guard let automaticSource = contract.toPlayerMediaSource() else { return false }
        episodeMediaSources[episodeID] = automaticSource
        if episodeNumber == currentEpisode {
            applyAutomaticQualityPolicy(from: contract)
        }
        return true
    }

    private func applyManualQualityPolicy(_ qualityID: String) {
        let resolution = Int(qualityID.filter(\.isNumber)) ?? 0
        playerCoordinator.engine.setAdaptiveQualityPolicy(
            resolution == 1080 ? .vip : .standard
        )
    }

    private func subtitleOptions() -> [PlayerSubtitleOption] {
        let available = playerCoordinator.engine.availableSubtitles
        if !available.isEmpty { return available }
        return currentPlayContract?.toPlayerSubtitleTracks().map {
            PlayerSubtitleOption(id: $0.id, displayName: $0.displayName, languageCode: $0.languageCode)
        } ?? []
    }

    private var currentPlayContract: PlaybackMediaSourceDTO? {
        guard let episodeID = currentBackendEpisodeID else { return nil }
        return episodePlayContracts[episodeID]
    }

    private func applyQuality(_ qualityID: String) {
        guard let episodeID = currentBackendEpisodeID,
              let contract = episodePlayContracts[episodeID],
              let currentItem = playerCoordinator.engine.currentItem,
              currentItem.episodeNumber == currentEpisode,
              currentItem.id == PlayerMediaItem.stableID(
                  dramaID: drama.id,
                  episodeNumber: currentEpisode
              ) else { return }

        let normalizedID = normalizedQualityID(qualityID) ?? qualityID
        let selectedSource: PlayerMediaSource
        if normalizedID == "auto" {
            guard let automaticSource = contract.toPlayerMediaSource() else { return }
            selectedSource = automaticSource
        } else {
            guard let rendition = contract.qualities.first(where: {
                normalizedQualityID($0.quality) == normalizedID
            }) else { return }

            guard isManualRenditionAvailable(rendition, in: contract) else {
                if qualityResolution(rendition) == 1080,
                   !contract.has1080Entitlement {
                    appStore.isShowingMembership = true
                }
                return
            }
            guard let renditionSource = source(for: rendition) else { return }
            selectedSource = renditionSource
        }

        if normalizedID != "auto" {
            applyManualQualityPolicy(normalizedID)
        }

        let updatedItem = PlayerMediaItem(
            id: currentItem.id,
            title: currentItem.title,
            episodeNumber: currentItem.episodeNumber,
            coverURL: currentItem.coverURL,
            source: selectedSource,
            externalSubtitles: contract.toPlayerSubtitleTracks(),
            resumeTime: currentItem.resumeTime,
            allowsPersistentCache: currentItem.allowsPersistentCache
        )
        selectedQualityID = normalizedID
        episodeMediaSources[episodeID] = selectedSource
        if playerCoordinator.engine.upgradeCurrentSource(to: updatedItem) {
            playerCoordinator.engine.setRate(selectedPlaybackRate)
        }
        if normalizedID == "auto" {
            applyAutomaticQualityPolicy(from: contract)
        }
        restartNextEpisodePrefetchForQuality()
        resetAutoHide()
    }

    private func applyAutomaticQualityPolicy(from contract: PlaybackMediaSourceDTO? = nil) {
        let vipAuto = contract?.autoMaxHeight == 1080
        playerCoordinator.engine.setAdaptiveQualityPolicy(vipAuto ? .vip : .standard)
        playerCoordinator.engine.applyAutomaticQualityPolicy()
    }

    /// 本地会员状态失效时先退出固定 1080P，并立即换到合同中最高的免费档。
    /// 后端新合同返回后，再由 Auto 切到不含 1080P 的标准 master。
    private func downgradeCurrentPlaybackAfterLocalVIPLoss() {
        guard (Int(selectedQualityID.filter(\.isNumber)) ?? 0) == 1080 else { return }
        selectedQualityID = "auto"

        guard let episodeID = currentBackendEpisodeID,
              let contract = episodePlayContracts[episodeID],
              let currentItem = playerCoordinator.engine.currentItem,
              currentItem.episodeNumber == currentEpisode,
              currentItem.id == PlayerMediaItem.stableID(
                  dramaID: drama.id,
                  episodeNumber: currentEpisode
              ),
              let freeRendition = contract.qualities
                  .filter({ quality in
                      let resolution = qualityResolution(quality)
                      return resolution > 0 && resolution <= 720
                          && isManualRenditionAvailable(quality, in: contract)
                  })
                  .max(by: { qualityResolution($0) < qualityResolution($1) }),
              let freeSource = source(for: freeRendition) else {
            if let episodeID = currentBackendEpisodeID {
                episodeMediaSources.removeValue(forKey: episodeID)
            }
            playerCoordinator.engine.pause(reason: .system)
            return
        }

        episodeMediaSources[episodeID] = freeSource
        let downgradedItem = PlayerMediaItem(
            id: currentItem.id,
            title: currentItem.title,
            episodeNumber: currentItem.episodeNumber,
            coverURL: currentItem.coverURL,
            source: freeSource,
            externalSubtitles: currentItem.externalSubtitles,
            resumeTime: currentItem.resumeTime,
            allowsPersistentCache: currentItem.allowsPersistentCache
        )
        if playerCoordinator.engine.upgradeCurrentSource(to: downgradedItem) {
            playerCoordinator.engine.setRate(selectedPlaybackRate)
        }
    }

    /// 会员状态变化后，所有旧合同和非当前集预取源立即失效。
    /// 当前集媒体仅为连续播放暂存，随后必须由新一代服务端合同覆盖。
    @discardableResult
    private func invalidateCachedQualityEntitlements() -> Int {
        qualityEntitlementGeneration &+= 1
        activePlayerPanel = nil
        episodePrefetchTask?.cancel()
        episodePrefetchTask = nil
        episodePrefetchTarget = nil
        initialPlayAssetTask?.cancel()
        initialPlayAssetTask = nil

        let currentEpisodeID = currentBackendEpisodeID
        let currentSource = currentEpisodeID.flatMap { episodeMediaSources[$0] }
        episodePlayContracts.removeAll()
        episodeMediaSources.removeAll()
        if let currentEpisodeID, let currentSource {
            episodeMediaSources[currentEpisodeID] = currentSource
        }
        for index in episodes.indices where episodes[index].id != currentEpisodeID {
            episodes[index].videoURL = ""
        }
        return qualityEntitlementGeneration
    }

    /// StoreKit 变化后重新向后端取当前集合同。服务端确认 VIP 后才下发完整 1080P master；
    /// 不用本地购买状态直接抬高画质，避免验单未完成时越权。
    @MainActor
    private func refreshCurrentPlayContractForQualityEntitlement(
        expectedGeneration: Int
    ) async {
        let requestedEpisode = currentEpisode
        guard let episodeID = episodeID(for: requestedEpisode) else { return }
        do {
            let contract = try await dependencies.detailRepository.fetchPlayAsset(
                episodeId: episodeID
            )
            guard !Task.isCancelled,
                  expectedGeneration == qualityEntitlementGeneration,
                  currentEpisode == requestedEpisode,
                  currentBackendEpisodeID == episodeID else { return }
            episodePlayContracts[episodeID] = contract
            // 必须由新合同重建 source；不能在权益变化后继续复用旧 1080P 或旧 Auto master。
            guard prepareSelectedQuality(for: requestedEpisode) else {
                episodeMediaSources.removeValue(forKey: episodeID)
                playerCoordinator.engine.pause(reason: .system)
                episodeLoadError = "player.episode_load_failed_retry".localized
                return
            }
            if let source = episodeMediaSources[episodeID],
               let currentItem = playerCoordinator.engine.currentItem,
               currentItem.episodeNumber == requestedEpisode,
               currentItem.id == PlayerMediaItem.stableID(
                   dramaID: drama.id,
                   episodeNumber: requestedEpisode
               ) {
                let refreshedItem = PlayerMediaItem(
                    id: currentItem.id,
                    title: currentItem.title,
                    episodeNumber: currentItem.episodeNumber,
                    coverURL: currentItem.coverURL,
                    source: source,
                    externalSubtitles: contract.toPlayerSubtitleTracks(),
                    resumeTime: currentItem.resumeTime,
                    allowsPersistentCache: currentItem.allowsPersistentCache
                )
                if playerCoordinator.engine.upgradeCurrentSource(to: refreshedItem) {
                    playerCoordinator.engine.setRate(selectedPlaybackRate)
                }
            }
            if selectedQualityID == "auto" {
                applyAutomaticQualityPolicy(from: contract)
            }
            restartNextEpisodePrefetchForQuality()
        } catch {
            Logger.player.warning("SeriesTrace 画质权益合同刷新失败 剧集ID=\(episodeID) 错误=\(error.localizedDescription)")
        }
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
        activePlayerPanel = nil
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
        resetAutoHide()

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

            // 当前短剧内保留用户手动画质；目标集没有同档位或权益已变化时安全回 Auto。
            prepareSelectedQuality(for: target)

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
                if episodeLoadError == nil, !isCurrentEpisodePlaying {
                    episodeLoadError = "player.episode_load_failed_retry".localized
                }
                return
            }
            initializeEpisodePlayer()
        }
    }

    @MainActor
    private func preloadEpisodeUnlockAd() async {
        do {
            let config = try await dependencies.adConfigRepository.fetchAdsConfig()
            let placement = config.interstitialUnlockEpisode
            guard config.adsEnabled,
                  placement.enabled,
                  placement.format == .rewardedInterstitial else { return }
            episodeUnlockAdPlacement = placement
            await dependencies.adService.preloadRewardedAd(placement: placement)
        } catch {
            Logger.store.info("Episode unlock ad preload unavailable: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func resolvedEpisodeUnlockAdPlacement() async throws -> AdPlacementConfig {
        if let episodeUnlockAdPlacement { return episodeUnlockAdPlacement }
        let config = try await dependencies.adConfigRepository.fetchAdsConfig()
        let placement = config.interstitialUnlockEpisode
        guard config.adsEnabled,
              placement.enabled,
              placement.format == .rewardedInterstitial else {
            throw APIError(code: "ADS_NOT_AVAILABLE", message: "player.ad_unlock_unavailable".localized)
        }
        episodeUnlockAdPlacement = placement
        await dependencies.adService.preloadRewardedAd(placement: placement)
        return placement
    }

    /// 页面只提前获取下一集播放合同；真正的媒体预加载统一交给共享 PlayerSlotPool。
    /// 这样 For You 与 Series 使用完全相同的静音 next + 原生 preroll 规则。
    private func restartNextEpisodePrefetchForQuality() {
        episodePrefetchTask?.cancel()
        episodePrefetchTask = nil
        episodePrefetchTarget = nil
        prefetchNextEpisode(after: currentEpisode)
    }

    private func prefetchNextEpisode(after episodeNumber: Int) {
        guard let nextEpisode = episodes.first(where: { $0.episodeNumber == episodeNumber + 1 }) else { return }
        if episodePrefetchTarget == nextEpisode.episodeNumber, episodePrefetchTask != nil {
            return
        }

        episodePrefetchTask?.cancel()
        episodePrefetchTarget = nextEpisode.episodeNumber

        episodePrefetchTask = Task { @MainActor in
            // 手动画质必须先拿到下一集完整 /play 合同，再生成同一固定档位的 source。
            // 仅有默认 URL 时不能把 Auto preroll 当成用户选择的画质。
            guard await ensurePlayAsset(
                for: nextEpisode.episodeNumber,
                recordTrace: false
            ) else { return false }
            guard !Task.isCancelled,
                  prepareSelectedQuality(
                    for: nextEpisode.episodeNumber,
                    updateSelectionOnFallback: false
                  ),
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
        let requiresPlayContract = selectedQualityID != "auto"

        // Auto 可直接复用默认源；手动画质必须同时具备完整 /play 合同，
        // 否则无法证明目标集真实存在同一档位。
        if episodeMediaSources[episodeId] != nil,
           !requiresPlayContract || episodePlayContracts[episodeId] != nil {
            if recordTrace, episodeNumber == currentEpisode { episodeLoadError = nil }
            Logger.player.info("SeriesTrace 播放源命中内存缓存 集数=\(episodeNumber)")
            if recordTrace { playerCoordinator.engine.markTrace("缓存命中") }
            return true
        }

        // Episode 自带 videoURL 只足够支撑 Auto；固定画质仍需请求 /play 合同。
        if !requiresPlayContract,
           let url = URL(string: ep.videoURL),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            episodeMediaSources[episodeId] = playerSource(for: url)
            if recordTrace, episodeNumber == currentEpisode { episodeLoadError = nil }
            Logger.player.info("SeriesTrace 播放源使用剧集URL 集数=\(episodeNumber)")
            if recordTrace { playerCoordinator.engine.markTrace("剧集URL") }
            return true
        }

        // 首屏播放合同可能正在与剧集列表并行请求；等待同一 Task，禁止重复调用 /play。
        if episodeId == (initialEpisodeID ?? drama.previewEpisodeID),
           let initialTask = initialPlayAssetTask {
            let generationBeforeAwait = qualityEntitlementGeneration
            let success = await initialTask.value
            guard !Task.isCancelled else { return false }
            if success, episodeMediaSources[episodeId] != nil,
               !requiresPlayContract || episodePlayContracts[episodeId] != nil {
                if recordTrace { playerCoordinator.engine.markTrace("首屏播放源复用") }
                return true
            }
            if success, requiresPlayContract {
                Logger.player.info("SeriesTrace 首屏默认源缺少手动画质合同，继续请求 /play 集数=\(episodeNumber)")
            } else if generationBeforeAwait != qualityEntitlementGeneration {
                // 会员状态变化取消了旧首屏请求，本轮直接按新代际继续请求。
                self.initialPlayAssetTask = nil
                Logger.player.info("SeriesTrace 首屏合同权益代际变化，重新请求 /play 集数=\(episodeNumber)")
            } else {
                // 同一次请求已经明确失败或被权益拦截，本轮不再立即重试相同接口。
                if recordTrace, unlockState == nil,
                   episodeNumber == currentEpisode, !isCurrentEpisodePlaying {
                    episodeLoadError = "player.episode_load_failed_retry".localized
                }
                return false
            }
        }

        // 请求后端播放合同
        let entitlementGeneration = qualityEntitlementGeneration
        let startedAt = CACurrentMediaTime()
        Logger.player.info("SeriesTrace 请求播放源 集数=\(episodeNumber) 剧集ID=\(episodeId)")
        do {
            let dto = try await dependencies.detailRepository.fetchPlayAsset(episodeId: episodeId)
            guard !Task.isCancelled else { return false }
            if entitlementGeneration != qualityEntitlementGeneration {
                return await ensurePlayAsset(for: episodeNumber, recordTrace: recordTrace)
            }
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            if let url = dto.preferredPlaybackURL {
                episodes[epIndex].videoURL = url
            }
            if let source = dto.toPlayerMediaSource() {
                episodeMediaSources[episodeId] = source
                episodePlayContracts[episodeId] = dto
                if episodeNumber == currentEpisode, selectedQualityID == "auto" {
                    applyAutomaticQualityPolicy(from: dto)
                }
                if let resume = dto.resumeTime, resume > 0 {
                    episodeResumeTimes[episodeId] = TimeInterval(resume)
                }
                unlockedEpisodes.insert(episodeNumber)
                if recordTrace, episodeNumber == currentEpisode { episodeLoadError = nil }
                Logger.player.info("SeriesTrace 播放源请求成功 集数=\(episodeNumber) 类型=\(dto.sourceType) 耗时=\(Int(elapsed))ms")
                if recordTrace { playerCoordinator.engine.markTrace("播放源") }
                return true
            }
            Logger.player.warning("SeriesTrace 播放源为空 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms")
            if recordTrace, episodeNumber == currentEpisode {
                episodeLoadError = "player.episode_unavailable".localized
                playerCoordinator.engine.markTrace("播放源失败-EP\(episodeNumber)")
                playerCoordinator.engine.finishTrace(termination: "播放源失败")
            }
            return false
        } catch let error as APIError where error.code == "EPISODE_LOCKED" {
            guard !Task.isCancelled else { return false }
            if entitlementGeneration != qualityEntitlementGeneration {
                return await ensurePlayAsset(for: episodeNumber, recordTrace: recordTrace)
            }
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.warning("SeriesTrace 剧集被锁定 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms 已进入解锁流程")
            if recordTrace, episodeNumber == currentEpisode {
                episodeLoadError = nil
                playerCoordinator.engine.markTrace("锁集阻断-EP\(episodeNumber)")
                playerCoordinator.engine.finishTrace(termination: "锁集阻断")
            }
            if recordTrace, episodeNumber == currentEpisode {
                presentEpisodeUnlock(episodeNumber)
            }
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            if entitlementGeneration != qualityEntitlementGeneration {
                return await ensurePlayAsset(for: episodeNumber, recordTrace: recordTrace)
            }
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.warning("SeriesTrace 播放源请求失败 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms 错误=\(error.localizedDescription)")
            if recordTrace, episodeNumber == currentEpisode, !isCurrentEpisodePlaying {
                episodeLoadError = "player.episode_load_failed_retry".localized
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
            return playerSource(for: url)
        }
        return nil
    }

    private func playerSource(for url: URL) -> PlayerMediaSource {
        url.pathExtension.lowercased() == "m3u8" ? .hls(masterURL: url) : .mp4(url)
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
                    externalSubtitles: episodePlayContracts[ep.id]?.toPlayerSubtitleTracks() ?? [],
                    resumeTime: resume,
                    // 普通免费集与 For You 共用公开 MP4 Range 缓存；受保护内容不落普通缓存。
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
            CompactSecondaryBackButton {
                dismissSeries()
            }

            Text("EP.\(episodeNumber)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

            Spacer()

            Button {
                presentPlayerPanel(.speed)
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
            .accessibilityLabel("player.speed".localized)

            Button {
                presentPlayerPanel(.settings)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(90))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("player.playback_settings".localized)
        }
        .frame(height: ChromeMetrics.topBarHeight)
        .padding(.horizontal, ChromeMetrics.horizontalPadding)
    }

    private var speedControlTitle: String {
        if abs(selectedPlaybackRate - 1.0) < 0.01 {
            return "player.speed".localized
        }
        let hundredths = Int((selectedPlaybackRate * 100).rounded())
        return hundredths.isMultiple(of: 10)
            ? String(format: "%.1fx", selectedPlaybackRate)
            : String(format: "%.2fx", selectedPlaybackRate)
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
        .accessibilityLabel(
            playbackState == .playing
                ? "player.pause".localized
                : "player.play".localized
        )
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
                    isActive: isCurrent,
                    showsSystemPlaybackButton: false
                )
                .allowsHitTesting(false)

                // 相邻页在拖动露出时也渲染自己的 EP/Speed/菜单；提交后当前页
                // 立即进入 3 秒可见窗口，不等待新视频首帧或 playing 回调。
                if (isUIVisible || !isCurrent), !showSpeedHUD {
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

                    if isCurrent,
                       playerCoordinator.engine.currentPlayer != nil,
                       playerCoordinator.engine.hasVisiblePlaybackStarted {
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
              activeSheet == nil, activePlayerPanel == nil,
              !showSpeedHUD else { return false }
        guard value.startLocation.x > 24 else { return false }
        guard abs(value.translation.height) > abs(value.translation.width) * 1.2 else { return false }
        return true
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard unlockState == nil, activePlayerPanel == nil else { return }
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
                guard unlockState == nil, activePlayerPanel == nil else { return }
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
                guard unlockState == nil, activePlayerPanel == nil else { return }
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

}

#if DEBUG
#Preview("Series Player") {
    NavigationStack {
        SeriesPlayerView(drama: DramaItem(id: "1", title: "友情博弈", coverURL: "", category: "都市", tags: ["独家", "现代言情"], viewCount: 234000, episodeCount: 63, currentEpisode: 3, synopsis: "...", isHot: true, isTrending: false, rating: 4.8))
    }
}
#endif
