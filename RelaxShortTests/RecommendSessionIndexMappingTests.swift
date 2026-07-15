import Foundation
import Testing
@testable import RelaxShort

// MARK: - TASK-0001-D: RecommendSession 索引映射测试

/// 辅助函数：构造可播放的 DramaItem
private func makeDrama(id: String, videoURL: String = "https://vod.example.com/\(UUID().uuidString).mp4", episode: Int = 1) -> DramaItem {
    DramaItem(
        id: id,
        title: "Test \(id)",
        coverURL: "",
        videoURL: videoURL,
        previewEpisodeID: nil,
        category: "都市",
        tags: [],
        viewCount: 1000,
        episodeCount: 60,
        currentEpisode: episode,
        synopsis: "...",
        isHot: false,
        isTrending: false,
        rating: 4.0,
        isVIPOnly: false,
        isPublicPreview: true,
        freeEpisodeRange: 1...3,
        isMemberOnly: false
    )
}

/// 辅助函数：构造不可播放的 DramaItem（VIP 保护）
private func makeProtectedDrama(id: String) -> DramaItem {
    var d = makeDrama(id: id)
    // 需要访问内部属性来设置 VIP；通过 Mock 数据模式
    return DramaItem(
        id: id, title: "VIP \(id)", coverURL: "",
        videoURL: "https://vod.example.com/\(id).mp4",
        previewEpisodeID: nil,
        category: "都市", tags: [],
        viewCount: 1000, episodeCount: 60, currentEpisode: 1, synopsis: "...",
        isHot: false, isTrending: false, rating: 4.0,
        isVIPOnly: true,
        isPublicPreview: false,
        freeEpisodeRange: 1...3,
        isMemberOnly: false
    )
}

@MainActor
struct RecommendSessionIndexMappingTests {

    // MARK: - Visibility Gate

    @Test("For You 不可见时首次加载只建立快照，不取得播放权")
    func hiddenInitialLoadDoesNotAutoplay() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator, playbackEnabled: false)

        session.replacePlaylist(dramas: [makeDrama(id: "hidden")])

        #expect(session.playableItems.count == 1)
        #expect(session.hasInitializedPool == false)
        #expect(coordinator.owner == nil)
        #expect(coordinator.engine.currentItem == nil)
    }

    @Test("切到 For You 后才初始化并开始播放")
    func becomingVisibleStartsPlayback() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator, playbackEnabled: false)
        let dramas = [makeDrama(id: "visible")]

        session.replacePlaylist(dramas: dramas)
        session.setPlaybackEnabled(true)
        session.initializePool(dramas: dramas)

        #expect(session.hasInitializedPool)
        #expect(coordinator.owner == .forYou)
        #expect(coordinator.engine.currentItem?.id == "visible-1")
    }

    // MARK: - Replace Tests

    @Test("同 count 整体 replace — playableItems/dramaToPlayable 完整重建")
    func sameCountReplaceRebuildsMapping() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let oldDramas = (0..<5).map { makeDrama(id: "old-\($0)") }
        session.replacePlaylist(dramas: oldDramas)
        let oldCount = session.playableItems.count
        let oldGen = session.feedGeneration

        let newDramas = (0..<5).map { makeDrama(id: "new-\($0)") }
        session.replacePlaylist(dramas: newDramas)

        #expect(session.playableItems.count == 5)
        #expect(session.feedGeneration > oldGen)
        #expect(session.playableItems[0].item.id.hasPrefix("new-0"))
        #expect(session.currentIndex == 0)
    }

    @Test("数量缩短 replace — 旧索引超出时安全复位")
    func shorterReplaceResetsIndex() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let oldDramas = (0..<10).map { makeDrama(id: "old-\($0)") }
        session.replacePlaylist(dramas: oldDramas)
        // 模拟滑到第 8 部
        session.currentIndex = 8

        let newDramas = (0..<3).map { makeDrama(id: "new-\($0)") }
        session.replacePlaylist(dramas: newDramas)

        #expect(session.currentIndex == 0) // 旧 dramaID 不存在，回到 0
        #expect(session.playableItems.count == 3)
    }

    @Test("按 dramaID 精确恢复到新 feed 位置")
    func restoreByDramaID() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        var oldDramas = (0..<5).map { makeDrama(id: "id-\($0)") }
        session.replacePlaylist(dramas: oldDramas)
        session.currentIndex = 3 // 停在 id-3

        // 新 feed 顺序不同，但 id-3 在第 1 位
        var newDramas: [DramaItem] = [
            makeDrama(id: "id-3"),
            makeDrama(id: "id-0"),
            makeDrama(id: "id-1"),
            makeDrama(id: "id-4"),
            makeDrama(id: "id-2"),
        ]
        session.replacePlaylist(dramas: newDramas)

        #expect(session.currentIndex == 0) // id-3 在 index 0
    }

    @Test("dramaID 不存在时回到 index 0")
    func dramaIDNotFoundResetsToZero() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let oldDramas = (0..<5).map { makeDrama(id: "old-\($0)") }
        session.replacePlaylist(dramas: oldDramas)
        session.currentIndex = 2

        let newDramas = (0..<3).map { makeDrama(id: "different-\($0)") }
        session.replacePlaylist(dramas: newDramas)

        #expect(session.currentIndex == 0)
    }

    // MARK: - Append Tests

    @Test("正常分页 append — 连续 startIndex")
    func normalPaginationAppend() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let page1 = (0..<5).map { makeDrama(id: "p1-\($0)") }
        session.replacePlaylist(dramas: page1)
        let gen = session.feedGeneration

        let page2 = (0..<5).map { makeDrama(id: "p2-\($0)") }
        let result = session.appendPlaylist(newDramas: page2, startDramaIndex: 5, generation: gen)

        #expect(result == true)
        #expect(session.playableItems.count == 10)
        #expect(session.playableItems[5].item.id.hasPrefix("p2-0"))
    }

    @Test("非连续 append 被拒绝")
    func nonConsecutiveAppendRejected() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let page1 = (0..<5).map { makeDrama(id: "p1-\($0)") }
        session.replacePlaylist(dramas: page1)
        let gen = session.feedGeneration

        let page2 = (0..<5).map { makeDrama(id: "p2-\($0)") }
        let result = session.appendPlaylist(newDramas: page2, startDramaIndex: 10, generation: gen)

        #expect(result == false)
        #expect(session.playableItems.count == 5) // 未变更
    }

    @Test("旧分页请求晚于新 replace 返回时被拒绝")
    func staleAppendRejectedAfterReplace() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let page1 = (0..<5).map { makeDrama(id: "p1-\($0)") }
        session.replacePlaylist(dramas: page1)
        let gen1 = session.feedGeneration

        // replace 新 feed
        let newDramas = (0..<3).map { makeDrama(id: "new-\($0)") }
        session.replacePlaylist(dramas: newDramas)

        // 旧 generation 的 append
        let page2 = (0..<5).map { makeDrama(id: "p2-\($0)") }
        let result = session.appendPlaylist(newDramas: page2, startDramaIndex: 5, generation: gen1)

        #expect(result == false)
        #expect(session.playableItems.count == 3) // replace 后的 3 条
    }

    // MARK: - Strict playableIndex

    @Test("不可播放目标不 fallback — 返回 nil")
    func unplayableTargetReturnsNil() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let dramas: [DramaItem] = [
            makeDrama(id: "a"),
            makeProtectedDrama(id: "b"),
            makeDrama(id: "c"),
        ]
        session.replacePlaylist(dramas: dramas)

        #expect(session.playableIndex(for: 0) != nil) // "a" is playable
        #expect(session.playableIndex(for: 1) == nil) // "b" is VIP, not playable
        #expect(session.playableIndex(for: 2) != nil) // "c" is playable
        #expect(session.playableIndex(for: 99) == nil) // out of bounds
    }

    @Test("attemptTransition 无映射时拒绝切换、不修改 currentIndex")
    func attemptTransitionRejectsUnplayable() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let dramas: [DramaItem] = [
            makeDrama(id: "a"),
            makeProtectedDrama(id: "b"),
        ]
        session.replacePlaylist(dramas: dramas)
        #expect(session.currentIndex == 0)

        let result = session.attemptTransition(from: 0, to: 1, autoplay: true)
        #expect(result == false)
        #expect(session.currentIndex == 0) // 未变
    }

    // MARK: - Series Ownership

    @Test("Series 持有播放权时 replace 只更新 session 快照，不抢占引擎")
    func replaceDuringSeriesOwnershipDoesNotClaimEngine() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        // 初始化 For You
        let oldDramas = (0..<5).map { makeDrama(id: "old-\($0)") }
        session.replacePlaylist(dramas: oldDramas)

        // Series 接管
        coordinator.beginSeries(dramaID: "series-1")

        // For You feed 重载
        let newDramas = (0..<10).map { makeDrama(id: "new-\($0)") }
        session.replacePlaylist(dramas: newDramas)

        // 引擎不应被 For You 抢占
        #expect(coordinator.owner == .series(dramaID: "series-1"))
        // Session 快照已更新
        #expect(session.playableItems.count == 10)
    }

    @Test("返回 For You 后使用新 playlist")
    func resumePlaybackUsesNewPlaylist() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        // 初始
        let oldDramas = (0..<5).map { makeDrama(id: "old-\($0)") }
        session.replacePlaylist(dramas: oldDramas)
        let oldFirstID = session.playableItems[0].item.id

        // Series 接管然后释放
        coordinator.beginSeries(dramaID: "series-1")
        coordinator.release(.series(dramaID: "series-1"))

        // feed 重载
        let newDramas = (0..<5).map { makeDrama(id: "new-\($0)") }
        session.replacePlaylist(dramas: newDramas)

        // resume 应使用新 playlist
        session.resumePlayback()
        let currentPlayableID = session.playableItems.first?.item.id ?? ""
        #expect(currentPlayableID.hasPrefix("new-0"))
    }

    // MARK: - Consistency

    @Test("UI dramaID / playable mediaID / engine mediaID 最终一致")
    func consistencyAfterReplace() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        let dramas = (0..<5).map { makeDrama(id: "test-\($0)") }
        session.replacePlaylist(dramas: dramas)

        // 切到 index 2
        let success = session.attemptTransition(from: 0, to: 2, autoplay: false)
        #expect(success)

        let uiDramaID = session.mediaID(for: session.currentIndex)
        #expect(uiDramaID?.hasPrefix("test-2") ?? false)

        // playableIndex 映射一致
        let pIdx = session.playableIndex(for: session.currentIndex)
        #expect(pIdx != nil)
        let playableItem = session.playableItems[pIdx!]
        #expect(playableItem.item.id.hasPrefix("test-2"))
    }

    @Test("保留当前媒体但重排 feed 时，Engine playlist 必须替换为新顺序")
    func replaceReordersEnginePlaylistWhenCurrentMediaSurvives() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        session.replacePlaylist(dramas: [
            makeDrama(id: "a"),
            makeDrama(id: "b"),
            makeDrama(id: "c")
        ])

        session.replacePlaylist(dramas: [
            makeDrama(id: "a"),
            makeDrama(id: "c"),
            makeDrama(id: "b")
        ])

        #expect(coordinator.engine.playlistItemIDs == ["a-1", "c-1", "b-1"])
        #expect(coordinator.engine.currentItem?.id == "a-1")
        #expect(coordinator.engine.currentIndex == 0)
    }

    @Test("replace 的首张卡不可播放时，UI 与 Engine 都定位到首个可播放卡")
    func replaceStartsAtFirstPlayableDrama() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        session.replacePlaylist(dramas: [
            makeProtectedDrama(id: "locked"),
            makeDrama(id: "playable")
        ])

        #expect(session.currentIndex == 1)
        #expect(session.playableIndex(for: session.currentIndex) == 0)
        #expect(coordinator.engine.currentItem?.id == "playable-1")
    }

    @Test("replace 成空 feed 时，For You 不得继续持有旧媒体")
    func emptyReplaceReleasesForYouMedia() {
        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        session.replacePlaylist(dramas: [makeDrama(id: "old")])
        session.replacePlaylist(dramas: [])

        #expect(session.playableItems.isEmpty)
        #expect(coordinator.owner == nil)
        #expect(coordinator.engine.currentItem == nil)
        #expect(coordinator.engine.playlistItemIDs.isEmpty)
    }

    @Test("同 URL 不同 dramaID 不得错误复用 — stableID 唯一")
    func sameURLDifferentDramaIDNotReused() {
        let sharedURL = "https://vod.example.com/shared.mp4"
        let dramaA = makeDrama(id: "drama-a", videoURL: sharedURL)
        let dramaB = makeDrama(id: "drama-b", videoURL: sharedURL)

        let coordinator = PlayerCoordinator()
        let session = RecommendSession(coordinator: coordinator)

        session.replacePlaylist(dramas: [dramaA, dramaB])

        // 两个应有不同 stableID
        let idA = session.playableItems[0].item.id
        let idB = session.playableItems[1].item.id
        #expect(idA != idB)
        #expect(idA.hasPrefix("drama-a"))
        #expect(idB.hasPrefix("drama-b"))
    }
}
