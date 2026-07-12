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

    /// 可播放条目列表，保存 dramaIndex → playableIndex 映射
    private(set) var playableItems: [RecommendPlayableItem] = []
    /// dramaIndex → playableIndex 快速查找
    private var dramaToPlayable: [Int: Int] = [:]

    /// TASK-0001-D: feed generation — replace 递增，append 绑定发起时 generation
    private(set) var feedGeneration: Int = 0
    /// 下次 append 合法的起始 dramaIndex
    private var nextAppendDramaIndex: Int = 0

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

    // MARK: - 整体替换（feed 重载、刷新、首次加载）

    /// 原子替换全部播放列表。优先按当前 dramaID 在新 feed 中恢复到对应索引，
    /// 找不到则回到 index 0。只在 For You 持有播放权或未初始化时提交引擎；
    /// Series 持有播放权时仅更新 session 快照。
    func replacePlaylist(dramas: [DramaItem]) {
        feedGeneration &+= 1
        let gen = feedGeneration
        nextAppendDramaIndex = dramas.count

        // 在局部变量中完整构建，验证后再提交
        var newPlayable: [RecommendPlayableItem] = []
        var newD2P: [Int: Int] = [:]

        for (dIdx, drama) in dramas.enumerated() {
            guard let mediaItem = drama.toPlayerMediaItem() else { continue }
            let pIdx = newPlayable.count
            newPlayable.append(
                RecommendPlayableItem(
                    id: mediaItem.id,
                    dramaID: drama.id,
                    dramaIndex: dIdx,
                    item: mediaItem
                )
            )
            newD2P[dIdx] = pIdx
        }

        // 优先按当前 dramaID 精确恢复索引
        let previousDramaID = currentDramaID()
        let targetDramaIndex: Int
        if let previousDramaID,
           let matched = newPlayable.first(where: { $0.dramaID == previousDramaID }) {
            targetDramaIndex = matched.dramaIndex
        } else {
            targetDramaIndex = 0
        }

        if newPlayable.isEmpty {
            playableItems = []
            dramaToPlayable = [:]
            currentIndex = 0
            nextAppendDramaIndex = 0
            hasInitializedPool = false
            if coordinator.owner == .forYou {
                coordinator.release(.forYou)
            }
            poolVersion &+= 1
            log("replacePlaylist gen=\(gen) 无可用播放条目 count=\(dramas.count)")
            return
        }

        // 目标必须是实际可播放的 feed 卡片；不允许 UI 停在锁集卡、Engine 却播放别的媒体。
        let safeTarget = newD2P[targetDramaIndex] == nil
            ? newPlayable[0].dramaIndex
            : targetDramaIndex
        guard let playableIdx = newD2P[safeTarget] else { return }

        // 原子提交 Session 映射。随后由 Coordinator 同步替换 Engine 的完整 playlist。
        playableItems = newPlayable
        dramaToPlayable = newD2P
        currentIndex = safeTarget
        let playerItems = newPlayable.map(\.item)

        log("replacePlaylist gen=\(gen) feedCount=\(dramas.count) playableCount=\(newPlayable.count) targetDrama=\(safeTarget) targetPlayable=\(playableIdx)")

        if !hasInitializedPool {
            engine.startPlaybackTrace(PlaybackDiagnosticsTrace(scene: "for_you", targetIndex: 0))
            coordinator.replaceForYouPlaylist(items: playerItems, index: playableIdx, autoplay: true)
            hasInitializedPool = true
        } else if coordinator.owner == .forYou {
            coordinator.replaceForYouPlaylist(items: playerItems, index: playableIdx, autoplay: true)
        }
        // Series 持有播放权时不提交引擎，只更新 session 快照

        poolVersion &+= 1
    }

    // MARK: - 分页追加

    /// 分页追加新剧集。校验 generation 匹配 + startIndex 连续。
    /// 旧 generation 或非连续 startIndex 的请求直接丢弃。
    func appendPlaylist(newDramas: [DramaItem], startDramaIndex: Int, generation: Int) -> Bool {
        guard generation == feedGeneration else {
            log("appendPlaylist 被拒绝 gen不匹配 请求gen=\(generation) 当前gen=\(feedGeneration)")
            return false
        }
        guard startDramaIndex == nextAppendDramaIndex else {
            log("appendPlaylist 被拒绝 startIndex不连续 请求start=\(startDramaIndex) 期望start=\(nextAppendDramaIndex)")
            return false
        }
        guard !newDramas.isEmpty else { return false }

        var newItems: [PlayerMediaItem] = []
        for (offset, drama) in newDramas.enumerated() {
            let dIdx = startDramaIndex + offset
            guard dramaToPlayable[dIdx] == nil else { continue }
            guard let mediaItem = drama.toPlayerMediaItem() else { continue }
            let pIdx = playableItems.count + newItems.count
            playableItems.append(
                RecommendPlayableItem(
                    id: mediaItem.id,
                    dramaID: drama.id,
                    dramaIndex: dIdx,
                    item: mediaItem
                )
            )
            dramaToPlayable[dIdx] = pIdx
            newItems.append(mediaItem)
        }

        nextAppendDramaIndex = startDramaIndex + newDramas.count
        guard !newItems.isEmpty else {
            log("appendPlaylist gen=\(generation) start=\(startDramaIndex) 无可播放新条目")
            return false
        }

        log("appendPlaylist gen=\(generation) start=\(startDramaIndex) newPlayable=\(newItems.count) totalPlayable=\(playableItems.count)")

        coordinator.appendForYouItems(newItems)
        poolVersion &+= 1
        return true
    }

    // MARK: - 严格 playableIndex（无 fallback）

    /// 严格映射：dramaIndex → playableIndex。找不到返回 nil，禁止 fallback。
    func playableIndex(for dramaIndex: Int) -> Int? {
        return dramaToPlayable[dramaIndex]
    }

    /// 根据 dramaIndex 查询对应的 mediaID（供诊断日志使用）。
    func mediaID(for dramaIndex: Int) -> String? {
        guard let pIdx = dramaToPlayable[dramaIndex],
              playableItems.indices.contains(pIdx) else { return nil }
        return playableItems[pIdx].item.id
    }

    /// 当前 dramaIndex 对应的 dramaID（供 replace 时精确恢复）。
    private func currentDramaID() -> String? {
        guard let pIdx = dramaToPlayable[currentIndex],
              playableItems.indices.contains(pIdx) else { return nil }
        return playableItems[pIdx].dramaID
    }

    // MARK: - 受控 transition

    /// 受控切页：先校验目标 dramaIndex 可播放，再提交 Engine。
    /// 成功返回 true，无可播放映射返回 false（不修改 currentIndex，不提交 Engine）。
    func attemptTransition(from old: Int, to new: Int, autoplay: Bool) -> Bool {
        guard old != new else { return true }

        guard let pIdx = playableIndex(for: new) else {
            log("attemptTransition 拒绝 目标drama=\(new) 无可播放映射 dramaToPlayable.keys=\(dramaToPlayable.keys.sorted())")
            return false
        }

        let oldMediaID = mediaID(for: old) ?? "nil"
        let newMediaID = mediaID(for: new) ?? "nil"

        guard coordinator.moveForYou(
            to: pIdx,
            expectedMediaID: newMediaID,
            autoplay: autoplay
        ) else {
            log("attemptTransition 拒绝：Engine playlist 与 UI 映射不一致")
            return false
        }

        currentIndex = new
        poolVersion &+= 1

        log("attemptTransition from=\(old)→\(new) fromID=\(oldMediaID) toID=\(newMediaID) playableIdx=\(pIdx)")
        return true
    }

    // MARK: - 生命周期

    func initializePool(dramas: [DramaItem]) {
        replacePlaylist(dramas: dramas)
    }

    /// 列表为空时重建（用于 loadData 全量刷新后的首次 init）
    /// 已替换为 replacePlaylist 调用。保留以兼容原有调用方。
    func handleTransition(from old: Int, to new: Int, dramas: [DramaItem], autoplay: Bool) {
        _ = attemptTransition(from: old, to: new, autoplay: autoplay)
    }

    func resumePlayback() {
        guard hasInitializedPool,
              !playableItems.isEmpty,
              let playableIdx = playableIndex(for: currentIndex) else { return }

        let playerItems = playableItems.map(\.item)

        if coordinator.owner == .forYou {
            coordinator.resumeForYou()
        } else {
            coordinator.claimForYou(items: playerItems, index: playableIdx)
        }
    }

    func pausePlayback() {
        coordinator.pauseForYou()
    }

    // MARK: - 同步旧 drama 到新 session（move 本地复用的轻量版本）

    /// 已弃用：由 replacePlaylist + appendPlaylist 替代。
    /// 保留以兼容 RecommendView 中现有的 onChange(dramas.count) → syncDramas 调用。
    /// TASK-0001-D 中 RecommendView 不再直接调此方法。
    @available(*, deprecated, message: "使用 appendPlaylist(newDramas:startDramaIndex:generation:) 替代")
    func syncDramas(_ newDramas: [DramaItem], startingAt startDramaIndex: Int) {
        _ = appendPlaylist(newDramas: newDramas, startDramaIndex: startDramaIndex, generation: feedGeneration)
    }

    // MARK: - 诊断

    /// 输出完整诊断信息（供日志使用）
    func diagnostics() -> String {
        let uiDramaID = mediaID(for: currentIndex) ?? "nil"
        let engMediaID = engine.currentItem?.id ?? "nil"
        let pIdx = playableIndex(for: currentIndex)
        return "gen=\(feedGeneration) currentIndex=\(currentIndex) uiDramaID=\(uiDramaID) playableIdx=\(pIdx.map(String.init) ?? "nil") engMediaID=\(engMediaID) feedCount=\(playableItems.count) nextAppend=\(nextAppendDramaIndex)"
    }

    private func log(_ msg: String) {
        #if DEBUG
        print("[RecommendSession] \(msg)")
        #endif
    }
}

// MARK: - DramaItem → PlayerMediaItem 映射

/// Task26: 可播放条目与原始 drama index 的映射，避免 compactMap 跳过无 URL 卡片后索引错位。
struct RecommendPlayableItem: Identifiable, Hashable {
    let id: String
    /// UI drama 的稳定业务身份；不从 PlayerMediaItem.id 的字符串格式反推。
    let dramaID: String
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
