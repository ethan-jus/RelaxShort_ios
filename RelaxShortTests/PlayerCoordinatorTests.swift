import Foundation
import Testing
import AVFoundation
@testable import RelaxShort

@MainActor
struct PlayerCoordinatorTests {
    @Test
    func beginningSeriesImmediatelyOwnsAndDeactivatesPlayer() {
        let coordinator = PlayerCoordinator()
        coordinator.engine.play()

        coordinator.beginSeries(dramaID: "series-2")

        #expect(coordinator.owner == .series(dramaID: "series-2"))
        #expect(coordinator.engine.wantsPlayback == false)
    }

    @Test
    func releasingSeriesRevokesPlaybackIntentAndOwnership() {
        let coordinator = PlayerCoordinator()
        coordinator.beginSeries(dramaID: "series-2")
        coordinator.engine.play()

        coordinator.release(.series(dramaID: "series-2"))

        #expect(coordinator.owner == nil)
        #expect(coordinator.engine.wantsPlayback == false)
    }

    @Test
    func forYouCannotResumeWhileSeriesOwnsPlayer() {
        let coordinator = PlayerCoordinator()
        coordinator.beginSeries(dramaID: "series-2")

        coordinator.resumeForYou()

        #expect(coordinator.owner == .series(dramaID: "series-2"))
        #expect(coordinator.engine.wantsPlayback == false)
    }

    @Test
    func playbackCompletionRoutesToForYouOwner() {
        let coordinator = PlayerCoordinator()
        var completionCount = 0
        coordinator.setForYouPlaybackFinishedHandler {
            completionCount += 1
        }
        coordinator.claimForYou(items: [mediaItem(id: "series-1-1")], index: 0)

        coordinator.engine.onPlaybackFinished?()

        #expect(completionCount == 1)
    }

    @Test
    func playbackCompletionRoutesToCurrentSeriesOwner() {
        let coordinator = PlayerCoordinator()
        var completionCount = 0
        coordinator.beginSeries(dramaID: "series-2")
        coordinator.setSeriesPlaybackFinishedHandler(dramaID: "series-2") {
            completionCount += 1
        }

        coordinator.engine.onPlaybackFinished?()

        #expect(completionCount == 1)
    }

    @Test
    func releasedSeriesCannotReceiveLatePlaybackCompletion() {
        let coordinator = PlayerCoordinator()
        var completionCount = 0
        coordinator.beginSeries(dramaID: "series-2")
        coordinator.setSeriesPlaybackFinishedHandler(dramaID: "series-2") {
            completionCount += 1
        }
        coordinator.release(.series(dramaID: "series-2"))

        coordinator.engine.onPlaybackFinished?()

        #expect(completionCount == 0)
        #expect(coordinator.owner == nil)
    }

    @Test
    func returningToForYouReclaimsItsPlaylistAfterSeriesRelease() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)
        let drama = DramaItem(
            id: "series-1",
            title: "Series 1",
            coverURL: "https://example.com/cover.jpg",
            videoURL: "https://example.com/video.mp4",
            category: "Drama",
            tags: [],
            viewCount: 1,
            episodeCount: 1,
            currentEpisode: 1,
            synopsis: "",
            isHot: false,
            isTrending: false,
            rating: 0
        )
        session.initializePool(dramas: [drama])
        coordinator.beginSeries(dramaID: "series-2")
        coordinator.release(.series(dramaID: "series-2"))

        session.resumePlayback()

        #expect(coordinator.owner == .forYou)
        #expect(coordinator.engine.currentItem?.id == "series-1-1")
        #expect(coordinator.engine.wantsPlayback == true)
    }

    @Test
    func forYouPaginationCannotMutatePlaylistWhileSeriesOwnsPlayer() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)
        session.initializePool(dramas: [drama(id: "for-you-1")])
        coordinator.claimSeries(
            drama: drama(id: "series-2"),
            items: [mediaItem(id: "series-2-1")],
            startIndex: 0,
            handoff: nil
        )
        let seriesPlaylist = coordinator.engine.playlistItemIDs

        session.syncDramas([drama(id: "for-you-2")], startingAt: 1)

        #expect(coordinator.owner == .series(dramaID: "series-2"))
        #expect(coordinator.engine.playlistItemIDs == seriesPlaylist)
        #expect(coordinator.engine.currentItem?.id == "series-2-1")
    }

    @Test
    func forYouMoveCannotReplaceCurrentSeriesMedia() {
        let coordinator = PlayerCoordinator()
        coordinator.claimSeries(
            drama: drama(id: "series-2"),
            items: [mediaItem(id: "series-2-1")],
            startIndex: 0,
            handoff: nil
        )

        coordinator.moveForYou(to: 1, autoplay: true)

        #expect(coordinator.owner == .series(dramaID: "series-2"))
        #expect(coordinator.engine.currentItem?.id == "series-2-1")
    }

    @Test
    func releasingOwnerFullyDetachesCurrentMedia() {
        let coordinator = PlayerCoordinator()
        coordinator.claimForYou(items: [mediaItem(id: "for-you-1")], index: 0)
        let oldPlayer = coordinator.engine.currentPlayer

        coordinator.release(.forYou)

        #expect(oldPlayer?.timeControlStatus == .paused)
        #expect(coordinator.engine.currentPlayer == nil)
        #expect(coordinator.engine.currentItem == nil)
        #expect(coordinator.engine.playlistItemIDs.isEmpty)
        #expect(coordinator.engine.progress.currentTime == 0)
    }

    @Test
    func movingWithoutAutoplayKeepsNewMediaPaused() {
        let coordinator = PlayerCoordinator()
        coordinator.claimForYou(
            items: [mediaItem(id: "for-you-1"), mediaItem(id: "for-you-2")],
            index: 0
        )

        coordinator.moveForYou(to: 1, autoplay: false)

        #expect(coordinator.engine.currentItem?.id == "for-you-2")
        #expect(coordinator.engine.wantsPlayback == false)
        #expect(coordinator.engine.currentPlayer?.timeControlStatus == .paused)
    }

    @Test
    func seriesPrefetchUpdatesOnlyItsOwnSharedPlaylist() {
        let coordinator = PlayerCoordinator()
        let series = drama(id: "series-2")
        coordinator.claimSeries(
            drama: series,
            items: [mediaItem(id: "series-2-1")],
            startIndex: 0,
            handoff: nil
        )

        coordinator.updateSeriesPlaylist(
            dramaID: series.id,
            items: [mediaItem(id: "series-2-1"), mediaItem(id: "series-2-2")]
        )
        #expect(coordinator.engine.playlistItemIDs == ["series-2-1", "series-2-2"])

        coordinator.release(.series(dramaID: series.id))
        coordinator.claimForYou(items: [mediaItem(id: "for-you-1")], index: 0)
        coordinator.updateSeriesPlaylist(
            dramaID: series.id,
            items: [mediaItem(id: "series-2-1"), mediaItem(id: "series-2-2")]
        )
        #expect(coordinator.engine.playlistItemIDs == ["for-you-1"])
    }

    @Test
    func preparedAdjacentSlotIsSilentUntilPromoted() throws {
        let pool = PlayerSlotPool()
        defer { pool.cleanup() }
        let first = mediaItem(id: "for-you-1")
        let second = mediaItem(id: "for-you-2")
        var current: AVPlayer?
        var next: AVPlayer?

        pool.prepare(item: first, slot: .current, generation: 1) {
            current = try? $0.get()
        }
        pool.prepare(item: second, slot: .next, generation: 1) {
            next = try? $0.get()
        }
        let oldPlayer = try #require(current)
        let preparedPlayer = try #require(next)

        #expect(oldPlayer.isMuted == false)
        #expect(preparedPlayer.isMuted == true)

        var promoted: AVPlayer?
        pool.move(from: 0, to: 1, items: [first, second], generation: 2) {
            promoted = try? $0.get()
        }

        #expect(promoted === preparedPlayer)
        #expect(oldPlayer.timeControlStatus == .paused)
        #expect(oldPlayer.isMuted == true)
        #expect(preparedPlayer.isMuted == false)
    }

    @Test
    func seriesNavigationKeepsBackendPreviewEpisodeID() {
        var item = drama(id: "series-2")
        item.previewEpisodeID = "episode-2001"

        let route = SeriesPlayerNav(drama: item, startEpisode: 1)

        #expect(route.episodeID == "episode-2001")
    }

    @Test
    func protectedCardURLCannotBypassPlayEntitlementCheck() {
        var item = drama(id: "vip-series")
        item.isVIPOnly = true

        #expect(item.toPlayerMediaItem() == nil)
    }

    @Test
    func stalePlayerLayerCallbackDoesNotMarkCurrentMediaReady() {
        let engine = ShortVideoPlayerEngine()
        let stalePlayer = AVPlayer()

        engine.markReadyForDisplay(from: stalePlayer)

        #expect(engine.isReadyForDisplay == false)
    }

    @Test
    func seriesWithResumeTimeStillStartsPlaybackImmediately() {
        let coordinator = PlayerCoordinator()
        let drama = DramaItem(
            id: "series-2",
            title: "Series 2",
            coverURL: "https://example.com/cover.jpg",
            videoURL: "https://example.com/video.mp4",
            category: "Drama",
            tags: [],
            viewCount: 1,
            episodeCount: 1,
            currentEpisode: 1,
            synopsis: "",
            isHot: false,
            isTrending: false,
            rating: 0
        )

        coordinator.claimSeries(
            drama: drama,
            items: [mediaItem(id: "series-2-1")],
            startIndex: 0,
            handoff: nil,
            backendResumeTime: 12
        )

        #expect(coordinator.owner == .series(dramaID: "series-2"))
        #expect(coordinator.engine.wantsPlayback == true)
    }

    @Test
    func currentPlaybackDoesNotWaitForLargeBufferBeforeStarting() {
        let coordinator = PlayerCoordinator()
        coordinator.claimForYou(items: [mediaItem(id: "series-quick-1")], index: 0)

        #expect(coordinator.engine.currentPlayer?.automaticallyWaitsToMinimizeStalling == false)
        #expect(coordinator.engine.currentPlayer?.currentItem?.preferredForwardBufferDuration == 0)
    }

    @Test
    func seriesUpgradesCurrentSourceWhenSameEpisodeReceivesOfficialAsset() throws {
        let coordinator = PlayerCoordinator()
        let drama = DramaItem(
            id: "series-3",
            title: "Series 3",
            coverURL: "https://example.com/cover.jpg",
            videoURL: "https://example.com/preview.mp4",
            category: "Drama",
            tags: [],
            viewCount: 1,
            episodeCount: 1,
            currentEpisode: 1,
            synopsis: "",
            isHot: false,
            isTrending: false,
            rating: 0
        )
        let preview = PlayerMediaItem(
            id: "series-3-1",
            title: "Series 3",
            episodeNumber: 1,
            coverURL: "",
            source: .mp4(URL(string: "https://example.com/preview.mp4")!),
            resumeTime: nil
        )
        let official = PlayerMediaItem(
            id: "series-3-1",
            title: "Series 3",
            episodeNumber: 1,
            coverURL: "",
            source: .hlsWithFallback(
                masterURL: URL(string: "https://example.com/master.m3u8")!,
                fallbackMP4URL: URL(string: "https://example.com/official.mp4")!
            ),
            resumeTime: nil
        )

        coordinator.claimSeries(drama: drama, items: [preview], startIndex: 0, handoff: nil)
        let previewPlayer = try #require(coordinator.engine.currentPlayer)
        coordinator.engine.progress = PlayerProgress(currentTime: 12, duration: 60, bufferProgress: 0.4)
        coordinator.engine.markReadyForDisplay(from: previewPlayer)
        #expect(coordinator.engine.isReadyForDisplay == true)

        coordinator.claimSeries(drama: drama, items: [official], startIndex: 0, handoff: nil)

        #expect(coordinator.engine.currentPlayer === previewPlayer)
        #expect(coordinator.engine.currentItem?.source == official.source)
        #expect(coordinator.engine.progress.currentTime == 12)
        #expect(coordinator.engine.isReadyForDisplay == true)
        #expect(coordinator.engine.wantsPlayback == true)
    }

    @Test
    func beginningContentTransitionDetachesOldMediaAndResetsVisibleState() throws {
        let coordinator = PlayerCoordinator()
        coordinator.claimForYou(items: [mediaItem(id: "series-1-1")], index: 0)
        let oldPlayer = try #require(coordinator.engine.currentPlayer)
        oldPlayer.play()
        coordinator.engine.progress = PlayerProgress(
            currentTime: 12,
            duration: 60,
            bufferProgress: 0.4
        )
        #expect(coordinator.engine.progress.currentTime == 12)

        coordinator.engine.beginContentTransition(autoplay: true)
        coordinator.engine.play()

        #expect(oldPlayer.timeControlStatus == .paused)
        #expect(coordinator.engine.currentPlayer == nil)
        #expect(coordinator.engine.currentItem == nil)
        #expect(coordinator.engine.progress.currentTime == 0)
        #expect(coordinator.engine.progress.duration == 0)
        #expect(coordinator.engine.hasVisiblePlaybackStarted == false)
        #expect(coordinator.engine.wantsPlayback == true)
        #expect(coordinator.engine.state == .preparing)
    }

    @Test
    func newerSeriesEpisodeTransitionInvalidatesOlderPendingRequest() {
        let coordinator = PlayerCoordinator()
        coordinator.beginSeries(dramaID: "series-2")

        let firstToken = coordinator.beginSeriesEpisodeTransition(dramaID: "series-2")
        let secondToken = coordinator.beginSeriesEpisodeTransition(dramaID: "series-2")

        #expect(firstToken != nil)
        #expect(secondToken != nil)
        #expect(coordinator.isCurrentSeriesEpisodeTransition(
            dramaID: "series-2",
            token: secondToken
        ))
        #expect(!coordinator.isCurrentSeriesEpisodeTransition(
            dramaID: "series-2",
            token: firstToken
        ))
        #expect(coordinator.engine.currentPlayer == nil)
        #expect(coordinator.engine.wantsPlayback == true)
    }

    @Test
    func staleSeriesEpisodeTransitionCannotReplaceNewerTarget() throws {
        let coordinator = PlayerCoordinator()
        coordinator.beginSeries(dramaID: "series-2")
        let staleToken = try #require(
            coordinator.beginSeriesEpisodeTransition(dramaID: "series-2")
        )
        let currentToken = try #require(
            coordinator.beginSeriesEpisodeTransition(dramaID: "series-2")
        )
        let drama = DramaItem(
            id: "series-2",
            title: "Series 2",
            coverURL: "https://example.com/cover.jpg",
            category: "Drama",
            tags: [],
            viewCount: 1,
            episodeCount: 3,
            currentEpisode: 2,
            synopsis: "",
            isHot: false,
            isTrending: false,
            rating: 0
        )

        let acceptedCurrent = coordinator.commitSeriesEpisodeTransition(
            drama: drama,
            items: [mediaItem(id: "series-2-2")],
            startIndex: 0,
            handoff: nil,
            token: currentToken
        )
        let acceptedStale = coordinator.commitSeriesEpisodeTransition(
            drama: drama,
            items: [mediaItem(id: "series-2-1")],
            startIndex: 0,
            handoff: nil,
            token: staleToken
        )

        #expect(acceptedCurrent)
        #expect(!acceptedStale)
        #expect(coordinator.engine.currentItem?.id == "series-2-2")
    }

    @Test
    func movingForYouImmediatelySilencesTheDisplacedPlayer() throws {
        let engine = ShortVideoPlayerEngine()
        engine.prepare(
            items: [
                mediaItem(id: "series-1-1"),
                mediaItem(id: "series-2-1")
            ],
            index: 0
        )
        let oldPlayer = try #require(engine.currentPlayer)
        oldPlayer.play()
        #expect(oldPlayer.timeControlStatus != .paused)

        engine.move(to: 1)

        #expect(oldPlayer.timeControlStatus == .paused)
        #expect(engine.currentItem?.id == "series-2-1")
        #expect(engine.currentPlayer !== oldPlayer)
        #expect(engine.progress.currentTime == 0)
    }

    private func mediaItem(id: String) -> PlayerMediaItem {
        PlayerMediaItem(
            id: id,
            title: "Series",
            episodeNumber: 1,
            coverURL: "",
            source: .mp4(URL(string: "https://example.com/video.mp4")!),
            resumeTime: nil
        )
    }

    private func drama(id: String) -> DramaItem {
        DramaItem(
            id: id,
            title: id,
            coverURL: "https://example.com/cover.jpg",
            videoURL: "https://example.com/\(id).mp4",
            category: "Drama",
            tags: [],
            viewCount: 1,
            episodeCount: 2,
            currentEpisode: 1,
            synopsis: "",
            isHot: false,
            isTrending: false,
            rating: 0
        )
    }
}
