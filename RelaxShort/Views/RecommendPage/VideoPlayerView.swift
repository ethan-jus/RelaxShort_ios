import SwiftUI
import AVKit
import Network
import Combine

// MARK: - 推荐页播放会话（迁移壳 — 委托给 ShortVideoPlayerEngine）

// MARK: - 推荐页播放会话（唯一 engine，无旧 pool/controller）

@MainActor final class RecommendSession: ObservableObject {
    /// 共享 engine — 由 PlayerCoordinator 提供，不再自己创建
    private weak var coordinator: PlayerCoordinator?
    private(set) var engine: ShortVideoPlayerEngine
    @Published var currentIndex = 0
    @Published var hasInitializedPool = false
    @Published var poolVersion = 0
    private var engineSink: AnyCancellable?

    /// Task26: 可播放条目列表，保存 dramaIndex → playableIndex 映射
    private(set) var playableItems: [RecommendPlayableItem] = []
    /// dramaIndex → playableIndex 快速查找
    private var dramaToPlayable: [Int: Int] = [:]

    init(engine: ShortVideoPlayerEngine) {
        self.engine = engine
        subscribe(to: engine)
    }

    func bind(to coordinator: PlayerCoordinator) {
        guard self.coordinator !== coordinator else { return }
        self.coordinator = coordinator
        guard engine !== coordinator.engine else { return }
        engine = coordinator.engine
        subscribe(to: coordinator.engine)
    }

    private func subscribe(to engine: ShortVideoPlayerEngine) {
        engineSink?.cancel()
        engineSink = engine.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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
            print("[PlayerKit] initializePool skipped reason=no-playable-items dramas=\(dramas.count)")
            return
        }
        playableItems = items
        dramaToPlayable = d2p
        let playerItems = items.map(\.item)
        if let coordinator {
            coordinator.claimForYou(items: playerItems, index: 0)
        } else {
            engine.prepare(items: playerItems, index: 0)
            engine.play()
        }
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

    func handleTransition(from old: Int, to new: Int, dramas: [DramaItem]) {
        guard old != new else { return }
        currentIndex = new
        // Task26: 使用 playable index 安全移动
        if let pIdx = playableIndex(for: new) {
            engine.move(to: pIdx)
        } else {
            print("[PlayerKit] handleTransition skipped dramaIndex=\(new) reason=no-playable-index")
        }
        poolVersion &+= 1
    }

    func cleanup() {}
}

// MARK: - 视频播放视图（engine 壳 — 不允许内部 new engine）

struct VideoPlayerView: View {
    let coverURL: String; let engine: ShortVideoPlayerEngine; let isCurrent: Bool
    var body: some View {
        ShortVideoPlayerView(player: isCurrent ? engine.currentPlayer : nil, coverURL: coverURL, engine: engine)
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
        guard let raw = videoURL,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            print("[PlayerKit] skip playable item id=\(id) reason=missing-video-url title=\(title) videoURL=\(videoURL ?? "nil")")
            return nil
        }
        let episodeNumber = max(1, currentEpisode)
        return PlayerMediaItem(
            id: PlayerMediaItem.stableID(dramaID: id, episodeNumber: episodeNumber),
            title: title, episodeNumber: episodeNumber,
            coverURL: coverURL, source: .mp4(url), resumeTime: nil
        )
    }
}
