# CC Task26 R2 Fixes — Codex Review 返工任务书

> 执行项目：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`
>
> 任务性质：Task26 review 返工
>
> 重要：不要扩大范围，不要继续做新 UI，不要改 Home/Search/My List/Profile/VIP/支付/广告。只修下面列出的 P0/P1/P2。

## 0. 当前状态

Task26 R1 已交付但 Codex review 不通过。当前工作区有未提交改动，先不要 reset，不要回滚整包。只按本文修复。

必须先读：

- `docs/CC_TASK26_FOR_YOU_PLAYER_POLISH.md`
- `docs/superpowers/plans/2026-06-23-task26-for-you-player-plan.md`
- `docs/TASK26_DELIVERY_REPORT.md`

## 1. 必修 P0：Series Player 切集必须真正使用目标集真实播放源

### 当前问题

`SeriesPlayerView.playerItems(from:)` 会跳过没有 URL/cache 的 episode。初始化时通常只有当前集拉过 `fetchPlayAsset`，但切集时：

- `handleEpisodeTransition` 先 `playerCoordinator.engine.move(to: episodeNumber - 1)`
- 然后才异步 `fetchPlayAssetForEpisode(new)`
- 拉到 source 后没有重建 engine items

这会导致切集无效、切错 item，或仍播放旧源。

### 修复要求

修改 `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`：

1. 切集前先确认目标 episode 的 `PlayerMediaSource`。
2. 如果没有缓存，先调用 `RealDetailRepository.fetchPlayAsset(episodeId:)`。
3. 拿到 source 后更新 `episodes[epIndex].videoURL` 和 `episodeMediaSources[episodeId]`。
4. 重新构建完整、索引安全的 player items。
5. `engine.move(to:)` 使用 player items 中目标 episode 对应的 index，不允许直接用 `episodeNumber - 1`。
6. 如果目标集 source 失败，显示/记录错误并保持当前集，不要切到错误 index。
7. 继续禁止 `about:blank`。

推荐实现方向：

```swift
private struct EpisodePlayableItem: Identifiable {
    let id: String
    let episodeNumber: Int
    let item: PlayerMediaItem
}

private func playableItems(from eps: [Episode]) -> [EpisodePlayableItem] {
    eps.compactMap { ep in
        guard let source = sourceForEpisode(ep) else { return nil }
        return EpisodePlayableItem(
            id: ep.id,
            episodeNumber: ep.episodeNumber,
            item: PlayerMediaItem(
                id: PlayerMediaItem.stableID(dramaID: drama.id, episodeNumber: ep.episodeNumber),
                title: drama.title,
                episodeNumber: ep.episodeNumber,
                coverURL: drama.coverURL,
                source: source,
                resumeTime: nil
            )
        )
    }
}
```

切集逻辑必须类似：

```swift
private func switchToEpisode(_ episodeNumber: Int) {
    Task { await switchToEpisodeAsync(episodeNumber) }
}

@MainActor
private func switchToEpisodeAsync(_ episodeNumber: Int) async {
    guard !isEpisodeLocked(episodeNumber) else {
        pendingLockedEpisode = episodeNumber
        unlockTargetEpisode = episodeNumber
        showUnlockSheet = true
        return
    }

    guard await ensurePlayAssetForEpisode(episodeNumber) else {
        Logger.viewModel.warning("SeriesPlayerView: cannot switch EP\(episodeNumber), missing play asset")
        return
    }

    let playable = playableItems(from: episodes)
    guard let playableIndex = playable.firstIndex(where: { $0.episodeNumber == episodeNumber }) else {
        Logger.viewModel.warning("SeriesPlayerView: cannot switch EP\(episodeNumber), no playable index")
        return
    }

    currentEpisode = episodeNumber
    playerCoordinator.engine.prepare(items: playable.map(\.item), index: playableIndex)
    playerCoordinator.engine.play()
}
```

不要求逐字照抄，但最终行为必须满足：

- EP1 → EP2 会调用 `/episodes/{episode2Id}/play`
- engine 当前 item id 变成 `dramaId-2`
- 日志出现目标集真实 HTTP/HLS URL
- 不出现 nil/about:blank

## 2. 必修 P1：恢复 `Package.resolved`

### 当前问题

`RelaxShort.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 被删除了。这是无关变更，会影响依赖锁定。

### 修复要求

恢复该文件：

```bash
git restore RelaxShort.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

最终 `git status --short` 不允许出现：

```text
D RelaxShort.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

## 3. 必修 P1：完成 Series Player 剧集 Sheet

### 当前问题

`EpisodePickerSheet` 仍是 5 列，没有 range tabs。交付报告也写了“Episode sheet 仍为 5 列”，这和 Task26 验收冲突。

### 修复要求

修改 `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`，把 `EpisodePickerSheet` 做到 Task26 要求：

- 深色大底部 sheet。
- 顶部 drag handle + close X。
- 头部包含 poster、title、views、rating。
- `Synopsis` / `Episodes` tab 外观，当前高亮 `Episodes`。
- range tabs 按 30 集一组生成：`1-30`、`31-60`、`61-90` 等；不足 30 的最后一组显示真实范围。
- episode grid 必须是 6 列。
- 当前集 cell 更亮，并在左下角显示 tiny playing bars。
- 锁定集右上角 lock badge。
- 免费范围使用 `drama.freeEpisodeRange ?? 1...3`。
- 点击已解锁集：调用新的安全切集逻辑，不直接 `currentEpisode = ep`。
- 点击锁定集：走现有 unlock sheet。

注意：这次必须真正替换旧的 5 列 sheet，不要只在交付报告里说明未完成。

## 4. 必修 P1：修复 More → Quality sheet presentation

### 当前问题

当前 `SeriesPlayerView` 同一个 View 挂了多个 `.sheet`，`PlayerMoreSheet` 里先 `dismiss()` 再立刻 `showQualitySheet = true`，SwiftUI 容易丢 presentation。

### 修复要求

改成单一 sheet router，例如：

```swift
private enum PlayerSheet: Identifiable {
    case share
    case speed
    case quality
    case more

    var id: String {
        switch self {
        case .share: "share"
        case .speed: "speed"
        case .quality: "quality"
        case .more: "more"
        }
    }
}

@State private var activeSheet: PlayerSheet?
```

然后只保留一个：

```swift
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .share:
        ShareSheet(dramaTitle: drama.title)
    case .speed:
        PlayerSpeedSheet(engine: playerCoordinator.engine)
    case .quality:
        PlayerQualitySheet(...)
    case .more:
        PlayerMoreSheet(
            onQuality: {
                activeSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    activeSheet = .quality
                }
            },
            ...
        )
    }
}
```

允许用更好的实现，但必须避免多 `.sheet` 互抢。

## 5. 必修 P2：Quality sheet 不要伪装成真实完成

### 当前问题

Quality 目前固定 Auto/720p/1080p/540p，且 `currentQuality` 参数未使用。

### 修复要求

二选一：

方案 A，推荐：基于当前 episode 的 `PlayerMediaSource.qualities` 生成选项；没有 qualities 时显示 fallback，并在交付报告明确“无多码率数据时为 fallback UI”。

方案 B：保持 UI-only，但：

- `docs/TASK26_DELIVERY_REPORT.md` 必须明确写“Quality 未绑定真实清晰度切换，仅 UI fallback”。
- 不要在“实现覆盖”里写成完整完成。
- `currentQuality` 参数要么使用，要么删除，避免死参数。

## 6. 必修 P2：清理 project.pbxproj 缩进/格式

当前 `project.pbxproj` 新增行缩进混乱，例如 `ShareSheet.swift` 行缩进被破坏。请修正为和相邻行一致。不要重排整个工程文件。

## 7. 验证要求

必须运行：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

如果遇到 GoogleMobileAds XCFramework artifact 缺失：

- 先尝试在 Xcode 或命令行重新解析包依赖。
- 可以尝试清理对应 DerivedData 的 SourcePackages artifacts 后重跑。
- 不能在没有 Swift 编译结果的情况下写 `BUILD SUCCEEDED`。

可用命令示例：

```bash
xcodebuild -resolvePackageDependencies -project RelaxShort.xcodeproj -scheme RelaxShort
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## 8. 交付报告更新

更新 `docs/TASK26_DELIVERY_REPORT.md`：

- 删除或修正“Episode sheet 仍为 5 列”的遗留项，除非你没有完成，那就不能交付通过。
- 写清楚 Series 切集真实播放源的最终实现。
- 写清楚 `Package.resolved` 已恢复。
- 写清楚 xcodebuild 的真实结果。
- 如果 Quality 仍是 fallback UI，必须如实写。

## 9. 最终交付前自检

运行：

```bash
git status --short
git diff --check
rg -n "Episode sheet 仍为 5 列|BUILD SUCCEEDED|Package.resolved" docs/TASK26_DELIVERY_REPORT.md
```

最终不允许：

- `Package.resolved` 删除。
- `EpisodePickerSheet` 仍为 5 列。
- 切集先 `engine.move(to: episodeNumber - 1)` 再异步拉源但不刷新 engine。
- xcodebuild 没通过却写 `BUILD SUCCEEDED`。
