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
        let session = RecommendSession(engine: coordinator.engine)
        session.bind(to: coordinator)
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
    func seriesKeepsCurrentPlayerWhenSameEpisodeReceivesOfficialAsset() {
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
        let previewPlayer = coordinator.engine.currentPlayer
        coordinator.engine.progress = PlayerProgress(currentTime: 12, duration: 60, bufferProgress: 0.4)
        coordinator.claimSeries(drama: drama, items: [official], startIndex: 0, handoff: nil)

        #expect(coordinator.engine.currentPlayer === previewPlayer)
        #expect(coordinator.engine.currentItem?.source == preview.source)
        #expect(coordinator.engine.progress.currentTime == 12)
        #expect(coordinator.engine.wantsPlayback == true)
    }

    @Test
    func differentSeriesCannotReusePlayerOnlyBecauseMediaIDMatches() throws {
        let coordinator = PlayerCoordinator()
        let firstDrama = drama(id: "series-a")
        let secondDrama = drama(id: "series-b")
        let sharedIDItem = mediaItem(id: "episode-1")

        coordinator.claimSeries(
            drama: firstDrama,
            items: [sharedIDItem],
            startIndex: 0,
            handoff: nil
        )
        let firstPlayer = try #require(coordinator.engine.currentPlayer)

        coordinator.claimSeries(
            drama: secondDrama,
            items: [sharedIDItem],
            startIndex: 0,
            handoff: nil
        )

        #expect(coordinator.owner == .series(dramaID: "series-b"))
        #expect(coordinator.engine.currentPlayer !== firstPlayer)
    }

    @Test
    func pageSessionRejectsOldPageAndOldEpisodeTokens() {
        var firstPage = SeriesPlaybackSessionGate(
            dramaID: "series-a",
            episodeNumber: 1,
            mediaID: "series-a-1"
        )
        let firstEpisodeToken = firstPage.currentToken

        let secondEpisodeToken = firstPage.retarget(
            episodeNumber: 2,
            mediaID: "series-a-2"
        )
        let secondPage = SeriesPlaybackSessionGate(
            dramaID: "series-a",
            episodeNumber: 2,
            mediaID: "series-a-2"
        )

        #expect(!firstPage.accepts(firstEpisodeToken))
        #expect(firstPage.accepts(secondEpisodeToken))
        #expect(!secondPage.accepts(secondEpisodeToken))
    }

    @Test
    func playbackStateUsesActualPlayerStatusInsteadOfPlayIntent() {
        #expect(
            ShortVideoPlayerEngine.resolvePlaybackState(
                wantsPlayback: true,
                itemStatus: .unknown,
                timeControlStatus: .paused,
                isPlaybackLikelyToKeepUp: false,
                pausedState: .pausedBySystem
            ) == .preparing
        )
        #expect(
            ShortVideoPlayerEngine.resolvePlaybackState(
                wantsPlayback: true,
                itemStatus: .readyToPlay,
                timeControlStatus: .waitingToPlayAtSpecifiedRate,
                isPlaybackLikelyToKeepUp: false,
                pausedState: .pausedBySystem
            ) == .waitingNetwork
        )
        #expect(
            ShortVideoPlayerEngine.resolvePlaybackState(
                wantsPlayback: true,
                itemStatus: .readyToPlay,
                timeControlStatus: .playing,
                isPlaybackLikelyToKeepUp: true,
                pausedState: .pausedBySystem
            ) == .playing
        )
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
