import SwiftUI

struct OfflineDownloadsView: View {
    @StateObject private var manager = OfflineDownloadManager.shared
    @State private var isManaging = false
    @State private var playbackItem: OfflineDownloadItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                storageSummary
                    .padding(.top, 18)

                if manager.activeItems.isEmpty && completedSeries.isEmpty {
                    emptyState
                        .padding(.top, 120)
                } else {
                    if !manager.activeItems.isEmpty {
                        activeSection
                            .padding(.top, 38)
                    }

                    if !completedSeries.isEmpty {
                        completedSection
                            .padding(.top, manager.activeItems.isEmpty ? 38 : 28)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(DB.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            navigationHeader
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .background(DB.black)
        }
        .interactivePopGestureEnabled()
        .navigationDestination(item: $playbackItem) { item in
            OfflinePlaybackView(item: item)
        }
    }

    private var navigationHeader: some View {
        ZStack {
            Text("downloads.title".localized)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            HStack {
                CompactSecondaryBackButton { dismiss() }
                Spacer()
                if !manager.items.isEmpty {
                    Button(isManaging ? "common.done".localized : "downloads.manage".localized) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isManaging.toggle()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DT.logoRed)
                    .frame(minWidth: 44, minHeight: 38, alignment: .trailing)
                }
            }
        }
        .frame(height: 46)
    }

    private var storageSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("downloads.used".localized)
                    .font(.system(size: 14))
                    .foregroundColor(DB.mutedText)
                Text(storageText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Label("downloads.vip_space".localized, systemImage: "diamond.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DT.coinGold)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DB.divider)
                    Capsule()
                        .fill(DT.logoRed)
                        .frame(
                            width: max(
                                manager.storageFraction > 0 ? 5 : 0,
                                proxy.size.width * manager.storageFraction
                            )
                        )
                }
            }
            .frame(height: 5)

            Text(
                "downloads.available".localizedFormat(
                    byteString(manager.availableBytes)
                )
            )
            .font(.system(size: 12))
            .foregroundColor(DB.mutedText)
        }
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("downloads.downloading".localized)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button("downloads.pause_all".localized) {
                    manager.pauseAll()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DT.logoRed)
            }

            ForEach(manager.activeItems) { item in
                activeRow(item)
                if item.id != manager.activeItems.last?.id {
                    divider
                }
            }
        }
    }

    private func activeRow(_ item: OfflineDownloadItem) -> some View {
        HStack(spacing: 16) {
            CoverImageView(
                url: item.coverURL,
                cornerRadius: 8,
                width: 90,
                height: 126
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(item.dramaTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(
                    "downloads.episode_progress".localizedFormat(
                        item.episodeNumber,
                        item.totalEpisodes
                    )
                )
                .font(.system(size: 13))
                .foregroundColor(DB.mutedText)

                HStack(spacing: 10) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DB.divider)
                            Capsule()
                                .fill(DT.logoRed)
                                .frame(width: proxy.size.width * item.progress)
                        }
                    }
                    .frame(height: 4)

                    Text("\(Int(item.progress * 100))%")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DB.mutedText)
                        .frame(width: 38, alignment: .trailing)
                }

                Text(activeDetail(item))
                    .font(.system(size: 12))
                    .foregroundColor(
                        item.status == .failed ? DT.logoRed : DB.mutedText
                    )
                    .lineLimit(1)
            }

            Button {
                manager.togglePause(for: item.id)
            } label: {
                Image(systemName: activeActionIcon(item))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DT.logoRed)
                    .frame(width: 42, height: 42)
                    .background(DB.panel.opacity(0.82))
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(DB.divider, lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activeActionLabel(item))

            if isManaging {
                deleteButton {
                    manager.remove(item.id)
                }
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("downloads.downloaded".localized)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            ForEach(completedSeries) { series in
                HStack(spacing: 16) {
                    CoverImageView(
                        url: series.coverURL,
                        cornerRadius: 8,
                        width: 84,
                        height: 112
                    )

                    VStack(alignment: .leading, spacing: 9) {
                        Text(series.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(
                            "downloads.downloaded_episodes".localizedFormat(
                                series.items.count
                            )
                        )
                        .font(.system(size: 13))
                        .foregroundColor(DB.mutedText)
                        Text(byteString(series.bytes))
                            .font(.system(size: 13))
                            .foregroundColor(DB.mutedText)
                    }

                    Spacer()

                    if isManaging {
                        deleteButton {
                            manager.removeSeries(series.id)
                        }
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DB.mutedText)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isManaging,
                          let playable = series.items
                            .sorted(by: { $0.episodeNumber > $1.episodeNumber })
                            .first,
                          manager.localURL(for: playable) != nil else { return }
                    playbackItem = playable
                }

                if series.id != completedSeries.last?.id {
                    divider
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(DB.mutedText)
            Text("downloads.empty_title".localized)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text("downloads.empty_detail".localized)
                .font(.system(size: 13))
                .foregroundColor(DB.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(DB.divider)
            .frame(height: 0.5)
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DT.logoRed)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("common.delete".localized)
    }

    private var completedSeries: [OfflineSeriesGroup] {
        let grouped = Dictionary(grouping: manager.completedItems, by: \.dramaID)
        return grouped.compactMap { dramaID, items in
            guard let first = items.first else { return nil }
            return OfflineSeriesGroup(
                id: dramaID,
                title: first.dramaTitle,
                coverURL: first.coverURL,
                items: items,
                bytes: items.reduce(0) { $0 + $1.downloadedBytes },
                updatedAt: items.map(\.updatedAt).max() ?? first.updatedAt
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var storageText: String {
        "\(byteString(manager.usedBytes)) / \(byteString(OfflineDownloadManager.maximumBytes))"
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func activeDetail(_ item: OfflineDownloadItem) -> String {
        switch item.status {
        case .paused:
            return "downloads.paused".localized
        case .failed:
            return item.errorMessage ?? "downloads.failed".localized
        case .queued:
            return "downloads.waiting".localized
        case .downloading:
            return item.bytesPerSecond > 0
                ? "\(byteString(item.bytesPerSecond))/s"
                : "downloads.preparing".localized
        case .completed:
            return byteString(item.downloadedBytes)
        }
    }

    private func activeActionIcon(_ item: OfflineDownloadItem) -> String {
        switch item.status {
        case .downloading, .queued:
            return "pause.fill"
        case .paused, .failed:
            return "play.fill"
        case .completed:
            return "checkmark"
        }
    }

    private func activeActionLabel(_ item: OfflineDownloadItem) -> String {
        switch item.status {
        case .downloading, .queued:
            return "downloads.pause".localized
        case .paused, .failed:
            return "downloads.resume".localized
        case .completed:
            return "downloads.completed".localized
        }
    }
}

private struct OfflineSeriesGroup: Identifiable {
    let id: String
    let title: String
    let coverURL: String
    let items: [OfflineDownloadItem]
    let bytes: Int64
    let updatedAt: Date
}

private struct OfflinePlaybackView: View {
    let item: OfflineDownloadItem
    @EnvironmentObject private var playerCoordinator: PlayerCoordinator
    @Environment(\.dismiss) private var dismiss

    private var ownerID: String { "offline-\(item.dramaID)" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShortVideoPlayerView(
                player: playerCoordinator.engine.currentPlayer,
                coverURL: item.coverURL,
                engine: playerCoordinator.engine
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                if playerCoordinator.engine.state == .pausedByUser {
                    playerCoordinator.engine.play()
                } else {
                    playerCoordinator.engine.pause(reason: .user)
                }
            }

            HStack {
                CompactSecondaryBackButton { dismiss() }
                Spacer()
                Text(
                    "downloads.offline_episode".localizedFormat(
                        item.episodeNumber
                    )
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(.black.opacity(0.48))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(DB.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
        .onAppear(perform: startPlayback)
        .onDisappear {
            playerCoordinator.release(.series(dramaID: ownerID))
        }
    }

    private func startPlayback() {
        guard let localURL = OfflineDownloadManager.shared.localURL(for: item) else {
            return
        }
        let drama = DramaItem(
            id: ownerID,
            title: item.dramaTitle,
            coverURL: item.coverURL,
            category: "",
            tags: [],
            viewCount: 0,
            episodeCount: item.totalEpisodes,
            currentEpisode: item.episodeNumber,
            synopsis: "",
            isHot: false,
            isTrending: false,
            rating: 0
        )
        let media = PlayerMediaItem(
            id: "offline-\(item.episodeID)",
            title: item.dramaTitle,
            episodeNumber: item.episodeNumber,
            coverURL: item.coverURL,
            source: .mp4(localURL),
            resumeTime: nil,
            allowsPersistentCache: false
        )
        playerCoordinator.claimSeries(
            drama: drama,
            items: [media],
            startIndex: 0,
            handoff: nil
        )
    }
}
