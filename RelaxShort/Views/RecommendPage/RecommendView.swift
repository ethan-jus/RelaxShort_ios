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

    @State private var dragOffset: CGFloat = 0
    @State private var isExpanded = false
    @State private var showShare = false
    @State private var isSpeeding = false
    @State private var showSpeedHUD = false
    @State private var isBookmarked = false
    @State private var showBookmarkToast = false
    @State private var isTruncated = false
    @State private var isScrubbing = false
    @State private var scrubFraction: CGFloat = 0
    @State private var showAbout = false
    @State private var showNotificationPrompt = false
    @State private var hasShownNotification = false

    init(viewModel: RecommendViewModel? = nil, session: RecommendSession) {
        self.viewModel = viewModel ?? RecommendViewModel(repository: MockHomeRepository())
        self.session = session
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
                isExpanded = false
                isTruncated = false
                session.handleTransition(from: oldValue, to: newValue, dramas: viewModel.dramas)
            }
            .onAppear { setupAutoPlay() }
            .onDisappear { session.controller.pause() }
            .modifier(TabLifecycleModifier(appStore: appStore, session: session, viewModel: viewModel))
    }

    // MARK: - Content View (split to fix type-checking)

    private var contentView: some View {
        GeometryReader { geo in
            ZStack {
                if viewModel.dramas.isEmpty {
                    emptyState(in: geo)
                } else {
                    feedOverlayContent(in: geo)
                }
            }
        }
    }

    @ViewBuilder
    private func feedOverlayContent(in geo: GeometryProxy) -> some View {
        feedPager(in: geo)

        LinearGradient(
            colors: [.clear, .black.opacity(0.1), .black.opacity(0.85)],
            startPoint: .top, endPoint: .bottom
        )
        .allowsHitTesting(false)

        let searchTopPadding = geo.safeAreaInsets.top + 44
        searchBarButton
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 24)
            .padding(.top, searchTopPadding)

        // Pause overlay
        if !session.controller.isPlaying {
            Button { session.controller.togglePlayPause() } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        bottomContent(in: geo)

        progressBar(totalWidth: geo.size.width)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, DT.Space.pageH)
            .padding(.bottom, 56)

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

        // About Sheet
        if showAbout, let drama = currentDrama {
            DramaAboutSheet(drama: drama, isPresented: $showAbout)
                .zIndex(200)
        }

        // Notification Prompt
        if showNotificationPrompt {
            NotificationPromptView(isPresented: $showNotificationPrompt)
                .zIndex(300)
        }
    }

    private func loadAndInit() async {
        await viewModel.loadData()
        if appStore.selectedTab == .forYou, !session.hasInitializedPool {
            session.initializePool(dramas: viewModel.dramas)
            // 首次进入For You延迟展示通知弹窗
            if !hasShownNotification {
                hasShownNotification = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showNotificationPrompt = true
                    }
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
        session.controller.onPlaybackFinished = { [weak session, weak appStore] in
            guard let session, let appStore else { return }
            let idx = session.currentIndex
            let dramas = viewModel.dramas
            if dramas.indices.contains(idx) {
                appStore.navigationTarget = SeriesPlayerNav(drama: dramas[idx], startEpisode: 2)
            }
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

    // MARK: - Vertical Feed Pager

    private func feedPager(in geo: GeometryProxy) -> some View {
        let pageHeight = geo.size.height
        let dramas = viewModel.dramas
        let yOffset = -CGFloat(session.currentIndex) * pageHeight + dragOffset

        return ZStack {
            ForEach(visibleIndices(for: session.currentIndex, count: dramas.count), id: \.self) { idx in
                VideoPlayerView(
                    coverURL: dramas[idx].coverURL,
                    player: (idx == session.currentIndex) ? session.pool.current : nil,
                    controller: (idx == session.currentIndex) ? session.controller : nil
                )
                    .allowsHitTesting(false)
                    .frame(width: geo.size.width, height: pageHeight)
                    .position(x: geo.size.width / 2, y: CGFloat(idx) * pageHeight + pageHeight / 2 + yOffset)
            }

            Color.clear
                .contentShape(Rectangle())
                .gesture(verticalDrag(count: dramas.count))
                .simultaneousGesture(longPressGesture)
                .simultaneousGesture(tapGesture)
        }
        .frame(width: geo.size.width, height: pageHeight)
        .clipped()
    }

    private func visibleIndices(for current: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return Array(max(0, current - 1)...min(count - 1, current + 1))
    }

    // MARK: - Drag Gesture

    private func verticalDrag(count: Int) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
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
            }
    }

    // MARK: - Tap Gesture

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                session.controller.togglePlayPause()
            }
    }

    // MARK: - Long Press Speed-Up

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
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

    // MARK: - Bottom Content

    private func bottomContent(in geo: GeometryProxy) -> some View {
        let sidebarWidth: CGFloat = 44
        let contentMaxWidth = geo.size.width - 24 * 2 - sidebarWidth - 16
        let uiHidden = isSpeeding || isScrubbing

        return VStack(spacing: 0) {
            Spacer()
            HStack(alignment: .bottom, spacing: 16) {
                infoSection(maxWidth: contentMaxWidth)
                    .opacity(uiHidden ? 0 : 1)
                    .allowsHitTesting(!uiHidden)
                rightActionBar
                    .opacity(uiHidden ? 0 : 1)
                    .allowsHitTesting(!uiHidden)
            }
            .padding(.horizontal, 24)

            if let drama = currentDrama {
                ctaButton(drama: drama, maxWidth: geo.size.width - 48)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .opacity(uiHidden ? 0 : 1)
                    .allowsHitTesting(!uiHidden)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Info Section (DramaBox style)

    private func infoSection(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let drama = currentDrama {
                // Title + chevron → opens About
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { showAbout = true }
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
            }
            tagRow
            if let drama = currentDrama {
                synopsisBlock(drama.synopsis)
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    // MARK: - Synopsis Block

    @ViewBuilder
    private func synopsisBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Trailer | synopsis format
            HStack(alignment: .top, spacing: 0) {
                Text("Trailer | ")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                + Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
            }
            .lineLimit(isExpanded ? nil : 2)
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.toggle()
            }

            if !isExpanded {
                Button { isExpanded = true } label: {
                    Text("more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - CTA Button

    private func ctaButton(drama: DramaItem, maxWidth: CGFloat) -> some View {
        NavigationLink(value: SeriesPlayerNav(drama: drama, startEpisode: max(1, drama.currentEpisode))) {
            Text("Watch Full Series")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: maxWidth)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress Bar

    private func progressBar(totalWidth: CGFloat) -> some View {
        let barWidth = totalWidth - 32
        let fraction = session.controller.duration > 0
            ? (isScrubbing ? Double(scrubFraction) : session.controller.currentTime / session.controller.duration)
            : 0
        let buffered = session.controller.bufferProgress
        let effectiveHeight: CGFloat = isScrubbing ? 6 : 3
        let clampedProgress = max(0, min(1, CGFloat(fraction)))
        let scrubSeconds = Double(clampedProgress) * session.controller.duration

        return VStack(spacing: 0) {
            if isScrubbing {
                VStack(spacing: 6) {
                    if let thumbnail = session.controller.thumbnailImage {
                        Image(uiImage: thumbnail)
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text("\(formatTime(scrubSeconds)) / \(formatTime(session.controller.duration))")
                        .font(DT.Font.body(11, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: effectiveHeight)
                Capsule().fill(Color.white.opacity(0.15))
                    .frame(width: max(0, barWidth * CGFloat(buffered)), height: effectiveHeight)
                Capsule().fill(DT.logoRed)
                    .frame(width: max(effectiveHeight, barWidth * clampedProgress), height: effectiveHeight)
                if isScrubbing {
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .offset(x: max(0, min(barWidth, barWidth * clampedProgress)) - 7)
                }
            }
            .frame(height: max(24, effectiveHeight), alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        let x = value.location.x
                        scrubFraction = max(0, min(1, x / barWidth))
                        session.controller.generateThumbnail(at: scrubFraction)
                    }
                    .onEnded { value in
                        let x = value.location.x
                        let clamped = max(0, min(1, x / barWidth))
                        session.controller.seek(to: Double(clamped))
                        isScrubbing = false
                        scrubFraction = 0
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

    // MARK: - Tag Row

    @ViewBuilder
    private var tagRow: some View {
        if let drama = currentDrama {
            HStack(spacing: 6) {
                // Members Only tag — gold
                feedTag("Members Only", bg: DB.gold.opacity(0.25), fg: DB.gold)
                // Exclusive tag
                feedTag("Exclusive", bg: Color.white.opacity(0.12), fg: .white.opacity(0.85))
                // Category or first tag
                feedTag(L10n.categoryDisplayName(drama.category), bg: Color.white.opacity(0.12), fg: .white.opacity(0.85))
            }
        }
    }

    private func feedTag(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Right Action Bar

    private var rightActionBar: some View {
        RightActionBar(
            isBookmarked: $isBookmarked,
            viewCount: currentDrama?.formattedViewCount,
            onBookmark: {
                withAnimation(.spring(response: 0.3)) {
                    isBookmarked.toggle()
                    showBookmarkToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showBookmarkToast = false
                    }
                }
            },
            onShare: { showShare = true }
        )
    }

    // MARK: - Bookmark Toast

    private var bookmarkToastView: some View {
        HStack(spacing: 6) {
            Image(systemName: isBookmarked ? "checkmark.circle.fill" : "bookmark.slash")
                .font(DT.Font.body(14, weight: .semibold))
            Text(isBookmarked ? L10n.favoritesAddedToast : L10n.favoritesRemovedToast)
                .font(DT.Font.body(14, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        session.controller.play()
                    }
                } else {
                    session.controller.pause()
                }
            }
            .onChange(of: appStore.isShowingSearch) { _, isShowing in
                guard appStore.selectedTab == .forYou else { return }
                if isShowing { session.controller.pause() } else { session.controller.play() }
            }
            .onChange(of: appStore.isShowingMembership) { _, isShowing in
                guard appStore.selectedTab == .forYou else { return }
                if isShowing { session.controller.pause() } else { session.controller.play() }
            }
            .onChange(of: appStore.navigationTarget) { _, target in
                guard appStore.selectedTab == .forYou else { return }
                if target != nil { session.controller.pause() } else { session.controller.play() }
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
