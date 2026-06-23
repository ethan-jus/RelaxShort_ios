import SwiftUI
import AVKit

// MARK: - Series Player View (接入 ShortVideoPlayerEngine)

struct SeriesPlayerView: View {

    let drama: DramaItem
    let startEpisode: Int
    @EnvironmentObject var dependencies: DependencyContainer
    let handoff: PlayerHandoffContext?

    @State private var currentEpisode: Int
    @State private var dragOffset: CGFloat = 0
    @State private var showSpeedHUD = false
    @State private var showEpisodeList = false
    @State private var showUnlockSheet = false
    @State private var unlockTargetEpisode: Int = 0
    @State private var isBookmarked = false
    @State private var episodes: [Episode] = []
    @State private var unlockedEpisodes: Set<Int> = []
    @State private var pendingLockedEpisode: Int?
    @State private var isUIVisible = true
    @State private var autoHideTask: Task<Void, Never>?
    /// Task24: 缓存当前集播放接口返回的 PlayerMediaSource（key = episodeId）
    @State private var episodeMediaSources: [String: PlayerMediaSource] = [:]
    /// Task26 R2: 单一 sheet router，避免多 .sheet 互抢
    @State private var activeSheet: PlayerSheet?
    @State private var isSpeeding = false
    /// Task26 R2: 切集 loading 状态
    @State private var isSwitchingEpisode = false

    /// Task26 R2: 单一 sheet router 枚举
    private enum PlayerSheet: Identifiable {
        case share, speed, quality, more
        var id: String {
            switch self {
            case .share: "share"
            case .speed: "speed"
            case .quality: "quality"
            case .more: "more"
            }
        }
    }

    @EnvironmentObject var playerCoordinator: PlayerCoordinator
    @Environment(\.dismiss) private var dismiss

    /// 总集数：从 episodes.count 派生，初始化时用 drama.episodeCount 兜底（可能为 0）
    private var totalEpisodes: Int { max(episodes.count, drama.episodeCount) }

    init(drama: DramaItem, startEpisode: Int? = nil, handoff: PlayerHandoffContext? = nil) {
        self.drama = drama
        self.startEpisode = startEpisode ?? max(1, drama.currentEpisode)
        self.handoff = handoff
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
                    .gesture(episodeDragGesture)
                    .simultaneousGesture(longPressGesture)
                    .simultaneousGesture(tapPauseGesture)

                // UI 叠层（可隐藏）
                if isUIVisible {
                    // Task26: 顶部控制栏
                    topControlBar(in: geo)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, geo.safeAreaInsets.top + 8)
                        .zIndex(60)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 280)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                    bottomBar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, DT.Space.pageH)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 10)

                    seriesBottomOverlay(in: geo)

                    // Task26: 底部会员/下载条
                    membershipDownloadStrip(in: geo)

                    RightActionBar(
                        isBookmarked: $isBookmarked,
                        viewCount: drama.formattedViewCount,
                        onBookmark: { isBookmarked.toggle(); resetAutoHide() },
                        onShare: { activeSheet = .share },
                        onEpisodes: { showEpisodeList = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, DT.Space.pageH)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 10)
                }

                // 中心暂停按钮：仅在播放中且 UI 可见时显示（暂停态由 ShortVideoPlayerView 自带按钮处理）
                if isUIVisible, playerCoordinator.engine.state == .playing {
                    Button {
                        playerCoordinator.engine.pause(reason: .user)
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(Color.black.opacity(0.42)))
                    }
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
                        onUnlock: { ep in
                            pendingLockedEpisode = ep
                            unlockTargetEpisode = ep
                            showEpisodeList = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showUnlockSheet = true
                            }
                        },
                        onSelectEpisode: { ep in
                            showEpisodeList = false
                            switchToEpisode(ep)
                        }
                    )
                    .zIndex(200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showUnlockSheet {
                    UnlockEpisodeSheet(
                        episodeNumber: unlockTargetEpisode,
                        coinPrice: 100,
                        isPresented: $showUnlockSheet,
                        onUnlockWithCoins: {
                            unlockedEpisodes.insert(unlockTargetEpisode)
                            showUnlockSheet = false
                            playUnlockedPendingEpisode()
                        },
                        onWatchAd: {
                            unlockedEpisodes.insert(unlockTargetEpisode)
                            showUnlockSheet = false
                            playUnlockedPendingEpisode()
                        }
                    )
                    .zIndex(300)
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .navigationTitle("\(drama.title) \(L10n.playerEpisodeNumber(currentEpisode))")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .share:
                ShareSheet(dramaTitle: drama.title)
                    .presentationDetents([.medium])
            case .speed:
                PlayerSpeedSheet(engine: playerCoordinator.engine)
                    .presentationDetents([.fraction(0.45)])
                    .presentationDragIndicator(.hidden)
            case .quality:
                PlayerQualitySheet(
                    qualities: qualityOptions(),
                    currentQuality: "720p"
                )
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.hidden)
            case .more:
                PlayerMoreSheet(
                    onQuality: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            activeSheet = .quality
                        }
                    },
                    onSubtitles: { },
                    onReport: { }
                )
                .presentationDetents([.fraction(0.3)])
                .presentationDragIndicator(.hidden)
            }
        }
        .task { await loadEpisodes() }
        .onChange(of: currentEpisode) { oldValue, newValue in
            guard oldValue != newValue else { return }
            requestEpisodeSwitch(newValue)
        }
        .onChange(of: showUnlockSheet) { _, isShowing in
            guard !isShowing, let pending = pendingLockedEpisode, isEpisodeLocked(pending) else { return }
            pendingLockedEpisode = nil
        }
        .onChange(of: playerCoordinator.engine.state) { _, state in
            if state == .playing { resetAutoHide() }
            else if state == .pausedByUser { autoHideTask?.cancel() }
        }
        .onDisappear {
            autoHideTask?.cancel()
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

    private func loadEpisodes() async {
        let repo = dependencies.detailRepository
        do {
            episodes = try await repo.fetchEpisodes(dramaId: drama.id)
        } catch {
            Logger.viewModel.error("SeriesPlayerView: fetchEpisodes failed: \(error)")
            episodes = (try? await MockDetailRepository().fetchEpisodes(dramaId: drama.id)) ?? []
        }
        // Task13: 真实模式下为当前集调用 episodePlay 获取播放URL
        await fetchCurrentEpisodePlaybackURL()
        initializeEpisodePlayer()
    }

    /// 通过 RealDetailRepository 获取当前集播放地址和 PlayerMediaSource。
    /// 更新 Episode.videoURL 兼容字段，同时缓存 source 供 playerItems 使用。
    /// 失败时保留已有 URL（来自 episodes 响应或 Mock）。
    private func fetchCurrentEpisodePlaybackURL() async {
        guard let repo = dependencies.detailRepository as? RealDetailRepository else { return }
        guard let epIndex = episodes.firstIndex(where: { $0.episodeNumber == currentEpisode }) else { return }
        let episodeId = episodes[epIndex].id
        do {
            let dto = try await repo.fetchPlayAsset(episodeId: episodeId)
            if let url = dto.preferredPlaybackURL {
                episodes[epIndex].videoURL = url
            }
            if let source = dto.toPlayerMediaSource() {
                episodeMediaSources[episodeId] = source
                Logger.viewModel.info("SeriesPlayerView: fetched source type=\(dto.sourceType) for EP \(currentEpisode)")
            }
        } catch {
            Logger.viewModel.warning("SeriesPlayerView: episodePlay failed, using fallback videoURL: \(error.localizedDescription)")
        }
    }

    /// Task26 R2: 初始化时使用 switchToEpisode 安全切换（确保已拉 play asset）
    private func initializeEpisodePlayer() {
        guard !isEpisodeLocked(currentEpisode) else {
            pendingLockedEpisode = currentEpisode
            unlockTargetEpisode = currentEpisode
            showUnlockSheet = true
            playerCoordinator.engine.pause(reason: .system)
            return
        }
        let playable = buildPlayableItems(from: episodes)
        guard !playable.isEmpty else { return }
        let startIndex = playable.firstIndex(where: { $0.episodeNumber == currentEpisode }) ?? 0
        playerCoordinator.claimSeries(drama: drama, items: playable.map(\.item), startIndex: startIndex, handoff: handoff)
    }

    // MARK: - 底部信息叠层

    private func seriesBottomOverlay(in geo: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = 14
        let actionRailWidth: CGFloat = 42
        let actionRailGap: CGFloat = 10
        let contentWidth = geo.size.width - horizontalPadding * 2 - actionRailWidth - actionRailGap
        let engine = playerCoordinator.engine

        return VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                // 标题
                Text(drama.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                // 标签（根据 DramaItem 状态动态展示）
                let badgeTags = L10n.dramaBadgeTags(for: drama)
                if !badgeTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(badgeTags.enumerated()), id: \.offset) { _, tag in
                            DramaBadgeTagView(tag: tag, drama: drama)
                        }
                    }
                }
                // 简介
                (Text("Trailer | ").font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                + Text(drama.synopsis).font(.system(size: 13)).foregroundColor(.white.opacity(0.65)))
                .lineLimit(2)
                // 进度条
                seriesProgressBar(totalWidth: contentWidth, engine: engine)
                    .frame(height: 32)
            }
            .frame(width: contentWidth, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 66)
        }
    }

    // MARK: - 进度条（带拖动和点击）
    @State private var seriesScrubFraction: CGFloat = 0
    @State private var seriesIsScrubbing = false
    @State private var seriesWasPlayingBeforeScrub = false

    private func seriesProgressBar(totalWidth: CGFloat, engine: ShortVideoPlayerEngine) -> some View {
        let fraction = engine.progress.duration > 0
            ? (seriesIsScrubbing ? Double(seriesScrubFraction) : engine.progress.currentTime / engine.progress.duration) : 0
        let clampedProgress = max(0, min(1, CGFloat(fraction)))
        let barWidth = totalWidth

        return ZStack(alignment: .leading) {
            // 触摸区域
            Rectangle().fill(Color.white.opacity(0.001)).frame(height: 32)
            // 轨道
            Capsule().fill(Color.white.opacity(0.25)).frame(height: 2)
            // 进度
            Capsule().fill(DT.logoRed)
                .frame(width: max(2.5, barWidth * clampedProgress), height: 2.5)
            // 圆头
            Circle().fill(.white)
                .frame(width: seriesIsScrubbing ? 14 : 4, height: seriesIsScrubbing ? 14 : 4)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                .offset(x: max(0, min(barWidth, barWidth * clampedProgress)) - (seriesIsScrubbing ? 7 : 2))
        }
        .frame(width: barWidth, height: 32, alignment: .center)
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
                    engine.seek(to: Double(max(0, min(1, seriesScrubFraction))))
                    if seriesWasPlayingBeforeScrub { engine.play() }
                    seriesIsScrubbing = false; seriesScrubFraction = 0
                }
        )
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard engine.progress.duration > 0 else { return }
                    engine.seek(to: Double(max(0, min(1, value.location.x / barWidth))))
                }
        )
    }

    // MARK: - Task26 Quality Helpers（fallback UI，无多码率数据）

    private func qualityOptions() -> [PlayerQualitySheet.QualityOption] {
        [
            .init(id: "auto", label: "Auto", isVIP: false, isSelected: true),
            .init(id: "720p", label: "720p", isVIP: false, isSelected: false),
            .init(id: "1080p", label: "1080p", isVIP: true, isSelected: false),
            .init(id: "540p", label: "540p", isVIP: false, isSelected: false)
        ]
    }

    // MARK: - Episode Switching

    /// Task26 R3: 安全切集请求入口。由 drag/onChange/EpisodePickerSheet 调用。
    /// 避免拖动直接改 currentEpisode 造成状态错位。
    private func requestEpisodeSwitch(_ target: Int) {
        guard target != currentEpisode, target >= 1, target <= totalEpisodes else { return }
        switchToEpisode(target)
    }

    /// Task26 R2 P0: 切集入口 — 先拉真实播放源，再重建 playable items，最后 prepare/play。
    /// 禁止在无 source 时用 episodeNumber - 1 做 engine.move。
    /// Task26 R3: 添加 currentEpisode 未变化 guard，避免 onChange 循环触发。
    private func switchToEpisode(_ episodeNumber: Int) {
        guard !isSwitchingEpisode else { return }
        guard episodeNumber != currentEpisode else { return } // R3: 已在此集则不重复切
        // 锁定集不能播放
        guard !isEpisodeLocked(episodeNumber) else {
            pendingLockedEpisode = episodeNumber
            unlockTargetEpisode = episodeNumber
            showUnlockSheet = true
            return
        }
        isSwitchingEpisode = true
        Task { @MainActor in
            defer { isSwitchingEpisode = false }
            guard await ensurePlayAsset(for: episodeNumber) else {
                Logger.viewModel.warning("SeriesPlayerView: cannot switch EP\(episodeNumber), missing play asset")
                return
            }
            let playable = buildPlayableItems(from: episodes)
            guard let playableIndex = playable.firstIndex(where: { $0.episodeNumber == episodeNumber }) else {
                Logger.viewModel.warning("SeriesPlayerView: no playable index for EP\(episodeNumber)")
                return
            }
            pendingLockedEpisode = nil
            currentEpisode = episodeNumber
            playerCoordinator.engine.prepare(items: playable.map(\.item), index: playableIndex)
            playerCoordinator.engine.play()
            Logger.viewModel.info("SeriesPlayerView: switched to EP\(episodeNumber) playableIndex=\(playableIndex)")
        }
    }

    /// Task26 R4: 三层回退支持 Real / Mock 两种模式。
    /// ① 已有 cached source → true
    /// ② episode.videoURL 有效（Mock 模式首次加载已写入）→ 缓存为 .mp4 source → true
    /// ③ RealDetailRepository.fetchPlayAsset（Real 模式）→ true/false
    @MainActor
    private func ensurePlayAsset(for episodeNumber: Int) async -> Bool {
        guard let epIndex = episodes.firstIndex(where: { $0.episodeNumber == episodeNumber }) else { return false }
        let ep = episodes[epIndex]
        let episodeId = ep.id

        // ① 已有缓存直接返回
        if episodeMediaSources[episodeId] != nil { return true }

        // ② Mock 模式：已有有效 videoURL 即可
        if let url = URL(string: ep.videoURL),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            episodeMediaSources[episodeId] = .mp4(url)
            return true
        }

        // ③ Real 模式：通过后端接口拉取
        guard let repo = dependencies.detailRepository as? RealDetailRepository else {
            Logger.viewModel.warning("SeriesPlayerView: no source for EP\(episodeNumber) (no RealDetailRepository, no videoURL)")
            return false
        }
        do {
            let dto = try await repo.fetchPlayAsset(episodeId: episodeId)
            if let url = dto.preferredPlaybackURL {
                episodes[epIndex].videoURL = url
            }
            if let source = dto.toPlayerMediaSource() {
                episodeMediaSources[episodeId] = source
                Logger.viewModel.info("SeriesPlayerView: fetched play asset EP\(episodeNumber) type=\(dto.sourceType)")
                return true
            }
            return false
        } catch {
            Logger.viewModel.warning("SeriesPlayerView: play asset failed EP\(episodeNumber): \(error.localizedDescription)")
            return false
        }
    }

    /// 从 sourceForEpisode 构建 EpisodePlayableItem 列表（保证索引安全）
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
                print("[SeriesPlayer] skip EP\(ep.episodeNumber) reason=no-source")
                return nil
            }
            return EpisodePlayableItem(
                id: ep.id,
                episodeNumber: ep.episodeNumber,
                item: PlayerMediaItem(
                    id: PlayerMediaItem.stableID(dramaID: drama.id, episodeNumber: ep.episodeNumber),
                    title: drama.title,
                    episodeNumber: ep.episodeNumber,
                    coverURL: drama.coverURL,
                    source: source,
                    resumeTime: nil
                )
            )
        }
    }

    private func playUnlockedPendingEpisode() {
        guard let pending = pendingLockedEpisode else { return }
        switchToEpisode(pending)
    }

    // MARK: - Task26 顶部控制栏

    private func topControlBar(in geo: GeometryProxy) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                    Text("EP.\(currentEpisode)")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                activeSheet = .speed
            } label: {
                Label("Speed", systemImage: "speedometer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)

            Button {
                activeSheet = .more
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Task26 底部会员/下载条

    private func membershipDownloadStrip(in geo: GeometryProxy) -> some View {
        HStack {
            Button {
                print("[SeriesPlayer] Join membership tapped (UI-only)")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill").font(.system(size: 12))
                    Text("Join membership").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DB.gold)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(DB.gold.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                print("[SeriesPlayer] Download tapped (UI-only)")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 14))
                    Text("Download").font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.bottom, geo.safeAreaInsets.bottom + 54)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Episode Pager

    private func episodePager(in geo: GeometryProxy) -> some View {
        let pageHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
        let yOffset = -CGFloat(currentEpisode - 1) * pageHeight + dragOffset

        return ZStack {
            ForEach(visibleEpisodeIndices(), id: \.self) { ep in
                let isCurrent = ep == currentEpisode
                ShortVideoPlayerView(
                    player: isCurrent ? playerCoordinator.engine.currentPlayer : nil,
                    coverURL: drama.coverURL,
                    engine: playerCoordinator.engine
                )
                .allowsHitTesting(false)
                .frame(width: geo.size.width, height: pageHeight)
                .position(x: geo.size.width / 2, y: CGFloat(ep - 1) * pageHeight + pageHeight / 2 + yOffset)
            }
        }
        .frame(width: geo.size.width, height: pageHeight)
        .clipped()
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
                let t = value.translation.height
                if currentEpisode == 1 && t > 0 { dragOffset = t * 0.4 }
                else if currentEpisode == totalEpisodes && t < 0 { dragOffset = t * 0.4 }
                else { dragOffset = t }
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let oldEpisode = currentEpisode
                var targetEpisode = oldEpisode
                if value.translation.height < -80 || velocity < -300 {
                    targetEpisode = min(oldEpisode + 1, totalEpisodes)
                } else if value.translation.height > 80 || velocity > 300 {
                    targetEpisode = max(oldEpisode - 1, 1)
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { dragOffset = 0 }
                if targetEpisode != oldEpisode {
                    requestEpisodeSwitch(targetEpisode)
                }
            }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, _):
                    if !showSpeedHUD, playerCoordinator.engine.progress.duration > 0 {
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
                playerCoordinator.engine.setRate(1.0)
                withAnimation(.spring(response: 0.3)) { showSpeedHUD = false }
            }
    }

    private var tapPauseGesture: some Gesture {
        TapGesture()
            .onEnded {
                // 暂停态点击屏幕直接恢复播放，避免透明手势层挡住播放器内置播放按钮。
                if playerCoordinator.engine.state == .pausedByUser {
                    playerCoordinator.engine.play()
                    resetAutoHide()
                    return
                }
                // 播放态点击屏幕 → 切换 UI 显隐。
                withAnimation(.easeOut(duration: 0.25)) {
                    isUIVisible.toggle()
                }
                if isUIVisible { resetAutoHide() }
            }
    }

    // MARK: - Episode Lock Check

    private func isEpisodeLocked(_ ep: Int) -> Bool {
        if unlockedEpisodes.contains(ep) { return false }
        let freeRange = drama.freeEpisodeRange ?? 1...3
        return !freeRange.contains(ep)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if isEpisodeLocked(currentEpisode) {
                Button {
                    unlockTargetEpisode = currentEpisode
                    showUnlockSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 12))
                        Text("Unlock EP \(currentEpisode)")
                            .font(DT.Font.body(15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).frame(height: 40)
                    .background(DB.pink)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl))
                }
            }
        }
    }
}

// MARK: - Task26 R2 Episode Picker Sheet（6 列 + range tabs）

private struct EpisodePickerSheet: View {
    let drama: DramaItem
    let episodes: [Episode]
    @Binding var currentEpisode: Int
    let unlockedEpisodes: Set<Int>
    @Binding var isPresented: Bool
    var onUnlock: (Int) -> Void
    var onSelectEpisode: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
    private let rangeSize = 30
    @State private var selectedRange = 0

    private var ranges: [ClosedRange<Int>] {
        let total = max(episodes.count, drama.episodeCount)
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
                    CoverImageView(url: drama.coverURL, aspectRatio: 2.0/3.0, cornerRadius: 6, width: 72, height: 96)
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
            if isLocked { onUnlock(ep) } else { onSelectEpisode(ep); dismiss() }
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

// MARK: - Unlock Episode Sheet (unchanged)

private struct UnlockEpisodeSheet: View {
    let episodeNumber: Int; let coinPrice: Int; @Binding var isPresented: Bool; var onUnlockWithCoins: () -> Void; var onWatchAd: () -> Void
    var body: some View {
        ZStack { Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { dismiss() }
            VStack(spacing: 0) {
                Image(systemName: "lock.shield.fill").font(.system(size: 40)).foregroundColor(DB.gold).padding(.top, 28).padding(.bottom, 16)
                Text("Unlock Episode \(episodeNumber)").font(.system(size: 20, weight: .bold)).foregroundColor(.white).padding(.bottom, 8)
                Text("This episode requires coins to unlock. Choose your method below.").font(.system(size: 13)).foregroundColor(DB.mutedText).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 24)
                Button { onUnlockWithCoins(); dismiss() } label: { HStack(spacing: 8) { Image(systemName: "bitcoinsign.circle.fill"); Text("Unlock with \(coinPrice) Coins").font(.system(size: 15, weight: .semibold)) }.foregroundColor(.black).frame(maxWidth: .infinity).frame(height: 48).background(DB.gold).cornerRadius(DB.ctaRadius) }.padding(.horizontal, 24).padding(.bottom, 10)
                Button { onWatchAd(); dismiss() } label: { HStack(spacing: 8) { Image(systemName: "play.rectangle.fill"); Text("Watch Ad to Unlock").font(.system(size: 15, weight: .semibold)) }.foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 48).background(RoundedRectangle(cornerRadius: DB.ctaRadius).stroke(DB.pink, lineWidth: 1.5)) }.padding(.horizontal, 24).padding(.bottom, 24)
            }.frame(width: 300).background(DB.panelElevated).clipShape(RoundedRectangle(cornerRadius: DB.sheetCornerRadius))
        }
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
