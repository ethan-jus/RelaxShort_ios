import SwiftUI
import AVKit

// MARK: - Series Player View (接入 ShortVideoPlayerEngine)

struct SeriesPlayerView: View {

    let drama: DramaItem
    let startEpisode: Int
    let handoff: PlayerHandoffContext?

    @State private var currentEpisode: Int
    @State private var dragOffset: CGFloat = 0
    @State private var showSpeedHUD = false
    @State private var showEpisodeList = false
    @State private var showUnlockSheet = false
    @State private var unlockTargetEpisode: Int = 0
    @State private var isBookmarked = false
    @State private var showShare = false
    @State private var episodes: [Episode] = []
    @State private var unlockedEpisodes: Set<Int> = []
    @State private var pendingLockedEpisode: Int?

    @EnvironmentObject var playerCoordinator: PlayerCoordinator

    private var totalEpisodes: Int

    init(drama: DramaItem, startEpisode: Int? = nil, handoff: PlayerHandoffContext? = nil) {
        self.drama = drama
        self.totalEpisodes = drama.episodeCount
        self.startEpisode = startEpisode ?? max(1, drama.currentEpisode)
        self.handoff = handoff
        self._currentEpisode = State(initialValue: self.startEpisode)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                episodePager(in: geo)

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

                if showSpeedHUD {
                    SpeedHUDView()
                        .transition(.scale.combined(with: .opacity))
                }

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
        .onChange(of: showUnlockSheet) { _, isShowing in
            guard !isShowing, let pending = pendingLockedEpisode, isEpisodeLocked(pending) else { return }
            pendingLockedEpisode = nil
        }
        .onDisappear {
            playerCoordinator.release(.series(dramaID: drama.id))
        }
    }

    // MARK: - Episode Loading

    private func loadEpisodes() async {
        let repo = MockDetailRepository()
        episodes = (try? await repo.fetchEpisodes(dramaId: drama.id)) ?? []
        initializeEpisodePlayer()
    }

    private func playerItems(from eps: [Episode]) -> [PlayerMediaItem] {
        eps.compactMap { ep -> PlayerMediaItem? in
            guard let url = URL(string: ep.videoURL) else { return nil }
            return PlayerMediaItem(
                id: PlayerMediaItem.stableID(dramaID: drama.id, episodeNumber: ep.episodeNumber),
                title: drama.title,
                episodeNumber: ep.episodeNumber,
                coverURL: drama.coverURL,
                source: .mp4(url),
                resumeTime: nil
            )
        }
    }

    private func initializeEpisodePlayer() {
        let items = playerItems(from: episodes)
        guard !items.isEmpty else { return }
        guard !isEpisodeLocked(currentEpisode) else {
            pendingLockedEpisode = currentEpisode
            unlockTargetEpisode = currentEpisode
            showUnlockSheet = true
            playerCoordinator.engine.pause(reason: .system)
            return
        }
        let startIndex = max(0, min(items.count - 1, currentEpisode - 1))
        playerCoordinator.claimSeries(drama: drama, items: items, startIndex: startIndex, handoff: handoff)
    }

    private func handleEpisodeTransition(from old: Int, to new: Int) {
        guard old != new else { return }
        // 锁定集不能播放 → 记录 pending，弹解锁，回退 episode
        guard !isEpisodeLocked(new) else {
            pendingLockedEpisode = new
            unlockTargetEpisode = new
            showUnlockSheet = true
            currentEpisode = old
            return
        }
        pendingLockedEpisode = nil
        let targetIndex = max(0, new - 1)
        playerCoordinator.engine.move(to: targetIndex)
    }

    private func playUnlockedPendingEpisode() {
        guard let pending = pendingLockedEpisode else { return }
        pendingLockedEpisode = nil

        let targetIndex = max(0, pending - 1)
        if playerCoordinator.engine.currentItem == nil {
            let items = playerItems(from: episodes)
            guard items.indices.contains(targetIndex) else { return }
            currentEpisode = pending
            playerCoordinator.engine.prepare(items: items, index: targetIndex)
            playerCoordinator.engine.play()
        } else if currentEpisode == pending {
            playerCoordinator.engine.move(to: targetIndex)
            playerCoordinator.engine.play()
        } else {
            currentEpisode = pending
        }
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
        .gesture(episodeDragGesture)
        .simultaneousGesture(longPressGesture)
        .simultaneousGesture(tapPauseGesture)
    }

    private func visibleEpisodeIndices() -> [Int] {
        let lo = max(1, currentEpisode - 1)
        let hi = min(totalEpisodes, currentEpisode + 1)
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
                if playerCoordinator.engine.state == .playing {
                    playerCoordinator.engine.pause(reason: .user)
                } else if playerCoordinator.engine.state == .pausedByUser {
                    playerCoordinator.engine.play()
                }
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

// MARK: - Episode Picker Sheet (unchanged)

private struct EpisodePickerSheet: View {
    let episodes: [Episode]; @Binding var currentEpisode: Int; let unlockedEpisodes: Set<Int>; @Binding var isPresented: Bool; var onUnlock: (Int) -> Void
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { dismiss() }
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.3)).frame(width: 36, height: 5).padding(.top, 10).padding(.bottom, 12)
                Text("Episodes").font(.system(size: 18, weight: .bold)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 12)
                ScrollView { LazyVGrid(columns: columns, spacing: 10) { ForEach(1...episodes.count, id: \.self) { ep in episodeCell(for: ep) } }.padding(.horizontal, 20) }.frame(maxHeight: 300)
            }.padding(.bottom, 20).background(DB.panel).clipShape(RoundedRectangle(cornerRadius: DB.sheetCornerRadius, style: .continuous))
        }
    }
    @ViewBuilder private func episodeCell(for ep: Int) -> some View {
        let isCurrent = ep == currentEpisode; let isLocked = !unlockedEpisodes.contains(ep) && ep > 3
        Button { if isLocked { onUnlock(ep) } else { currentEpisode = ep; dismiss() } } label: {
            VStack(spacing: 4) { if isLocked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundColor(DB.mutedText) }; Text("\(ep)").font(.system(size: 14, weight: isCurrent ? .bold : .regular)).foregroundColor(isCurrent ? .white : (isLocked ? DB.mutedText : .white.opacity(0.8))) }
                .frame(width: 52, height: 44).background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? DB.pink : (isLocked ? Color.white.opacity(0.05) : Color.white.opacity(0.12))))
        }
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
