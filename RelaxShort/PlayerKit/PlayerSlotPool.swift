import AVFoundation

enum PlayerPreloadState: String, Equatable {
    case idle
    case preparing
    case ready
    case failed
}

// MARK: - 槽位上下文

/// 每个槽位持有的强引用上下文：player + item + 预加载任务
struct PlayerSlotContext {
    let player: AVPlayer
    var item: AVPlayerItem
    var resourceLoaderDelegate: PlayerResourceLoaderDelegate?
    var mediaID: String
    var source: PlayerMediaSource
    let preparedAt: Date
    var readyToPlayAt: Date?
    var firstFrameAt: Date?
    var tasks: [Task<Void, Never>] = []
    var generation: Int = 0
    var preloadState: PlayerPreloadState = .idle
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
@MainActor
final class PlayerSlotPool {

    private var slots: [PlayerSlotContext?] = [nil, nil, nil]

    /// 只读诊断入口：验证相邻槽在异步 preroll 完成前保持静音，不暴露槽位写权限。
    func player(in slot: PlayerSlot) -> AVPlayer? {
        slots[slot.rawValue]?.player
    }

    // MARK: - 准备槽位

    func prepare(
        item: PlayerMediaItem,
        slot: PlayerSlot,
        generation: Int,
        adaptiveQualityPolicy: PlayerAdaptiveQualityPolicy = .standard,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) {
        cancel(slot)
        let idx = slot.rawValue
        let intent: PlayerItemLoadIntent = slot == .current ? .playback : .preload
        let managedItem = PlayerItemFactory.makePlaybackItem(
            from: item,
            intent: intent,
            adaptiveQualityPolicy: adaptiveQualityPolicy
        )
        let playerItem = managedItem.item
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = slot != .current
        if slot == .current {
            // 当前视频由 AVPlayer 根据实际网络决定起播缓冲，避免 item ready 后仍停在 paused。
            player.currentItem?.preferredForwardBufferDuration = 0
            player.automaticallyWaitsToMinimizeStalling = true
        } else {
            player.currentItem?.preferredForwardBufferDuration = PlayerPreloadPolicy.preferredForwardBufferDuration
            player.automaticallyWaitsToMinimizeStalling = false
        }
        slots[idx] = PlayerSlotContext(
            player: player, item: playerItem,
            resourceLoaderDelegate: managedItem.resourceLoaderDelegate,
            mediaID: item.id, source: item.source,
            preparedAt: Date(), generation: generation,
            preloadState: slot == .current ? .idle : .preparing
        )
        // 相邻槽只由共享池预加载；item ready 即可复用，preroll 只是额外加速而非成败条件。
        if slot != .current {
            let loadTask = Task(priority: .utility) { [weak self, weak player, asset = playerItem.asset] in
                guard let self, let player else { return }
                guard !Task.isCancelled else { return }
                let isPlayable = (try? await asset.load(.isPlayable)) == true
                guard !Task.isCancelled else { return }
                guard isPlayable else {
                    self.finishPreload(
                        slot: slot,
                        mediaID: item.id,
                        state: .failed,
                        player: player,
                        completion: completion
                    )
                    print("[PlayerKit] 相邻预加载失败 mediaID=\(item.id) slot=\(slot) 可播放=\(isPlayable)")
                    return
                }
                let playerReady = await Self.waitUntilReadyToPlay(player)
                guard !Task.isCancelled,
                      playerReady,
                      player.currentItem?.status == .readyToPlay else {
                    if !Task.isCancelled {
                        self.finishPreload(
                            slot: slot,
                            mediaID: item.id,
                            state: .failed,
                            player: player,
                            completion: completion
                        )
                    }
                    print("[PlayerKit] 相邻预加载跳过 preroll mediaID=\(item.id) slot=\(slot) playerStatus=\(player.status.rawValue)")
                    return
                }
                let prerollReady = await withCheckedContinuation { continuation in
                    player.preroll(atRate: 1) { success in
                        continuation.resume(returning: success)
                    }
                }
                guard !Task.isCancelled else { return }
                // preroll=false 不代表媒体不可播放；只要 item 已 ready，就保留这条已建立的
                // HLS 连接供滑动时直接晋升，不能丢弃后重新建链。
                let usableState: PlayerPreloadState = player.currentItem?.status == .failed
                    ? .failed : .ready
                self.finishPreload(
                    slot: slot,
                    mediaID: item.id,
                    state: usableState,
                    player: player,
                    completion: completion
                )
                print("[PlayerKit] 相邻预加载完成 mediaID=\(item.id) slot=\(slot) preroll=\(prerollReady)")
            }
            slots[idx]?.tasks.append(loadTask)
            return
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
        adaptiveQualityPolicy: PlayerAdaptiveQualityPolicy = .standard,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) {
        guard items.indices.contains(newIndex) else { return }
        if let preloadState = promotePrepared(
            item: items[newIndex],
            generation: generation,
            completion: completion
        ) {
            print("[PlayerKit] 相邻预加载命中 idx=\(newIndex) 状态=\(preloadState.rawValue) 复用=true")
            return
        }
        parkCurrent(as: newIndex > oldIndex ? .previous : .next)
        print("[PlayerKit] 相邻预加载未命中 idx=\(newIndex) 方向=\(newIndex > oldIndex ? "next" : "previous")")
        prepare(
            item: items[newIndex], slot: .current, generation: generation,
            adaptiveQualityPolicy: adaptiveQualityPolicy, completion: completion
        )
    }

    /// 按稳定媒体 ID 与实际播放源提升预加载槽，不依赖页面自己的紧凑索引。
    /// 同一集从 Auto 改成固定画质后 source 会变化，旧 preroll 不得被误当成新画质复用。
    @discardableResult
    func promotePrepared(
        item: PlayerMediaItem,
        generation: Int,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) -> PlayerPreloadState? {
        let current = slots[PlayerSlot.current.rawValue]?.player
        current?.pause()
        current?.isMuted = true

        let sourceSlot: PlayerSlot
        if slots[PlayerSlot.next.rawValue]?.mediaID == item.id,
           slots[PlayerSlot.next.rawValue]?.source == item.source {
            sourceSlot = .next
        } else if slots[PlayerSlot.previous.rawValue]?.mediaID == item.id,
                  slots[PlayerSlot.previous.rawValue]?.source == item.source {
            sourceSlot = .previous
        } else {
            return nil
        }

        guard let source = slots[sourceSlot.rawValue] else { return nil }
        let canPromote = source.preloadState == .ready
            || (source.preloadState == .preparing && source.resourceLoaderDelegate == nil)
        guard canPromote else {
            if slots[sourceSlot.rawValue] != nil {
                print("[PlayerKit] 相邻预加载不可晋升，改用当前直连 mediaID=\(item.id) state=\(source.preloadState.rawValue)")
            }
            cancel(sourceSlot)
            return nil
        }
        let preloadState = source.preloadState
        cancelPreparation(sourceSlot)
        guard let promotedSource = slots[sourceSlot.rawValue] else { return nil }
        let oldCurrent = slots[PlayerSlot.current.rawValue].map(parkedContext)

        if sourceSlot == .next {
            cancel(.previous)
            slots[PlayerSlot.previous.rawValue] = oldCurrent
        } else {
            cancel(.next)
            slots[PlayerSlot.next.rawValue] = oldCurrent
        }
        slots[PlayerSlot.current.rawValue] = promotedSource
        slots[sourceSlot.rawValue] = nil

        guard let promoted = slots[PlayerSlot.current.rawValue],
              promoted.player.currentItem?.status != .failed else {
            cancel(.current)
            return nil
        }
        promoted.resourceLoaderDelegate?.promoteToPlaybackPriority()
        if promoted.player.currentItem?.status == .readyToPlay {
            promoted.player.cancelPendingPrerolls()
        }
        promoted.player.pause()
        promoted.player.isMuted = false
        completion(.success(promoted.player))
        return preloadState
    }

    /// 目标集没有命中预加载时，也要把刚播放过的 current 停放到相邻槽。
    /// AVFoundation 的 HLS 缓冲跟随 AVPlayerItem；保留实例才能让用户回滑时真正复用。
    private func parkCurrent(as destination: PlayerSlot) {
        guard destination != .current,
              let current = slots[PlayerSlot.current.rawValue] else { return }
        cancel(destination)
        slots[destination.rawValue] = parkedContext(current)
        slots[PlayerSlot.current.rawValue] = nil
    }

    private func parkedContext(_ context: PlayerSlotContext) -> PlayerSlotContext {
        var parked = context
        for task in parked.tasks { task.cancel() }
        parked.tasks.removeAll()
        parked.player.cancelPendingPrerolls()
        parked.player.pause()
        parked.player.isMuted = true
        parked.preloadState = parked.player.currentItem?.status == .readyToPlay
            ? .ready : .preparing
        return parked
    }

    /// 防止首帧回调和播放列表更新同时重复创建同一个 next。
    func contains(item: PlayerMediaItem, in slot: PlayerSlot) -> Bool {
        guard let context = slots[slot.rawValue] else { return false }
        return context.mediaID == item.id && context.source == item.source
    }

    /// 同一个 AVPlayer 原地替换正式源、重建 item 或降级源后，同步池内元数据。
    /// 否则列表刷新会把仍可复用的 previous/next 误判为旧源并释放。
    func updateCurrentMetadata(
        player: AVPlayer,
        playerItem: AVPlayerItem,
        mediaItem: PlayerMediaItem,
        resourceLoaderDelegate: PlayerResourceLoaderDelegate?
    ) {
        guard var context = slots[PlayerSlot.current.rawValue],
              context.player === player else { return }
        context.item = playerItem
        context.resourceLoaderDelegate = resourceLoaderDelegate
        context.mediaID = mediaItem.id
        context.source = mediaItem.source
        slots[PlayerSlot.current.rawValue] = context
    }

    // MARK: - 当前页强制重建（超时/failed/fallback 时 engine 调用）

    func rebuildCurrent(
        item: PlayerMediaItem,
        generation: Int,
        adaptiveQualityPolicy: PlayerAdaptiveQualityPolicy = .standard,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) {
        print("[PlayerKit] 重建当前播放器 媒体ID=\(item.id)")
        prepare(
            item: item, slot: .current, generation: generation,
            adaptiveQualityPolicy: adaptiveQualityPolicy, completion: completion
        )
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
        if ctx.player.currentItem?.status == .readyToPlay {
            ctx.player.cancelPendingPrerolls()
        }
    }

    /// AVPlayer.preroll 在 status 仍为 unknown 时会抛 Objective-C 异常，无法用 Swift catch 捕获。
    /// 因此先短暂等待 readyToPlay；超时只放弃 preroll，绝不影响主播放。
    private static func waitUntilReadyToPlay(_ player: AVPlayer) async -> Bool {
        for _ in 0..<160 {
            guard !Task.isCancelled else { return false }
            if player.status == .failed {
                return false
            }
            switch player.currentItem?.status {
            case .readyToPlay:
                return true
            case .failed:
                return false
            case .unknown, .none:
                try? await Task.sleep(nanoseconds: 50_000_000)
            @unknown default:
                return false
            }
        }
        return false
    }

    private func finishPreload(
        slot: PlayerSlot,
        mediaID: String,
        state: PlayerPreloadState,
        player: AVPlayer,
        completion: @escaping (Result<AVPlayer, Error>) -> Void
    ) {
        guard var context = slots[slot.rawValue],
              context.mediaID == mediaID,
              context.player === player else { return }
        context.preloadState = state
        context.tasks.removeAll()
        context.readyToPlayAt = state == .ready ? Date() : nil
        slots[slot.rawValue] = context
        player.pause()

        if state == .ready {
            completion(.success(player))
        } else {
            completion(
                .failure(
                    NSError(
                        domain: "PlayerSlotPool.Preload",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "相邻媒体预加载失败"]
                    )
                )
            )
        }
    }

    func cancelAdjacent() {
        cancel(.previous)
        cancel(.next)
    }

    /// 当前播放出现网络压力时只释放仍在拉流的相邻预加载；已经 ready 的前后集
    /// 保留在内存中，避免用户回滑时再次从 CDN 建链。
    func cancelPreparingAdjacent() {
        for slot in [PlayerSlot.previous, .next]
        where slots[slot.rawValue]?.preloadState == .preparing {
            cancel(slot)
        }
    }

    func cleanup() {
        for i in 0..<3 { cancel(PlayerSlot(rawValue: i)!) }
    }

    deinit {
        // deinit 不继承 MainActor 隔离，直接释放槽位，避免跨隔离调用 cleanup()。
        for context in slots.compactMap({ $0 }) {
            for task in context.tasks { task.cancel() }
            context.player.cancelPendingPrerolls()
            context.player.pause()
        }
    }
}
