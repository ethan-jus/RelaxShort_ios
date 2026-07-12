import SwiftUI
import AVKit
import Network
import Combine

// MARK: - 推荐页播放会话（唯一 Coordinator / Engine）

@MainActor final class RecommendSession: ObservableObject {
    /// Coordinator 是播放权唯一入口；会话不允许脱离它直接管理播放列表。
    private let coordinator: PlayerCoordinator
    let engine: ShortVideoPlayerEngine
    @Published var currentIndex = 0
    @Published var hasInitializedPool = false
    @Published var poolVersion = 0
    private var engineSink: AnyCancellable?

    /// Task26: 可播放条目列表，保存 dramaIndex → playableIndex 映射
    private(set) var playableItems: [RecommendPlayableItem] = []
    /// dramaIndex → playableIndex 快速查找
    private var dramaToPlayable: [Int: Int] = [:]

    init(coordinator: PlayerCoordinator) {
        self.coordinator = coordinator
        self.engine = coordinator.engine
        subscribe(to: coordinator.engine)
    }

    private func subscribe(to engine: ShortVideoPlayerEngine) {
        engineSink?.cancel()
        engineSink = engine.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Task36A: 追加新剧集到播放器池，不中断当前播放。
    /// 只映射尚未在 dramaToPlayable 中的新 DramaItem，并同步 engine 内部 items。
    /// startingAt 必须使用追加数据在完整 dramas 数组中的真实起始下标，避免首屏或不可播放条目导致索引错位。
    func syncDramas(_ newDramas: [DramaItem], startingAt startDramaIndex: Int) {
        guard !newDramas.isEmpty else { return }
        var newItems: [PlayerMediaItem] = []
        for (offset, drama) in newDramas.enumerated() {
            let dIdx = startDramaIndex + offset
            guard dramaToPlayable[dIdx] == nil else { continue }
            guard let mediaItem = drama.toPlayerMediaItem() else { continue }
            let pIdx = playableItems.count + newItems.count
            playableItems.append(RecommendPlayableItem(id: mediaItem.id, dramaIndex: dIdx, item: mediaItem))
            dramaToPlayable[dIdx] = pIdx
            newItems.append(mediaItem)
        }
        guard !newItems.isEmpty else { return }
        coordinator.appendForYouItems(newItems)
        poolVersion &+= 1
    }

    func initializePool(dramas: [DramaItem]) {
        guard !dramas.isEmpty else { return }
        var items: [RecommendPlayableItem] = []
        var d2p: [Int: Int] = [:]
        for (dIdx, drama) in dramas.enumerated() {
            guard let mediaItem = drama.toPlayerMediaItem() else { continue }
            let pIdx = items.count
            items.append(RecommendPlayableItem(id: mediaItem.id, dramaIndex: dIdx, item: mediaItem))
            d2p[dIdx] = pIdx
        }
        guard !items.isEmpty else {
            print("[PlayerKit] 跳过初始化播放池 原因=没有可播放条目 剧集数=\(dramas.count)")
            return
        }
        playableItems = items
        dramaToPlayable = d2p
        let playerItems = items.map(\.item)
        // Task36B-2: 开始 For You 播放诊断追踪
        engine.startPlaybackTrace(PlaybackDiagnosticsTrace(scene: "for_you", targetIndex: 0))
        coordinator.claimForYou(items: playerItems, index: 0)
        hasInitializedPool = true; poolVersion &+= 1
    }

    /// 将 drama index 映射为 playable index，供 engine.move 使用。
    /// 如果目标 drama 不可播放，返回最近的合法 playable index 或 nil。
    func playableIndex(for dramaIndex: Int) -> Int? {
        if let direct = dramaToPlayable[dramaIndex] { return direct }
        // 不可播放时找最近的合法索引
        let sorted = dramaToPlayable.keys.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if dramaIndex < first { return 0 }
        if dramaIndex > last { return playableItems.count - 1 }
        // 二分查找最近
        var best = first
        for k in sorted { if k <= dramaIndex { best = k } else { break } }
        return dramaToPlayable[best]
    }

    func handleTransition(from old: Int, to new: Int, dramas: [DramaItem], autoplay: Bool) {
        guard old != new else { return }
        currentIndex = new
        // Task26: 使用 playable index 安全移动
        if let pIdx = playableIndex(for: new) {
            coordinator.moveForYou(to: pIdx, autoplay: autoplay)
        } else {
            print("[PlayerKit] 跳过推荐流切换 剧集索引=\(new) 原因=没有可播放索引")
        }
        poolVersion &+= 1
    }

    func resumePlayback() {
        guard hasInitializedPool,
              !playableItems.isEmpty,
              let playableIndex = playableIndex(for: currentIndex) else { return }

        if coordinator.owner == .forYou {
            coordinator.resumeForYou()
        } else {
            coordinator.claimForYou(items: playableItems.map(\.item), index: playableIndex)
        }
    }

    func pausePlayback() {
        coordinator.pauseForYou()
    }
}

// MARK: - DramaItem → PlayerMediaItem 映射

/// Task26: 可播放条目与原始 drama index 的映射，避免 compactMap 跳过无 URL 卡片后索引错位。
struct RecommendPlayableItem: Identifiable, Hashable {
    let id: String
    let dramaIndex: Int
    let item: PlayerMediaItem
}

extension PlayerMediaItem {
    /// 统一稳定 ID：For You 和 Series 使用同一规则
    static func stableID(dramaID: String, episodeNumber: Int) -> String {
        "\(dramaID)-\(episodeNumber)"
    }
}

extension DramaItem {
    /// Task24 R2: 可失败构造，禁止 about:blank 进入 PlayerKit。
    /// 仅当 videoURL 为 http/https scheme 时才创建 PlayerMediaItem，
    /// 否则打印诊断日志返回 nil，由调用方 compactMap 过滤。
    func toPlayerMediaItem() -> PlayerMediaItem? {
        let episodeNumber = max(1, currentEpisode)
        let publicPreviewAllowed = isPublicPreview
            && !isVIPOnly
            && !isMemberOnly
            && (freeEpisodeRange?.contains(episodeNumber) ?? true)
        guard publicPreviewAllowed else {
            print("[PlayerKit] 跳过受保护卡片直链 id=\(id) 集数=\(episodeNumber)，等待 /play 权益校验")
            return nil
        }
        guard let raw = videoURL,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            print("[PlayerKit] 跳过可播放条目 ID=\(id) 原因=缺少有效视频地址 标题=\(title) 视频地址=\(videoURL ?? "无")")
            return nil
        }
        return PlayerMediaItem(
            id: PlayerMediaItem.stableID(dramaID: id, episodeNumber: episodeNumber),
            title: title, episodeNumber: episodeNumber,
            coverURL: coverURL, source: .mp4(url), resumeTime: nil
        )
    }
}
