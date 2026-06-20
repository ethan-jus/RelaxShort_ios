import SwiftUI
import AVKit

// MARK: - Series Player View

/// 剧集沉浸播放页 — 同一部剧的 EP 播放流
///
/// **导航**：NavigationStack push，系统返回按钮 + 边缘右滑
/// **产品定位**：连续剧模式，提升连续观看 & 付费率
/// - 上下滑 = 上一集 / 下一集（同一部剧）
/// - 长按 = 2.0x 倍速
/// - 顶部：系统导航栏（剧名 + EP）
/// - 底部：解锁按钮 + 选集入口 → push 选集网格页
///
/// → 入口：RecommendView 点击「观看全集」
struct SeriesPlayerView: View {

    let drama: DramaItem
    let startEpisode: Int
    @EnvironmentObject var dependencies: DependencyContainer

    @State private var currentEpisode: Int
    @State private var dragOffset: CGFloat = 0
    @State private var showSpeedHUD = false
    @State private var showEpisodeList = false
    @State private var showUnlockSheet = false
    @State private var unlockTargetEpisode: Int = 0
    @State private var isBookmarked = false
    @State private var showShare = false
    @State private var episodes: [Episode] = []
    /// 当前 session 内解锁的剧集
    @State private var unlockedEpisodes: Set<Int> = []

    @State private var playerPool = PlayerPool()
    @StateObject private var playerController = PlayerController()

    /// 总集数：从 episodes.count 派生，初始化时用 drama.episodeCount 兜底（可能为 0）
    private var totalEpisodes: Int { max(episodes.count, drama.episodeCount) }

    init(drama: DramaItem, startEpisode: Int? = nil) {
        self.drama = drama
        self.startEpisode = startEpisode ?? max(1, drama.currentEpisode)
        self._currentEpisode = State(initialValue: self.startEpisode)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                //Color.black.ignoresSafeArea()

                episodePager(in: geo)

                // 底部渐变 — 让按钮区可读
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 280)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                // ── 底部左侧：解锁 + 选集 ──
                bottomBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, DT.Space.pageH)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 10)

                // ── 右侧操作按钮栏 ──
                RightActionBar(
                    isBookmarked: $isBookmarked,
                    viewCount: drama.formattedViewCount,
                    onBookmark: { isBookmarked.toggle() },
                    onShare: { showShare = true },
                    onEpisodes: { showEpisodeList = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, DT.Space.pageH)
                .padding(.bottom, geo.safeAreaInsets.bottom + 10)

                // ── 2.0x 倍速 HUD ──
                if showSpeedHUD {
                    SpeedHUDView()
                        .transition(.scale.combined(with: .opacity))
                }

                // ── 选集底部弹层 ──
                if showEpisodeList {
                    EpisodePickerSheet(
                        episodes: episodes,
                        currentEpisode: $currentEpisode,
                        unlockedEpisodes: unlockedEpisodes,
                        isPresented: $showEpisodeList,
                        onUnlock: { ep in
                            unlockTargetEpisode = ep
                            showEpisodeList = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showUnlockSheet = true
                            }
                        }
                    )
                    .zIndex(200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── 解锁弹层 ──
                if showUnlockSheet {
                    UnlockEpisodeSheet(
                        episodeNumber: unlockTargetEpisode,
                        coinPrice: 100,
                        isPresented: $showUnlockSheet,
                        onUnlockWithCoins: {
                            unlockedEpisodes.insert(unlockTargetEpisode)
                            showUnlockSheet = false
                        },
                        onWatchAd: {
                            unlockedEpisodes.insert(unlockTargetEpisode)
                            showUnlockSheet = false
                        }
                    )
                    .zIndex(300)
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .navigationTitle("\(drama.title) \(L10n.episodeNumber(currentEpisode))")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            ShareSheet(dramaTitle: drama.title)
                .presentationDetents([.medium])
        }
        .task { await loadEpisodes() }
        .onChange(of: currentEpisode) { oldValue, newValue in
            handleEpisodeTransition(from: oldValue, to: newValue)
        }
        .onDisappear {
            playerController.cleanup()
            playerPool.cleanup()
        }
    }

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
        initializeEpisodePool()
    }

    /// 通过 RealDetailRepository 获取当前集播放地址，更新 Episode.videoURL。
    /// 失败时保留已有 URL（来自 episodes 响应或 Mock）。
    private func fetchCurrentEpisodePlaybackURL() async {
        guard let repo = dependencies.detailRepository as? RealDetailRepository else { return }
        guard let epIndex = episodes.firstIndex(where: { $0.episodeNumber == currentEpisode }) else { return }
        do {
            if let url = try await repo.fetchPlaybackURL(episodeId: episodes[epIndex].id) {
                episodes[epIndex].videoURL = url
                Logger.viewModel.info("SeriesPlayerView: fetched playback URL for EP \(currentEpisode)")
            }
        } catch {
            Logger.viewModel.warning("SeriesPlayerView: episodePlay failed, using fallback videoURL: \(error.localizedDescription)")
        }
    }

    // MARK: - PlayerPool 管理

    private func initializeEpisodePool() {
        guard let url = episodeVideoURL(for: currentEpisode) else { return }
        playerPool.setCurrent(url: url)
        preloadEpisodeAdjacent(for: currentEpisode)
    }

    private func handleEpisodeTransition(from old: Int, to new: Int) {
        if new > old {
            playerPool.advance()
        } else if new < old {
            playerPool.retreat()
        }
        preloadEpisodeAdjacent(for: new)
    }

    private func preloadEpisodeAdjacent(for ep: Int) {
        let nextEp = ep + 1
        if nextEp <= totalEpisodes, let url = episodeVideoURL(for: nextEp) {
            playerPool.preloadNext(url: url)
        }
        let prevEp = ep - 1
        if prevEp >= 1, let url = episodeVideoURL(for: prevEp) {
            playerPool.preloadPrevious(url: url)
        }
    }

    private func episodeVideoURL(for ep: Int) -> URL? {
        guard let episode = episodes.first(where: { $0.episodeNumber == ep }) else { return nil }
        return URL(string: episode.videoURL)
    }

    // MARK: - Episode Pager

    private func episodePager(in geo: GeometryProxy) -> some View {
        let pageHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
        let yOffset = -CGFloat(currentEpisode - 1) * pageHeight + dragOffset

        return ZStack {
            ForEach(visibleEpisodeIndices(), id: \.self) { ep in
                VideoPlayerView(
                    coverURL: drama.coverURL,
                    player: (ep == currentEpisode) ? playerPool.current : nil,
                    controller: (ep == currentEpisode) ? playerController : nil
                )
                .allowsHitTesting(false)
                .frame(width: geo.size.width, height: pageHeight)
                .position(x: geo.size.width / 2, y: CGFloat(ep - 1) * pageHeight + pageHeight / 2 + yOffset)
            }
        }
        .frame(width: geo.size.width, height: pageHeight)
        .clipped()
        .gesture(episodeDragGesture)
        .simultaneousGesture(longPressGesture)
        .simultaneousGesture(tapPauseGesture)
    }

    private func visibleEpisodeIndices() -> [Int] {
        guard totalEpisodes > 0 else { return [currentEpisode] }
        let lo = max(1, currentEpisode - 1)
        let hi = min(totalEpisodes, currentEpisode + 1)
        guard lo <= hi else { return [currentEpisode] }
        return Array(lo...hi)
    }

    // MARK: - Drag Gesture (Episode Navigation)

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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if value.translation.height < -80 || velocity < -300 {
                        currentEpisode = min(currentEpisode + 1, totalEpisodes)
                    } else if value.translation.height > 80 || velocity > 300 {
                        currentEpisode = max(currentEpisode - 1, 1)
                    }
                    dragOffset = 0
                }
            }
    }

    // MARK: - Long Press Speed-Up

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, _):
                    if playerController.isPlaying && playerController.currentTime > 0 {
                        playerController.setRate(2.0)
                        withAnimation(.spring(response: 0.3)) { showSpeedHUD = true }
                    }
                default: break
                }
            }
            .onEnded { _ in
                playerController.setRate(1.0)
                withAnimation(.spring(response: 0.3)) { showSpeedHUD = false }
            }
    }

    private var tapPauseGesture: some Gesture {
        TapGesture()
            .onEnded {
                playerController.togglePlayPause()
            }
    }

    // MARK: - Episode Lock Check

    private func isEpisodeLocked(_ ep: Int) -> Bool {
        if unlockedEpisodes.contains(ep) { return false }
        let freeRange = drama.freeEpisodeRange ?? 1...3
        return !freeRange.contains(ep)
    }

    // MARK: - Bottom Bar (左侧解锁按钮)

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if isEpisodeLocked(currentEpisode) {
                Button {
                    unlockTargetEpisode = currentEpisode
                    showUnlockSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                        Text("Unlock EP \(currentEpisode)")
                            .font(DT.Font.body(15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(DB.pink)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl))
                }
            }
        }
    }
}

// MARK: - Episode Picker Sheet (底部弹层，非push)

/// DramaBox 风格选集底部弹层 — 视频留在底层，弹层展示选集网格
private struct EpisodePickerSheet: View {
    let episodes: [Episode]
    @Binding var currentEpisode: Int
    let unlockedEpisodes: Set<Int>
    @Binding var isPresented: Bool
    var onUnlock: (Int) -> Void

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 5
    )

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
                    .padding(.bottom, 12)

                Text("Episodes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(1...episodes.count, id: \.self) { ep in
                            episodeCell(for: ep)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxHeight: 300)
            }
            .padding(.bottom, 20)
            .background(DB.panel)
            .clipShape(RoundedRectangle(cornerRadius: DB.sheetCornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func episodeCell(for ep: Int) -> some View {
        let isCurrent = ep == currentEpisode
        let isLocked = !unlockedEpisodes.contains(ep) && ep > 3

        Button {
            if isLocked {
                onUnlock(ep)
            } else {
                currentEpisode = ep
                dismiss()
            }
        } label: {
            VStack(spacing: 4) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DB.mutedText)
                }
                Text("\(ep)")
                    .font(.system(size: 14, weight: isCurrent ? .bold : .regular))
                    .foregroundColor(isCurrent ? .white : (isLocked ? DB.mutedText : .white.opacity(0.8)))
            }
            .frame(width: 52, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? DB.pink : (isLocked ? Color.white.opacity(0.05) : Color.white.opacity(0.12)))
            )
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { isPresented = false }
    }
}

// MARK: - Unlock Episode Sheet

/// DramaBox 风格解锁弹层 — 金币解锁 或 看广告解锁
private struct UnlockEpisodeSheet: View {
    let episodeNumber: Int
    let coinPrice: Int
    @Binding var isPresented: Bool
    var onUnlockWithCoins: () -> Void
    var onWatchAd: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundColor(DB.gold)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                Text("Unlock Episode \(episodeNumber)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 8)

                Text("This episode requires coins to unlock. Choose your method below.")
                    .font(.system(size: 13))
                    .foregroundColor(DB.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                // 金币解锁
                Button {
                    onUnlockWithCoins()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bitcoinsign.circle.fill")
                        Text("Unlock with \(coinPrice) Coins")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DB.gold)
                    .cornerRadius(DB.ctaRadius)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                // 看广告解锁
                Button {
                    onWatchAd()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                        Text("Watch Ad to Unlock")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: DB.ctaRadius)
                            .stroke(DB.pink, lineWidth: 1.5)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 300)
            .background(DB.panelElevated)
            .clipShape(RoundedRectangle(cornerRadius: DB.sheetCornerRadius))
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { isPresented = false }
    }
}

#if DEBUG
#Preview("Series Player") {
    NavigationStack {
        SeriesPlayerView(drama: DramaItem(
            id: "1",
            title: "友情博弈",
            coverURL: "",
            category: "都市",
            tags: ["独家", "现代言情"],
            viewCount: 234000,
            episodeCount: 63,
            currentEpisode: 3,
            synopsis: "温栀妍跟沈霁寒隐婚四年，却从未见过公公婆婆。",
            isHot: true,
            isTrending: false,
            rating: 4.8
        ))
    }
}
#endif
