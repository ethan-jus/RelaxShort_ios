import SwiftUI

// MARK: - 沉浸式短剧流

/// 推荐页 — 沉浸式短剧信息流，对标短剧应用
///
/// **布局**：
/// - 全屏视频区，顶部无黑边，延伸至状态栏
/// - 右上角搜索按钮，毛玻璃圆形背景
/// - 底部渐变遮罩、标题、标签、简介和转化按钮
/// - 右侧收藏和分享操作按钮
/// - 底部视频播放进度条（紧贴底部，拖动时显示时间预览+拇指图）
///
/// 播放状态由外层标签页持有的推荐会话管理，本视图重建时也不会丢失状态。
struct RecommendView: View {

    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject var playerCoordinator: PlayerCoordinator
    @ObservedObject private var viewModel: RecommendViewModel
    @ObservedObject private var session: RecommendSession
    let isVisible: Bool

    @State private var dragOffset: CGFloat = 0
    @State private var isExpanded = false
    @State private var showShare = false
    @State private var isSpeeding = false
    @State private var showSpeedHUD = false
    @State private var isBookmarked = false
    @State private var showBookmarkToast = false
    @State private var isScrubbing = false
    @State private var scrubFraction: CGFloat = 0
    @State private var showAbout = false
    @State private var showNotificationPrompt = false
    @State private var hasShownNotification = false
    @State private var wasPlayingBeforeScrub = false
    @State private var isDraggingPage = false
    @State private var scrubThumbnail: UIImage?

    init(viewModel: RecommendViewModel? = nil, session: RecommendSession, isVisible: Bool = true) {
        self.viewModel = viewModel ?? RecommendViewModel(repository: MockHomeRepository())
        self.session = session
        self.isVisible = isVisible
    }

    // MARK: - 路由遮挡状态

    private var routeBlocksPlayback: Bool {
        appStore.isShowingSearch || appStore.isShowingMembership
    }

    private var isPlaybackVisible: Bool {
        isVisible && !routeBlocksPlayback
    }

    // MARK: - 主视图

    var body: some View {
        contentView
            .ignoresSafeArea()
            .task { await loadAndInit() }
            .sheet(isPresented: $showShare) {
                ShareSheet(dramaTitle: currentDrama?.title ?? "")
                    .presentationDetents([.medium])
            }
            .onChange(of: session.currentIndex) { oldValue, newValue in
                // 单视频切换状态重置
                isExpanded = false
                isScrubbing = false; scrubFraction = 0
                isSpeeding = false; showSpeedHUD = false
                // engine handles reset internally
                session.handleTransition(from: oldValue, to: newValue, dramas: viewModel.dramas)
                if isPlaybackVisible { session.engine.play() }
            }
            .onChange(of: isPlaybackVisible) { _, vis in
                if vis {
                    initializePlaybackIfNeeded()
                    session.engine.playFromSystemResume()
                } else {
                    session.engine.pause(reason: .system)
                }
            }
            .onChange(of: viewModel.dramas.count) { _, count in
                guard count > 0 else { return }
                if isPlaybackVisible {
                    initializePlaybackIfNeeded()
                }
            }
            .onChange(of: showAbout) { _, isShowing in
                withAnimation(.easeOut(duration: 0.18)) {
                    appStore.isBottomTabBarHidden = isShowing
                }
            }
            .onDisappear {
                appStore.isBottomTabBarHidden = false
            }
            .onAppear { setupAutoPlay() }
            .modifier(TabLifecycleModifier(appStore: appStore, session: session, viewModel: viewModel))
    }

    // MARK: - 内容视图

    private var contentView: some View {
        GeometryReader { geo in
            ZStack {
                if viewModel.dramas.isEmpty {
                    emptyState(in: geo)
                } else {
                    feedOverlayContent(in: geo)
                }

                // 固定浮层
                let searchTopPadding = geo.safeAreaInsets.top + 86
                searchBarButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 14)
                    .padding(.top, searchTopPadding)

                if session.engine.state == .pausedByUser, session.engine.isReadyForDisplay {
                    Button { handleVideoTap() } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(Color.black.opacity(0.42)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(40)
                }

                if showSpeedHUD {
                    SpeedHUDView()
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.16)
                        .transition(.opacity)
                }

                if showBookmarkToast {
                    CollectToastView(
                        message: isBookmarked ? "Added to 'My List'" : "Removed from 'My List'",
                        systemImage: isBookmarked ? "bookmark.fill" : "bookmark.slash.fill"
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.65)
                    .zIndex(100)
                    .transition(.opacity)
                }

                if showAbout, let drama = currentDrama {
                    DramaAboutSheet(
                        drama: drama,
                        relatedDramas: relatedDramas(for: drama),
                        isPresented: $showAbout,
                        onWatchFullSeries: {
                            showAbout = false
                            let handoff = session.engine.makeHandoffContext(dramaID: drama.id, episodeNumber: max(1, drama.currentEpisode))
                            appStore.navigationTarget = SeriesPlayerNav(
                                drama: drama,
                                startEpisode: max(1, drama.currentEpisode),
                                handoff: handoff
                            )
                        }
                    )
                    .zIndex(200)
                }
                if showNotificationPrompt {
                    NotificationPromptView(isPresented: $showNotificationPrompt).zIndex(300)
                }
            }
        }
    }

    @ViewBuilder
    private func feedOverlayContent(in geo: GeometryProxy) -> some View {
        let dramas = viewModel.dramas
        let pageHeight = geo.size.height
        let yOffset = -CGFloat(session.currentIndex) * pageHeight + dragOffset

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(verticalDrag(count: dramas.count))
                .simultaneousGesture(longPressGesture)
                .simultaneousGesture(tapGesture)
                .zIndex(-1)

            ForEach(Array(visibleIndices(for: session.currentIndex, count: dramas.count)), id: \.self) { idx in
                let isCurrent = idx == session.currentIndex
                ZStack {
                    ShortVideoPlayerView(
                        player: isCurrent ? session.engine.currentPlayer : nil,
                        coverURL: dramas[idx].coverURL,
                        engine: session.engine
                    )
                        .allowsHitTesting(false)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.1), .black.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    // 每页独立底部浮层
                    if !isSpeeding, !showAbout, !showNotificationPrompt {
                        pageBottomOverlay(drama: dramas[idx], isCurrent: isCurrent, geo: geo)
                    }
                }
                .frame(width: geo.size.width, height: pageHeight)
                .position(x: geo.size.width / 2, y: CGFloat(idx) * pageHeight + pageHeight / 2 + yOffset)
            }
        }
        .frame(width: geo.size.width, height: pageHeight)
        .clipped()
    }

    private func pageBottomOverlay(drama: DramaItem, isCurrent: Bool, geo: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = 14
        let actionRailWidth: CGFloat = 42
        let actionRailGap: CGFloat = 10
        let tabBarAvoidance: CGFloat = 86
        let contentWidth = geo.size.width - horizontalPadding * 2 - actionRailWidth - actionRailGap

        return VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 3) {
                if !isScrubbing {
                    HStack(alignment: .bottom, spacing: actionRailGap) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                withAnimation(.easeOut(duration: 0.25)) { showAbout = true }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(drama.title)
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.white).lineLimit(1)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .buttonStyle(.plain)

                            // 标签
                            HStack(spacing: 6) {
                                feedTag("Members Only", bg: DB.gold.opacity(0.25), fg: DB.gold)
                                feedTag("Exclusive", bg: Color.white.opacity(0.12), fg: .white.opacity(0.85))
                                feedTag(L10n.categoryDisplayName(drama.category), bg: Color.white.opacity(0.12), fg: .white.opacity(0.85))
                            }

                            // 简介展开和收起
                            synopsisView(drama.synopsis)
                                .lineSpacing(3)
                                .contentShape(Rectangle())
                                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() } }
                        }
                        .frame(width: contentWidth, alignment: .leading)

                        // 右侧操作栏
                        RightActionBar(
                            isBookmarked: $isBookmarked,
                            viewCount: drama.formattedViewCount,
                            onBookmark: {
                                withAnimation(.spring(response: 0.3)) {
                                    isBookmarked.toggle(); showBookmarkToast = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                    withAnimation(.easeOut(duration: 0.3)) { showBookmarkToast = false }
                                }
                            },
                            onShare: { showShare = true }
                        )
                        .frame(width: actionRailWidth)
                    }

                    // 使用按钮显式跳转，避免手势层抢占点击
                    Button {
                        let handoff = session.engine.makeHandoffContext(dramaID: drama.id, episodeNumber: max(1, drama.currentEpisode))
                        appStore.navigationTarget = SeriesPlayerNav(
                            drama: drama,
                            startEpisode: max(1, drama.currentEpisode),
                            handoff: handoff
                        )
                    } label: {
                        Text("Watch Full Series")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: contentWidth, height: 38)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.22)))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }

                if isCurrent {
                    progressBar(totalWidth: geo.size.width - horizontalPadding * 2)
                        .frame(width: geo.size.width - horizontalPadding * 2)
                        .zIndex(30)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: geo.size.width - horizontalPadding * 2, height: 3)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, tabBarAvoidance)
        }
        .zIndex(10)
    }

    private func synopsisView(_ text: String) -> some View {
        Group {
            if isExpanded {
                (Text("Trailer | ").font(.system(size: 13)).foregroundColor(.white.opacity(0.9))
                + Text(text).font(.system(size: 13)).foregroundColor(.white.opacity(0.82)))
            } else {
                (Text("Trailer | ").font(.system(size: 13)).foregroundColor(.white.opacity(0.9))
                + Text(truncatedSynopsis(text)).font(.system(size: 13)).foregroundColor(.white.opacity(0.82))
                + Text("... more").font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.96)))
            }
        }
        .lineLimit(isExpanded ? nil : 2)
    }

    private func truncatedSynopsis(_ text: String) -> String {
        if text.count > 80 { String(text.prefix(80)) }
        else { text }
    }

    private func feedTag(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func loadAndInit() async {
        // 连线：session.engine 指向共享 coordinator.engine
        session.bind(to: playerCoordinator)
        await viewModel.loadData()
        if isPlaybackVisible {
            initializePlaybackIfNeeded()
            if !hasShownNotification {
                hasShownNotification = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.3)) { showNotificationPrompt = true }
                }
            }
        }
    }

    private func initializePlaybackIfNeeded() {
        guard !session.hasInitializedPool, !viewModel.dramas.isEmpty else { return }
        session.initializePool(dramas: viewModel.dramas)
        session.engine.play()
    }

    // MARK: - 计算属性

    private var currentDrama: DramaItem? {
        guard viewModel.dramas.indices.contains(session.currentIndex) else { return nil }
        return viewModel.dramas[session.currentIndex]
    }

    private func relatedDramas(for drama: DramaItem) -> [DramaItem] {
        viewModel.dramas
            .filter { $0.id != drama.id }
            .prefix(12)
            .map { $0 }
    }

    // MARK: - 自动播放配置

    private func setupAutoPlay() {
        session.bind(to: playerCoordinator)
        session.engine.onPlaybackFinished = { [weak engine = session.engine] in
            engine?.pause(reason: .system)
            engine?.seek(to: 0)
            // 推荐页第一版：播放结束不自动跳转到全屏
        }
    }

    // MARK: - 搜索按钮

    private var searchBarButton: some View {
        Button {
            NotificationCenter.default.post(name: .showSearch, object: nil)
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 空状态

    private func emptyState(in geo: GeometryProxy) -> some View {
        VStack(spacing: DT.Space.lg) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(DT.Font.emptyIcon)
                .foregroundColor(DT.Color.textTertiary)
            Text(L10n.noRecommendations)
                .font(DT.Font.bodyDefault)
                .foregroundColor(DT.Color.textSecondary)
            Text(L10n.pullToRefresh)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textTertiary)
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    // 旧分页器已移除，统一使用当前信息流浮层

    private func visibleIndices(for current: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return Array(max(0, current - 1)...min(count - 1, current + 1))
    }

    // MARK: - 拖拽手势

    private func verticalDrag(count: Int) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                isDraggingPage = true
                let t = value.translation.height
                if session.currentIndex == 0 && t > 0 { dragOffset = t * 0.4 }
                else if session.currentIndex == count - 1 && t < 0 { dragOffset = t * 0.4 }
                else { dragOffset = t }
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if value.translation.height < -80 || velocity < -300 {
                        session.currentIndex = min(session.currentIndex + 1, count - 1)
                    } else if value.translation.height > 80 || velocity > 300 {
                        session.currentIndex = max(session.currentIndex - 1, 0)
                    }
                    dragOffset = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isDraggingPage = false }
            }
    }

    // MARK: - 点击手势

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                handleVideoTap()
            }
    }

    private func handleVideoTap() {
        let e = session.engine
        if e.state == .playing {
            e.pause(reason: .user)
        } else if e.state == .pausedByUser {
            e.play()
        }
    }

    // MARK: - 长按二倍速

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard !isScrubbing, !isDraggingPage else { return }
                switch value {
                case .second(true, _):
                    if !isSpeeding {
                        isSpeeding = true
                        if session.engine.state == .pausedByUser {
                            session.engine.play()
                        }
                        session.engine.setRate(2.0)
                        withAnimation(.spring(response: 0.3)) { showSpeedHUD = true }
                    }
                default: break
                }
            }
            .onEnded { _ in
                isSpeeding = false
                session.engine.setRate(1.0)
                withAnimation(.spring(response: 0.3)) { showSpeedHUD = false }
            }
    }

    // MARK: - 进度条

    private func progressBar(totalWidth: CGFloat) -> some View {
        let barWidth = totalWidth
        let fraction = session.engine.progress.duration > 0
            ? (isScrubbing ? Double(scrubFraction) : session.engine.progress.currentTime / session.engine.progress.duration)
            : 0
        let buffered = session.engine.progress.bufferProgress
        let effectiveHeight: CGFloat = isScrubbing ? 8 : 3
        let clampedProgress = max(0, min(1, CGFloat(fraction)))
        let scrubSeconds = Double(clampedProgress) * session.engine.progress.duration
        let showSeekPreview = isScrubbing

        return VStack(spacing: 0) {
            if showSeekPreview {
                VStack(spacing: 8) {
                    // 缩略图预览
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.6))
                        .frame(width: 112, height: 160)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                            )
                        if let thumbnail = scrubThumbnail {
                            Image(uiImage: thumbnail)
                                .resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 112, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // 时间文本
                    Text("\(formatTime(scrubSeconds)) / \(formatTime(session.engine.progress.duration))")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
                .transition(.opacity)
            }

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(height: isScrubbing ? 36 : 32)
                Capsule().fill(Color.white.opacity(0.25)).frame(height: effectiveHeight)
                Capsule().fill(Color.white.opacity(0.18))
                    .frame(width: max(0, barWidth * CGFloat(buffered)), height: effectiveHeight)
                Capsule().fill(DT.logoRed)
                    .frame(width: max(effectiveHeight, barWidth * clampedProgress), height: effectiveHeight)
                if isScrubbing {
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .offset(x: max(0, min(barWidth, barWidth * clampedProgress)) - 7)
                }
            }
            .frame(width: barWidth, height: isScrubbing ? 36 : 32, alignment: .center)
            .contentShape(Rectangle())
            .highPriorityGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard !isScrubbing, session.engine.progress.duration > 0 else { return }
                        let clamped = max(0, min(1, value.location.x / barWidth))
                        session.engine.seek(to: Double(clamped))
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.28)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        guard session.engine.progress.duration > 0 else { return }
                        switch value {
                        case .second(true, let drag?):
                            if !isScrubbing {
                                wasPlayingBeforeScrub = session.engine.state == .playing
                                if isSpeeding {
                                    isSpeeding = false
                                    session.engine.setRate(1.0)
                                    showSpeedHUD = false
                                }
                            }
                            isScrubbing = true
                            let x = drag.location.x
                            scrubFraction = max(0, min(1, x / barWidth))
                            session.engine.generateThumbnail(at: scrubFraction) { img in scrubThumbnail = img }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        if case .second(true, let drag?) = value {
                            let x = drag.location.x
                            let clamped = max(0, min(1, x / barWidth))
                            session.engine.seek(to: Double(clamped))
                            if wasPlayingBeforeScrub { session.engine.playFromSystemResume() }
                        }
                        withAnimation(.easeOut(duration: 0.12)) {
                            isScrubbing = false
                        }
                        scrubFraction = 0
                        scrubThumbnail = nil
                        wasPlayingBeforeScrub = false
                    }
            )
        }
    }

    // MARK: - 时间格式

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

// MARK: - 标签页和导航生命周期

private struct TabLifecycleModifier: ViewModifier {
    let appStore: AppStore
    let session: RecommendSession
    let viewModel: RecommendViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: appStore.selectedTab) { _, newTab in
                if newTab == .forYou {
                    if !session.hasInitializedPool, !viewModel.dramas.isEmpty {
                        session.initializePool(dramas: viewModel.dramas)
                    } else {
                        session.engine.playFromSystemResume()
                    }
                } else {
                    session.engine.pause(reason: .system)
                }
            }
            .onChange(of: appStore.isShowingSearch) { _, isShowing in
                guard appStore.selectedTab == .forYou else { return }
                if isShowing { session.engine.pause(reason: .system) } else { session.engine.playFromSystemResume() }
            }
            .onChange(of: appStore.isShowingMembership) { _, isShowing in
                guard appStore.selectedTab == .forYou else { return }
                if isShowing { session.engine.pause(reason: .system) } else { session.engine.playFromSystemResume() }
            }
    }
}

// MARK: - 收藏提示

/// 短剧应用风格收藏提示 — 中央偏下暗色气泡
private struct CollectToastView: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.8)))
    }
}

// MARK: - 剧集详情弹层

/// 短剧应用风格剧集详情弹层
private struct DramaAboutSheet: View {
    private enum Tab {
        case synopsis
        case episodes
    }

    let drama: DramaItem
    let relatedDramas: [DramaItem]
    @Binding var isPresented: Bool
    var onWatchFullSeries: () -> Void

    @State private var selectedTab: Tab = .synopsis

    var body: some View {
        GeometryReader { geo in
            let sheetHeight = min(geo.size.height * 0.78, max(geo.size.height * 0.6, geo.size.height - geo.safeAreaInsets.top - 24))

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                VStack(spacing: 0) {
                    sheetChrome
                    header
                    tabBar

                    ScrollView(showsIndicators: false) {
                        Group {
                            if selectedTab == .synopsis {
                                synopsisContent
                            } else {
                                episodesContent
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: sheetHeight, alignment: .top)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#232323"), Color(hex: "#111111")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var sheetChrome: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(width: 40, height: 5)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 21, weight: .light))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 7)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImageView(
                url: drama.coverURL,
                aspectRatio: 2.0 / 3.0,
                cornerRadius: 6,
                width: 92,
                height: 124
            )

            VStack(alignment: .leading, spacing: 9) {
                Text(drama.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text("\(drama.formattedViewCount) Views")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.42))

                HStack(spacing: 5) {
                    Image(systemName: "star")
                        .font(.system(size: 14, weight: .regular))
                    Text(String(format: "%.1f(5.5K)", drama.rating))
                    Text("Rate")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white.opacity(0.52))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var tabBar: some View {
        HStack(alignment: .bottom, spacing: 32) {
            tabButton("Synopsis", tab: .synopsis)
            tabButton("Episodes", tab: .episodes)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func tabButton(_ title: String, tab: Tab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.45))
                Capsule()
                    .fill(selectedTab == tab ? Color.white : Color.clear)
                    .frame(width: 34, height: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private var synopsisContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(drama.synopsis)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white.opacity(0.78))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            tagCloud

            VStack(alignment: .leading, spacing: 16) {
                Text("Cast")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                castRow(name: "Xinhui Zhu", color: DB.gold.opacity(0.8))
                castRow(name: "Yadi Zhang", color: DB.pink.opacity(0.75))
            }

            if !relatedDramas.isEmpty {
                VStack(spacing: 16) {
                    HStack {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                        Text("More Like This")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.42))
                            .fixedSize()
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 16) {
                        ForEach(relatedDramas, id: \.id) { item in
                            relatedDramaCard(item)
                        }
                    }
                }
            }
        }
    }

    private var tagCloud: some View {
        HStack(spacing: 8) {
            aboutTag("Revenge")
            aboutTag("Counterattack")
            aboutTag("Hidden Identity")
            aboutTag(L10n.categoryDisplayName(drama.category))
        }
    }

    private func aboutTag(_ text: String) -> some View {
        HStack(spacing: 3) {
            Text(text)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white.opacity(0.56))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
    }

    private func castRow(name: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 54, height: 54)
                .overlay(
                    Text(String(name.prefix(1)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                )

            Text(name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.36))
        }
    }

    private var episodesContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 34) {
                Text("1-30")
                    .foregroundColor(.white)
                Text("31-60")
                    .foregroundColor(.white.opacity(0.38))
            }
            .font(.system(size: 18, weight: .medium))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(1...max(60, drama.episodeCount), id: \.self) { episode in
                    episodeButton(episode)
                }
            }
        }
    }

    private func episodeButton(_ episode: Int) -> some View {
        Button {
            if episode <= 3 {
                onWatchFullSeries()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .frame(height: 54)

                Text("\(episode)")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if episode > 11 {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.82))
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func relatedDramaCard(_ item: DramaItem) -> some View {
        Button {
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    CoverImageView(
                        url: item.coverURL,
                        aspectRatio: 2.0 / 3.0,
                        cornerRadius: 3
                    )
                    .frame(height: 150)
                    .clipped()

                    Label(item.formattedViewCount, systemImage: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(5)
                        .shadow(color: .black.opacity(0.7), radius: 2)
                }

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)

                Text(L10n.categoryDisplayName(item.category))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { isPresented = false }
    }
}

// MARK: - 通知引导弹窗

/// 短剧应用风格通知弹窗，仅用于模拟
private struct NotificationPromptView: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(DB.pink.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 32))
                        .foregroundColor(DB.pink)
                }
                .padding(.top, 28)
                .padding(.bottom, 20)

                Text("Turn on Notifications")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 8)

                Text("Get notified about new episodes, exclusive releases, and special rewards.")
                    .font(.system(size: 14))
                    .foregroundColor(DB.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)

                Button { dismiss() } label: {
                    Text("Allow Notifications")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DB.pink)
                        .cornerRadius(DB.ctaRadius)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

                Button { dismiss() } label: {
                    Text("Not Now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DB.mutedText)
                }
                .padding(.bottom, 24)
            }
            .frame(width: 300)
            .background(DB.panelElevated)
            .clipShape(RoundedRectangle(cornerRadius: DB.sheetCornerRadius))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 4)
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { isPresented = false }
    }
}

#if DEBUG
#Preview("Recommend View") {
    RecommendView(session: RecommendSession()).environmentObject(AppStore())
}
#endif
}
