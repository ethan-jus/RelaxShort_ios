import AVFoundation

// MARK: - 槽位上下文

/// 每个槽位持有的强引用上下文：player + item + resourceLoaderDelegate + tasks
struct PlayerSlotContext {
    let player: AVPlayer
    let item: AVPlayerItem
    let resourceLoaderDelegate: PlayerResourceLoaderDelegate?
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
/// 支持 generation token + tasks 取消
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

        let managed = PlayerItemFactory.makeManagedItem(from: item.source)
        let player = AVPlayer(playerItem: managed.item)
        slots[idx] = PlayerSlotContext(
            player: player,
            item: managed.item,
            resourceLoaderDelegate: managed.resourceLoaderDelegate,
            generation: generation
        )

        guard generation > 0 else {
            player.pause()
            return
        }
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
            cancel(.previous)
            slots[0]?.player.pause()
            slots[0] = nil
            slots[0] = slots[1]
            slots[1] = slots[2]
            slots[2] = nil
        } else {
            cancel(.next)
            slots[2]?.player.pause()
            slots[2] = nil
            slots[2] = slots[1]
            slots[1] = slots[0]
            slots[0] = nil
        }

        if let ctx = slots[1] {
            completion(.success(ctx.player))
        } else {
            prepare(item: items[newIndex], slot: .current, generation: generation, completion: completion)
        }
    }

    // MARK: - 取消与清理

    func cancel(_ slot: PlayerSlot) {
        guard let ctx = slots[slot.rawValue] else { return }
        ctx.player.pause()
        for task in ctx.tasks { task.cancel() }
        slots[slot.rawValue] = nil
    }

    func cleanup() {
        for i in 0..<3 {
            cancel(PlayerSlot(rawValue: i)!)
        }
    }

    deinit { cleanup() }
}
