import AVFoundation

// MARK: - 槽位上下文

/// 每个槽位持有的强引用上下文：player + item + 预加载任务
struct PlayerSlotContext {
    let player: AVPlayer
    let item: AVPlayerItem
    let mediaID: String
    let source: PlayerMediaSource
    let preparedAt: Date
    var readyToPlayAt: Date?
    var firstFrameAt: Date?
    var tasks: [Task<Void, Never>] = []
    var generation: Int = 0
}

// MARK: - 播放槽位

enum PlayerSlot: Int, Sendable {
    case previous = 0
    case current = 1
    case next = 2
}

// MARK: - 三槽播放器池

/// 固定三槽 AVPlayer 池。App 只有一套池；current 可见可听，previous/next 永远静音暂停。
/// 相邻项通过 AVPlayer.preroll 做原生缓冲，升为 current 时直接复用同一个 AVPlayer。
final class PlayerSlotPool {

    private var slots: [PlayerSlotContext?] = [nil, nil, nil]

    // MARK: - 准备槽位

    func prepare(
        item: PlayerMediaItem,
        slot: PlayerSlot,
        generation: Int,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) {
        cancel(slot)
        let idx = slot.rawValue
        let playerItem = slot == .current
            ? PlayerItemFactory.makePlaybackItem(from: item.source)
            : PlayerItemFactory.makeDirectItem(from: item.source)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = slot != .current
        if slot == .current {
            // 当前视频必须优先首帧速度；弱网卡顿由封面兜底、恢复状态机和后续预加载处理。
            player.currentItem?.preferredForwardBufferDuration = 0
            player.automaticallyWaitsToMinimizeStalling = false
        } else {
            player.currentItem?.preferredForwardBufferDuration = 1.0
            player.automaticallyWaitsToMinimizeStalling = false
        }
        slots[idx] = PlayerSlotContext(
            player: player, item: playerItem,
            mediaID: item.id, source: item.source,
            preparedAt: Date(), generation: generation
        )
        // 相邻槽只由共享池预加载：先确认可播，再 preroll 到系统认为可立即起播的状态。
        if slot != .current {
            let loadTask = Task(priority: .utility) { [weak player, asset = playerItem.asset] in
                guard let player else { return }
                guard !Task.isCancelled else { return }
                let isPlayable = (try? await asset.load(.isPlayable)) == true
                guard !Task.isCancelled, isPlayable else {
                    print("[PlayerKit] 相邻预加载失败 mediaID=\(item.id) slot=\(slot) 可播放=\(isPlayable)")
                    return
                }
                let playerReady = await Self.waitUntilReadyToPlay(player)
                guard !Task.isCancelled, playerReady, player.status == .readyToPlay else {
                    print("[PlayerKit] 相邻预加载跳过 preroll mediaID=\(item.id) slot=\(slot) playerStatus=\(player.status.rawValue)")
                    return
                }
                let prerollReady = await withCheckedContinuation { continuation in
                    player.preroll(atRate: 1) { success in
                        continuation.resume(returning: success)
                    }
                }
                guard !Task.isCancelled else { return }
                player.pause()
                print("[PlayerKit] 相邻预加载完成 mediaID=\(item.id) slot=\(slot) preroll=\(prerollReady)")
            }
            slots[idx]?.tasks.append(loadTask)
        }
        guard generation > 0 else { player.pause(); return }
        completion(.success(player))
    }

    // MARK: - 滑动切换槽位

    func move(
        from oldIndex: Int,
        to newIndex: Int,
        items: [PlayerMediaItem],
        generation: Int,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) {
        guard items.indices.contains(newIndex) else { return }
        if promotePrepared(item: items[newIndex], generation: generation, completion: completion) {
            print("[PlayerKit] 相邻预加载命中 idx=\(newIndex) 复用=true")
            return
        }
        print("[PlayerKit] 相邻预加载未命中 idx=\(newIndex) 方向=\(newIndex > oldIndex ? "next" : "previous")")
        prepare(item: items[newIndex], slot: .current, generation: generation, completion: completion)
    }

    /// 按稳定媒体 ID 提升预加载槽，不依赖页面自己的紧凑索引。
    /// Series 的播放源是渐进补齐的，使用 ID 才能安全复用下一集 preroll 结果。
    @discardableResult
    func promotePrepared(
        item: PlayerMediaItem,
        generation: Int,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) -> Bool {
        let current = slots[PlayerSlot.current.rawValue]?.player
        current?.pause()
        current?.isMuted = true

        if slots[PlayerSlot.next.rawValue]?.mediaID == item.id {
            cancelPreparation(.next)
            cancel(.previous)
            slots[0] = slots[1]
            slots[1] = slots[2]
            slots[2] = nil
        } else if slots[PlayerSlot.previous.rawValue]?.mediaID == item.id {
            cancelPreparation(.previous)
            cancel(.next)
            slots[2] = slots[1]
            slots[1] = slots[0]
            slots[0] = nil
        } else {
            return false
        }

        guard let promoted = slots[PlayerSlot.current.rawValue],
              promoted.player.currentItem?.status != .failed else {
            cancel(.current)
            return false
        }
        if promoted.player.status == .readyToPlay {
            promoted.player.cancelPendingPrerolls()
        }
        promoted.player.pause()
        promoted.player.isMuted = false
        completion(.success(promoted.player))
        return true
    }

    // MARK: - 当前页强制重建（超时/failed/fallback 时 engine 调用）

    func rebuildCurrent(
        item: PlayerMediaItem,
        generation: Int,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) {
        print("[PlayerKit] 重建当前播放器 媒体ID=\(item.id)")
        prepare(item: item, slot: .current, generation: generation, completion: completion)
    }

    // MARK: - 取消与清理

    func cancel(_ slot: PlayerSlot) {
        guard let ctx = slots[slot.rawValue] else { return }
        cancelPreparation(slot)
        ctx.player.pause()
        ctx.player.isMuted = true
        slots[slot.rawValue] = nil
    }

    /// 提升预加载槽前必须先取消其后台任务，防止迟到的 preroll 回调把当前播放器再次 pause。
    private func cancelPreparation(_ slot: PlayerSlot) {
        guard let ctx = slots[slot.rawValue] else { return }
        for task in ctx.tasks { task.cancel() }
        slots[slot.rawValue]?.tasks.removeAll()
        if ctx.player.status == .readyToPlay {
            ctx.player.cancelPendingPrerolls()
        }
    }

    /// AVPlayer.preroll 在 status 仍为 unknown 时会抛 Objective-C 异常，无法用 Swift catch 捕获。
    /// 因此先短暂等待 readyToPlay；超时只放弃 preroll，绝不影响主播放。
    private static func waitUntilReadyToPlay(_ player: AVPlayer) async -> Bool {
        for _ in 0..<40 {
            guard !Task.isCancelled else { return false }
            switch player.status {
            case .readyToPlay:
                return true
            case .failed:
                return false
            case .unknown:
                try? await Task.sleep(nanoseconds: 50_000_000)
            @unknown default:
                return false
            }
        }
        return false
    }

    func cancelAdjacent() {
        cancel(.previous)
        cancel(.next)
    }

    func cleanup() {
        for i in 0..<3 { cancel(PlayerSlot(rawValue: i)!) }
    }

    deinit { cleanup() }
}
