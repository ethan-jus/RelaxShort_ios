import SwiftUI

// MARK: - Drama Feed View (DramaBox-style)

/// 推荐页 — 沉浸式短剧 Feed 流，对标 DramaBox
///
/// **布局**：
/// - 全屏视频区，顶部无黑边，延伸至状态栏
/// - 右上角搜索按钮，毛玻璃圆形背景
/// - 底部渐变遮罩 + 标题/标签/简介 + CTA 按钮
/// - 右侧收藏+分享操作按钮（半透明圆形背景）
/// - 底部视频播放进度条（紧贴底部，拖动时显示时间预览+拇指图）
///
/// 播放状态由 MainTabView 持有的 RecommendSession 管理，本 View 即使被 SwiftUI 重建也不会丢失状态。
struct RecommendView: View {

    @EnvironmentObject private var appStore: AppStore
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

    init(viewModel: RecommendViewModel? = nil, session: RecommendSession, isVisible: Bool = true) {
        self.viewModel = viewModel ?? RecommendViewModel(repository: MockHomeRepository())
        self.session = session
        self.isVisible = isVisible
    }

    // MARK: - Computed Route Block

    private var routeBlocksPlayback: Bool {
        appStore.isShowingSearch || appStore.isShowingMembership || appStore.navigationTarget != nil
    }

    private var isPlaybackVisible: Bool {
        isVisible && !routeBlocksPlayback
    }

    // MARK: - Body

    var body: some View {
        contentView
            .ignoresSafeArea()
            .task { await loadAndInit() }
            .sheet(isPresented: $showShare) {
                ShareSheet(dramaTitle: currentDrama?.title ?? "")
                    .presentationDetents([.medium])
            }
            .onChange(of: session.currentIndex) { oldValue, newValue in
                // Per-video transition reset
                isExpanded = false
                isScrubbing = false; scrubFraction = 0
                isSpeeding = false; showSpeedHUD = false
                session.controller.resetForNewPlayer()
                session.handleTransition(from: oldValue, to: newValue, dramas: viewModel.dramas)
                if isPlaybackVisible { session.controller.playAfterAttach() }
            }
            .onChange(of: isPlaybackVisible) { _, vis in
                if vis { session.controller.playFromSystemResume() }
                else { session.controller.pauseForSystem() }
            }
            .onAppear { setupAutoPlay() }
            .modifier(TabLifecycleModifier(appStore: appStore, session: session, viewModel: viewModel))
    }

    // MARK: - Content View

    private var contentView: some View {
        GeometryReader { geo in
            ZStack {
                if viewModel.dramas.isEmpty {
                    emptyState(in: geo)
                } else {
                    feedOverlayContent(in: geo)
                }

                // Fixed overlays
                let searchTopPadding = geo.safeAreaInsets.top + 44
                searchBarButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 24)
                    .padding(.top, searchTopPadding)

                if session.controller.pauseReason == .user, session.controller.hasStartedPlayingOnce {
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
                    DramaAboutSheet(drama: drama, isPresented: $showAbout).zIndex(200)
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
            ForEach(visibleIndices(for: session.currentIndex, count: dramas.count), id: \.self) { idx in
                let isCurrent = idx == session.currentIndex
                ZStack {
                    VideoPlayerView(
                        coverURL: dramas[idx].coverURL,
                        player: isCurrent ? session.pool.current : nil,
                        controller: isCurrent ? session.controller : nil
                    )
                        .allowsHitTesting(false)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.1), .black.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    // Per-page bottom overlay
                    if !isScrubbing, !isSpeeding {
                        pageBottomOverlay(drama: dramas[idx], isCurrent: isCurrent, geo: geo)
                    }
                }
                .frame(width: geo.size.width, height: pageHeight)
                .position(x: geo.size.width / 2, y: CGFloat(idx) * pageHeight + pageHeight / 2 + yOffset)
            }

            // Progress bar sits above gesture layer (zIndex 30)
            progressBar(totalWidth: geo.size.width - 24)
                .padding(.horizontal, 12)
                .padding(.bottom, 86)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .zIndex(30)

            Color.clear
                .contentShape(Rectangle())
                .gesture(verticalDrag(count: dramas.count))
                .simultaneousGesture(longPressGesture)
                .simultaneousGesture(tapGesture)
        }
        .frame(width: geo.size.width, height: pageHeight)
        .clipped()
    }

    private func pageBottomOverlay(drama: DramaItem, isCurrent: Bool, geo: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = 20
        let actionRailWidth: CGFloat = 58
        let actionRailGap: CGFloat = 14
        let tabBarAvoidance: CGFloat = 92
        let contentWidth = geo.size.width - horizontalPadding * 2 - actionRailWidth - actionRailGap

        return VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
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
                        }.buttonStyle(.plain)

                        // Tags
                        HStack(spacing: 6) {
                            feedTag("Members Only", bg: DB.gold.opacity(0.25), fg: DB.gold)
                            feedTag("Exclusive", bg: Color.white.opacity(0.12), fg: .white.opacity(0.85))
                            feedTag(L10n.categoryDisplayName(drama.category), bg: Color.white.opacity(0.12), fg: .white.opacity(0.85))
                        }

                        // Synopsis toggle expand/collapse
                        synopsisView(drama.synopsis)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() } }
                    }
                    .frame(width: contentWidth, alignment: .leading)

                    // Action rail
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

                // CTA as Button (not NavigationLink) for reliable tap
                Button {
                    session.controller.pauseForSystem()
                    appStore.navigationTarget = SeriesPlayerNav(drama: drama, startEpisode: max(1, drama.currentEpisode))
                } label: {
                    Text("Watch Full Series")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: contentWidth, height: 44)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.42)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, tabBarAvoidance)
        }
        .zIndex(10)
    }

    private func synopsisView(_ text: String) -> some View {
        Group {
            if isExpanded {
                (Text("Trailer | ").font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                + Text(text).font(.system(size: 13)).foregroundColor(.white.opacity(0.65)))
            } else {
                (Text("Trailer | ").font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                + Text(truncatedSynopsis(text)).font(.system(size: 13)).foregroundColor(.white.opacity(0.65))
                + Text("... more").font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.9)))
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
        await viewModel.loadData()
        if isVisible, !session.hasInitializedPool {
            session.initializePool(dramas: viewModel.dramas)
            session.controller.playAfterAttach()
            if !hasShownNotification {
                hasShownNotification = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.3)) { showNotificationPrompt = true }
                }
            }
        }
    }

    // MARK: - Computed

    private var currentDrama: DramaItem? {
        guard viewModel.dramas.indices.contains(session.currentIndex) else { return nil }
        return viewModel.dramas[session.currentIndex]
    }

    // MARK: - Auto Play Setup

    private func setupAutoPlay() {
        let s = session
        s.controller.onPlaybackFinished = {
            s.controller.pauseForSystem()
            s.controller.seek(to: 0)
            // For You v1: do not auto-navigate to fullscreen
        }
    }

    // MARK: - Search Bar Button

    private var searchBarButton: some View {
        Button {
            NotificationCenter.default.post(name: .showSearch, object: nil)
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.2)))
        }
    }

    // MARK: - Empty State

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

    // Old feedPager removed — feedOverlayContent is the single pager implementation

    private func visibleIndices(for current: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return Array(max(0, current - 1)...min(count - 1, current + 1))
    }

    // MARK: - Drag Gesture

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

    // MARK: - Tap Gesture

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                handleVideoTap()
            }
    }

    private func handleVideoTap() {
        let ctrl = session.controller
        if ctrl.isPlaying {
            ctrl.pauseByUser()
        } else if ctrl.pauseReason == .user {
            ctrl.togglePlayPause()
        }
    }

    // MARK: - Long Press 2x Speed-Up

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard !isScrubbing, !isDraggingPage else { return }
                switch value {
                case .second(true, _):
                    if !isSpeeding {
                        isSpeeding = true
                        session.controller.setRate(2.0)
                        withAnimation(.spring(response: 0.3)) { showSpeedHUD = true }
                    }
                default: break
                }
            }
            .onEnded { _ in
                isSpeeding = false
                session.controller.setRate(1.0)
                withAnimation(.spring(response: 0.3)) { showSpeedHUD = false }
            }
    }

    // MARK: - Progress Bar

    private func progressBar(totalWidth: CGFloat) -> some View {
        let barWidth = totalWidth
        let fraction = session.controller.duration > 0
            ? (isScrubbing ? Double(scrubFraction) : session.controller.currentTime / session.controller.duration)
            : 0
        let buffered = session.controller.bufferProgress
        let effectiveHeight: CGFloat = isScrubbing ? 8 : 3
        let clampedProgress = max(0, min(1, CGFloat(fraction)))
        let scrubSeconds = Double(clampedProgress) * session.controller.duration
        let showSeekPreview = isScrubbing

        return VStack(spacing: 0) {
            if showSeekPreview {
                VStack(spacing: 8) {
                    // Thumbnail preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 160, height: 90)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                            )
                        if let thumbnail = session.controller.thumbnailImage {
                            Image(uiImage: thumbnail)
                                .resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 160, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Time text
                    Text("\(formatTime(scrubSeconds)) / \(formatTime(session.controller.duration))")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
                .transition(.opacity)
            }

            ZStack(alignment: .leading) {
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
            .frame(height: max(44, effectiveHeight), alignment: .bottom)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            wasPlayingBeforeScrub = session.controller.isPlaying
                            if isSpeeding {
                                isSpeeding = false
                                session.controller.setRate(1.0)
                                showSpeedHUD = false
                            }
                        }
                        isScrubbing = true
                        let x = value.location.x
                        scrubFraction = max(0, min(1, x / barWidth))
                        session.controller.generateThumbnail(at: scrubFraction)
                    }
                    .onEnded { value in
                        let x = value.location.x
                        let clamped = max(0, min(1, x / barWidth))
                        session.controller.seek(to: Double(clamped))
                        if wasPlayingBeforeScrub { session.controller.playFromSystemResume() }
                        isScrubbing = false
                        scrubFraction = 0
                        wasPlayingBeforeScrub = false
                    }
            )
        }
    }

    // MARK: - Time Format

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

// MARK: - Tab & Navigation Lifecycle Modifier

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
                        session.controller.playFromSystemResume()
                    }
                } else {
                    session.controller.pauseForSystem()
                }
            }
            .onChange(of: appStore.isShowingSearch) { _, isShowing in
                guard appStore.selectedTab == .forYou else { return }
                if isShowing { session.controller.pauseForSystem() } else { session.controller.playFromSystemResume() }
            }
            .onChange(of: appStore.isShowingMembership) { _, isShowing in
                guard appStore.selectedTab == .forYou else { return }
                if isShowing { session.controller.pauseForSystem() } else { session.controller.playFromSystemResume() }
            }
            .onChange(of: appStore.navigationTarget) { _, target in
                guard appStore.selectedTab == .forYou else { return }
                if target != nil { session.controller.pauseForSystem() } else { session.controller.playFromSystemResume() }
            }
    }
}

// MARK: - DramaBox Collect Toast

/// DramaBox 风格收藏 Toast — 中央偏下暗色气泡
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

// MARK: - DramaBox About Sheet

/// DramaBox 风格剧集详情弹层
private struct DramaAboutSheet: View {
    let drama: DramaItem
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                HStack(alignment: .top, spacing: 16) {
                    CoverImageView(
                        url: drama.coverURL,
                        aspectRatio: 2.0 / 3.0,
                        cornerRadius: DB.posterRadius,
                        width: 100,
                        height: 150
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(drama.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            aboutTag(drama.category, color: DB.pink.opacity(0.8))
                        }

                        HStack(spacing: 8) {
                            Label("\(drama.episodeCount) EP", systemImage: "play.rectangle")
                                .font(.system(size: 12))
                                .foregroundColor(DB.mutedText)
                            Label(String(format: "%.1f", drama.rating), systemImage: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(DB.gold)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Text(drama.synopsis)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(6)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Button {
                    dismiss()
                } label: {
                    Text("Watch Full Series")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DB.pink)
                        .cornerRadius(DB.ctaRadius)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 34)
            }
            .background(DB.panel)
            .clipShape(RoundedRectangle(cornerRadius: DB.sheetCornerRadius, style: .continuous))
        }
        .transition(.opacity)
    }

    private func aboutTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.3))
            .cornerRadius(4)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { isPresented = false }
    }
}

// MARK: - DramaBox Notification Prompt

/// DramaBox 风格通知弹窗 (mock only)
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
