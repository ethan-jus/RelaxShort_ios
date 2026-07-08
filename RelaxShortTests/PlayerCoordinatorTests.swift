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
}
