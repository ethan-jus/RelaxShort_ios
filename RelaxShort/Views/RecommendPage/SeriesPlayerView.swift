import SwiftUI
import AVKit

// MARK: - Series Player View (接入 ShortVideoPlayerEngine)

struct SeriesPlayerView: View {

    let drama: DramaItem
    let startEpisode: Int
    let initialEpisodeID: String?
    let initialResumeTime: TimeInterval?
    @EnvironmentObject var dependencies: DependencyContainer
    let handoff: PlayerHandoffContext?
    let sourceScene: String
    /// 标记 My List 初始 resume 是否已被消费
    @State private var hasConsumedInitialResume = false

    @State private var currentEpisode: Int
    @State private var dragOffset: CGFloat = 0
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
    @State private var isSpeeding = false
    @State private var isSwitchingEpisode = false
    @State private var playbackState: PlayerPlaybackState = .idle
    @State private var playbackProgress = PlayerProgress()
    @State private var selectedPlaybackRate: Float = 1.0
    @State private var selectedQualityID = "auto"
    @State private var hasTrackedImpression = false
    @State private var qualifiedEpisodeIDs: Set<String> = []
    @State private var completedEpisodeIDs: Set<String> = []
    @State private var episodePrefetchTask: Task<Void, Never>?
    /// 播放链路耗时追踪：open/switch 开始时间，用于定位接口、播放器、首帧慢点。
    @State private var playbackTraceStartedAt = CACurrentMediaTime()
    @State private var playbackTraceReason = "open"

    private enum ChromeMetrics {
        static let horizontalPadding: CGFloat = 16
        static let actionRailWidth: CGFloat = 50
        static let bottomGap: CGFloat = 10
        static let progressIdleHeight: CGFloat = 14
        static let progressScrubbingHeight: CGFloat = 36
        static let topGapBelowSafeArea: CGFloat = 8
        static let topBarHeight: CGFloat = 44
        static let membershipRowHeight: CGFloat = 30
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
                episodePager(in: geo)

                // 全屏手势层（视频上面，UI 下面 — 点击切换 UI 显隐）
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(longPressGesture)
                    .simultaneousGesture(tapPauseGesture(in: geo))
                    .simultaneousGesture(edgeBackGesture(in: geo))

                // UI 叠层（可隐藏）
                if isUIVisible, !showSpeedHUD {
                    topControlBar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, topChromeTopInset(in: geo))
                        .zIndex(60)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 280)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                    seriesChromeOverlay(in: geo)
                }

                if showSpeedHUD {
                    speedProgressOverlay(in: geo)
                        .zIndex(45)
                }

                if isUIVisible, !showSpeedHUD {
                    centerPlaybackButton
                        .zIndex(40)
                }

                if showSpeedHUD {
                    SpeedHUDView()
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.16)
                        .transition(.opacity)
                }

                if showEpisodeList {
                    EpisodePickerSheet(
                        drama: drama,
                        episodes: episodes,
                        currentEpisode: $currentEpisode,
                        unlockedEpisodes: unlockedEpisodes,
                        isPresented: $showEpisodeList,
                        onSelectEpisode: { ep in
                            showEpisodeList = false
                            switchToEpisode(ep)
                        }
                    )
                    .zIndex(200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            }
            .contentShape(Rectangle())
            // 上下切集挂在页面根层，避免底部信息区、右侧按钮或中心按钮吃掉拖拽事件。
            // 具体冲突保护在 episodeDragGesture 内处理。
            .simultaneousGesture(episodeDragGesture)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
        .task(id: drama.id) {
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
            episodePrefetchTask?.cancel()
            Task { await dependencies.watchProgressReporter.finalize(completed: false) }
            playerCoordinator.release(.series(dramaID: drama.id))
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

        // 卡片已携带预览媒资时立即播放点击的短剧，正式剧集/鉴权接口并行补全。
        if let previewItem = drama.toPlayerMediaItem() {
            Logger.player.info("SeriesTrace 使用卡片预览源先播 剧ID=\(drama.id) 集数=\(previewItem.episodeNumber ?? -1)")
            playerCoordinator.claimSeries(
                drama: drama,
                items: [previewItem],
                startIndex: 0,
                handoff: handoff
            )
        }

        await loadEpisodes()
    }

    /// Series 播放完成后优先切换下一集；最后一集回到首帧并等待用户重播。
    private func handlePlaybackFinished() {
        autoHideTask?.cancel()
        Task { await dependencies.watchProgressReporter.finalize(completed: true) }
        if currentEpisode < totalEpisodes {
            switchToEpisode(currentEpisode + 1)
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
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            Logger.viewModel.error("SeriesPlayerView: fetchEpisodes failed: \(error)")
            if playerCoordinator.engine.currentItem?.id != PlayerMediaItem.stableID(
                dramaID: drama.id,
                episodeNumber: currentEpisode
            ) {
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
        _ = await ensurePlayAsset(for: currentEpisode, presentUnlockOnDenied: true)
        guard !Task.isCancelled else { return }
        initializeEpisodePlayer()
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

    private func seriesChromeOverlay(in geo: GeometryProxy) -> some View {
        let horizontalPadding = ChromeMetrics.horizontalPadding
        let actionRailWidth = ChromeMetrics.actionRailWidth
        let actionRailGap = max(18, geo.size.width * 0.055)
        let contentMaxWidth = geo.size.width - horizontalPadding * 2 - actionRailWidth - actionRailGap
        let contentWidth = min(contentMaxWidth, geo.size.width * 0.74)
        let progressWidth = geo.size.width - horizontalPadding * 2
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
                }

                seriesProgressBar(totalWidth: progressWidth, engine: playerCoordinator.engine)
                    .frame(width: progressWidth, height: seriesIsScrubbing ? ChromeMetrics.progressScrubbingHeight : ChromeMetrics.progressIdleHeight)
                    .padding(.top, 2)

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

    /// 避免拖动直接改 currentEpisode 造成状态错位。
    private func requestEpisodeSwitch(_ target: Int) {
        guard target != currentEpisode, target >= 1, target <= totalEpisodes else { return }
        let previous = currentEpisode
        playbackTraceStartedAt = CACurrentMediaTime()
        playbackTraceReason = "switch"
        Logger.player.info("SeriesGesture 接受切集手势 原集=\(previous) 目标集=\(target)")

        // 先切 UI 页码，保证手势像 For You 一样停在目标页；播放源随后异步补齐。
        playerCoordinator.engine.deactivate()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            currentEpisode = target
            dragOffset = 0
        }
        switchToEpisode(target, previousEpisode: previous)
    }

    /// 切集入口：先拉播放源，再重建 playable items，最后 prepare/play。
    /// 禁止在无 source 时用 episodeNumber - 1 做 engine.move。
    private func switchToEpisode(_ episodeNumber: Int, previousEpisode: Int? = nil) {
        guard !isSwitchingEpisode else { return }
        isSwitchingEpisode = true
        Task { @MainActor in
            defer { isSwitchingEpisode = false }
            // 先 finalize 旧 session
            await dependencies.watchProgressReporter.finalize(completed: false)
            guard await ensurePlayAsset(for: episodeNumber, presentUnlockOnDenied: true) else {
                Logger.player.warning("SeriesTrace 切集被阻断 目标集=\(episodeNumber) 原集=\(previousEpisode ?? -1) 原因=播放源缺失或剧集锁定")
                return
            }
            let playable = buildPlayableItems(from: episodes)
            guard let playableIndex = playable.firstIndex(where: { $0.episodeNumber == episodeNumber }) else {
                Logger.player.warning("SeriesTrace 切集失败 目标集=\(episodeNumber) 原因=没有可播放索引")
                return
            }
            if currentEpisode != episodeNumber { currentEpisode = episodeNumber }
            Logger.player.info("SeriesTrace 切集准备播放器 目标集=\(episodeNumber) 播放索引=\(playableIndex)")
            playerCoordinator.engine.prepare(items: playable.map(\.item), index: playableIndex)
            playerCoordinator.engine.play()
            prefetchNextEpisode(after: episodeNumber)
            Logger.player.info("SeriesTrace 切集已调用播放 目标集=\(episodeNumber)")
        }
    }

    /// 提前获取下一集播放合同并验证媒体可用性。只预热一个相邻剧集，
    /// 不创建第二个 AVPlayer，避免额外音频会话和内存占用。
    private func prefetchNextEpisode(after episodeNumber: Int) {
        episodePrefetchTask?.cancel()
        guard let nextEpisode = episodes.first(where: { $0.episodeNumber == episodeNumber + 1 }),
              episodeMediaSources[nextEpisode.id] == nil else { return }

        episodePrefetchTask = Task { @MainActor in
            guard await ensurePlayAsset(for: nextEpisode.episodeNumber, presentUnlockOnDenied: false),
                  !Task.isCancelled,
                  let source = episodeMediaSources[nextEpisode.id],
                  let url = directURL(from: source) else { return }
            let asset = AVURLAsset(url: url)
            _ = try? await asset.load(.isPlayable)
        }
    }

    private func directURL(from source: PlayerMediaSource) -> URL? {
        switch source {
        case .mp4(let url), .mp4WithEmbeddedSubtitles(let url):
            return url
        case .mp4WithExternalSubtitles(let url, _):
            return url
        case .hls(let url):
            return url
        case .hlsWithFallback(_, let fallbackMP4URL):
            return fallbackMP4URL
        }
    }

    /// 播放源按内存缓存、Episode URL、后端播放合同依次解析。
    @MainActor
    private func ensurePlayAsset(for episodeNumber: Int, presentUnlockOnDenied: Bool = false) async -> Bool {
        guard let epIndex = episodes.firstIndex(where: { $0.episodeNumber == episodeNumber }) else { return false }
        let ep = episodes[epIndex]
        let episodeId = ep.id

        if episodeMediaSources[episodeId] != nil {
            Logger.player.info("SeriesTrace 播放源命中内存缓存 集数=\(episodeNumber)")
            return true
        }

        if let url = URL(string: ep.videoURL),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            episodeMediaSources[episodeId] = .mp4(url)
            Logger.player.info("SeriesTrace 播放源使用剧集URL 集数=\(episodeNumber)")
            return true
        }

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
                // 缓存后端 resume time
                if let resume = dto.resumeTime, resume > 0 {
                    episodeResumeTimes[episodeId] = TimeInterval(resume)
                }
                // 播放接口成功代表后端已完成免费/VIP/金币权限判定。
                unlockedEpisodes.insert(episodeNumber)
                Logger.player.info("SeriesTrace 播放源请求成功 集数=\(episodeNumber) 类型=\(dto.sourceType) 耗时=\(Int(elapsed))ms")
                return true
            }
            Logger.player.warning("SeriesTrace 播放源为空 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms")
            return false
        } catch let error as APIError where error.code == "EPISODE_LOCKED" {
            // 解锁流程尚未正式设计，当前版本不展示半成品弹窗；后续由专门任务接入正式解锁页。
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.warning("SeriesTrace 剧集被锁定 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms 解锁UI暂未接入")
            return false
        } catch {
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000
            Logger.player.warning("SeriesTrace 播放源请求失败 集数=\(episodeNumber) 耗时=\(Int(elapsed))ms 错误=\(error.localizedDescription)")
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
                    resumeTime: resume
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

    private var topControlBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 36)
                    .contentShape(Rectangle())
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)

            Text("EP.\(currentEpisode)")
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
        let pageHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
        let yOffset = -CGFloat(currentEpisode - 1) * pageHeight + dragOffset

        return ZStack {
            ForEach(visibleEpisodeIndices(), id: \.self) { ep in
                let isCurrent = ep == currentEpisode
                ShortVideoPlayerView(
                    player: isCurrent ? playerForEpisode(ep) : nil,
                    coverURL: drama.coverURL,
                    engine: playerCoordinator.engine,
                    showsSystemPlaybackButton: false
                )
                .allowsHitTesting(false)
                .frame(width: geo.size.width, height: pageHeight)
                .position(x: geo.size.width / 2, y: CGFloat(ep - 1) * pageHeight + pageHeight / 2 + yOffset)
            }
        }
        .frame(width: geo.size.width, height: pageHeight)
        .clipped()
    }

    /// 只有播放器当前 item 确实属于该集时才挂载 AVPlayer。
    /// 锁集或播放源加载中时目标页只显示封面，避免 EP2 页面继续显示 EP1 画面。
    private func playerForEpisode(_ episodeNumber: Int) -> AVPlayer? {
        guard playerCoordinator.engine.currentItem?.episodeNumber == episodeNumber else {
            return nil
        }
        return playerCoordinator.engine.currentPlayer
    }

    private func visibleEpisodeIndices() -> [Int] {
        guard totalEpisodes > 0 else { return [currentEpisode] }
        let lo = max(1, currentEpisode - 1)
        let hi = min(totalEpisodes, currentEpisode + 1)
        guard lo <= hi else { return [currentEpisode] }
        return Array(lo...hi)
    }

    // MARK: - Gestures

    private var episodeDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard canHandleEpisodeDrag(value) else { return }
                let t = value.translation.height
                if currentEpisode == 1 && t > 0 { dragOffset = t * 0.4 }
                else if currentEpisode == totalEpisodes && t < 0 { dragOffset = t * 0.4 }
                else { dragOffset = t }
            }
            .onEnded { value in
                guard canHandleEpisodeDrag(value) else {
                    Logger.player.info("SeriesGesture 忽略手势 起点X=\(Int(value.startLocation.x)) 横向=\(Int(value.translation.width)) 纵向=\(Int(value.translation.height))")
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { dragOffset = 0 }
                    return
                }
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let oldEpisode = currentEpisode
                var targetEpisode = oldEpisode
                if value.translation.height < -80 || velocity < -300 {
                    targetEpisode = min(oldEpisode + 1, totalEpisodes)
                } else if value.translation.height > 80 || velocity > 300 {
                    targetEpisode = max(oldEpisode - 1, 1)
                }
                Logger.player.info("SeriesGesture 手势结束 原集=\(oldEpisode) 目标集=\(targetEpisode) 纵向=\(Int(value.translation.height)) 速度=\(Int(velocity)) 总集数=\(totalEpisodes)")
                if targetEpisode != oldEpisode {
                    requestEpisodeSwitch(targetEpisode)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { dragOffset = 0 }
                }
            }
    }

    /// Series 全屏切集必须像 For You 一样从页面大部分区域可触发，
    /// 但要避开左边缘返回、进度条拖动、弹层和明显横滑。
    private func canHandleEpisodeDrag(_ value: DragGesture.Value) -> Bool {
        guard !seriesIsScrubbing, !showEpisodeList, activeSheet == nil else { return false }
        guard value.startLocation.x > 24 else { return false }
        guard abs(value.translation.height) > abs(value.translation.width) * 1.2 else { return false }
        return true
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
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
                dismiss()
            }
    }

    private func tapPauseGesture(in geo: GeometryProxy) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
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
