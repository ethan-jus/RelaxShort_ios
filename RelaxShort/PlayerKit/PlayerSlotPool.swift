import AVFoundation

// MARK: - 槽位上下文

/// 每个槽位持有的强引用上下文：player + item + resourceLoaderDelegate + tasks
struct PlayerSlotContext {
    let player: AVPlayer
    let item: AVPlayerItem
    let resourceLoaderDelegate: PlayerResourceLoaderDelegate?
    let mediaID: String
    let source: PlayerMediaSource
    let isManagedCacheItem: Bool
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

/// 固定三槽 AVPlayer 池，带 PlayerSlotContext 强引用 delegate
/// 预加载升 current 优先复用播放器，只在超时/failed/fallback 时重建
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
        let managed = slot == .current
            ? PlayerItemFactory.makePlaybackItem(from: item.source)
            : PlayerItemFactory.makeDirectItem(from: item.source)
        let player = AVPlayer(playerItem: managed.item)
        if slot == .current {
            // 当前视频必须优先首帧速度；弱网卡顿由封面兜底、恢复状态机和后续预加载处理。
            player.currentItem?.preferredForwardBufferDuration = 0
            player.automaticallyWaitsToMinimizeStalling = false
        } else {
            player.currentItem?.preferredForwardBufferDuration = 1.0
            player.automaticallyWaitsToMinimizeStalling = false
        }
        slots[idx] = PlayerSlotContext(
            player: player, item: managed.item,
            resourceLoaderDelegate: managed.resourceLoaderDelegate,
            mediaID: item.id, source: item.source,
            isManagedCacheItem: managed.resourceLoaderDelegate != nil,
            preparedAt: Date(), generation: generation
        )
        // preload slot：异步加载 isPlayable/duration，捕获真实结果
        if slot != .current {
            let loadTask = Task(priority: .utility) { [asset = managed.item.asset] in
                guard !Task.isCancelled else { return }
                let isPlayable = (try? await asset.load(.isPlayable)) == true
                let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
                guard !Task.isCancelled else { return }
                if isPlayable, duration > 0 {
                    print("[PlayerKit] preload metadata ready mediaID=\(item.id) slot=\(slot) duration=\(String(format: "%.1f", duration))s playable=\(isPlayable)")
                } else {
                    print("[PlayerKit] preload metadata failed mediaID=\(item.id) slot=\(slot) playable=\(isPlayable) duration=\(String(format: "%.1f", duration))s")
                }
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
        if newIndex > oldIndex {
            cancel(.previous); slots[0]?.player.pause(); slots[0] = nil
            slots[0] = slots[1]; slots[1] = slots[2]; slots[2] = nil
        } else {
            cancel(.next); slots[2]?.player.pause(); slots[2] = nil
            slots[2] = slots[1]; slots[1] = slots[0]; slots[0] = nil
        }

        if let ctx = slots[1] {
            guard ctx.mediaID == items[newIndex].id else {
                print("[PlayerKit] preload miss idx=\(newIndex) reason=id-mismatch")
                prepare(item: items[newIndex], slot: .current, generation: generation, completion: completion)
                return
            }

            let itemStatus = ctx.player.currentItem?.status
            if itemStatus == .failed {
                print("[PlayerKit] preload discard idx=\(newIndex) reason=failed-item")
                prepare(item: items[newIndex], slot: .current, generation: generation, completion: completion)
            } else if ctx.resourceLoaderDelegate == nil {
                // 直连 current → 直接复用；failed item 已在上方剔除。
                print("[PlayerKit] preload hit idx=\(newIndex) slot=current reuse=true")
                completion(.success(ctx.player))
            } else {
                // 缓存代理 item 目前只做后台预热，不能直接升主播放链路。
                // AVPlayer 可能只请求 0-1 探测字节，直接复用会把 current 变成 failed item。
                print("[PlayerKit] preload warm idx=\(newIndex) slot=current rebuild=direct")
                prepare(item: items[newIndex], slot: .current, generation: generation, completion: completion)
            }
        } else {
            print("[PlayerKit] preload miss idx=\(newIndex) reason=empty-slot")
            prepare(item: items[newIndex], slot: .current, generation: generation, completion: completion)
        }
    }

    // MARK: - 当前页强制重建（超时/failed/fallback 时 engine 调用）

    func rebuildCurrent(
        item: PlayerMediaItem,
        generation: Int,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) {
        print("[PlayerKit] current rebuild reason=\(item.id)")
        prepare(item: item, slot: .current, generation: generation, completion: completion)
    }

    // MARK: - 取消与清理

    func cancel(_ slot: PlayerSlot) {
        guard let ctx = slots[slot.rawValue] else { return }
        ctx.player.pause()
        for task in ctx.tasks { task.cancel() }
        slots[slot.rawValue] = nil
    }

    func cleanup() {
        for i in 0..<3 { cancel(PlayerSlot(rawValue: i)!) }
    }

    deinit { cleanup() }
}
