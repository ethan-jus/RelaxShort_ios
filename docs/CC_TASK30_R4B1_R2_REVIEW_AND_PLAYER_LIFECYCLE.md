# Task30 R4B-1 R2 返工：Analytics 工程化与 SeriesPlayer 生命周期

## 任务目标

完成 R4B-1 原计划中被跳过的文件拆分、测试 Target、多尺寸和真实联调门禁，并修复 SeriesPlayer 两个阻断问题：

1. 从 Home 进入 SeriesPlayer 后必须自动开始播放。
2. 返回上级页面后 SeriesPlayer 不得继续发声，任何延迟 prepare、Recovery 或 handoff 回调都不得重新启动播放。

## 已确认根因

当前 `PlayerCoordinator.release()` 调用：

```swift
engine.pause(reason: .system)
```

但 `.system` pause 会保留 `ShortVideoPlayerEngine.wantsPlayback = true`。因此页面消失后，下列异步路径仍可能再次 `play()`：

- 尚未完成的 `prepare -> attach`
- `PlayerRecoveryController.recoveryTask`
- handoff 的 KVO/3 秒超时回调
- `SeriesPlayerView.loadEpisodes()` 在 `.task` 被取消后继续执行并再次 `claimSeries`

上次修复只暂停了当时的 `AVPlayer`，没有撤销播放所有权和异步播放意图。

## 审查不通过项

- `APIClient.swift` 增加约 240 行 Analytics 类型，违反已确认文件边界。
- 没有创建 `RelaxShortTests` target；交付所称 DTO/Reporter/Search 测试文件实际不存在。
- `InstallIdentityProvider` 标记为 `@unchecked Sendable`，但可变 `memoryID` 没有同步保护，存在并发数据竞争。
- Reporter 的重试 sleep 使用 `try?`，会吞掉 Task cancellation；后台 flush 可能继续存活最多 82 秒。
- `SearchViewModel.flushPendingEvents/flushForBackground` 没有调用方，和 App 级生命周期职责重复。
- 只构建 iPhone 17，没有小屏/大屏门禁。
- 没有真实事件入库和动态榜单证据。
- 当前工作树 `APIClient.swift` 有 11 处 trailing whitespace，交付所称 `git diff --check` 通过与实际状态不一致。

构建成功不等于任务通过。以上项目必须在 R2 一次收敛。

## 禁止事项

- 不回滚当前未提交的 R4B-1 改动。
- 不重写 PlayerKit，不改播放器 UI、手势、缓存、进度条和 Recovery 策略。
- 不用新的 `onDisappear` 延时、通知或全局布尔值拼补生命周期。
- 不把 SeriesPlayer 改成独立第二套 Engine。
- 不删除 For You 与 Series 共享 Engine 架构。
- 不提交、不推送，等待 Codex review。
- 不新增重复交付报告，只给中文简报。

## Phase A：先建立测试门禁

### A1. 创建 `RelaxShortTests` target

修改 `RelaxShort.xcodeproj/project.pbxproj`：

- 新增 Unit Test target `RelaxShortTests`
- 依赖 App target `RelaxShort`
- `TEST_HOST` 指向 RelaxShort.app
- scheme 的 Test action 能发现该 target
- 不重排无关 PBX section

先创建：

- `RelaxShortTests/PlayerLifecycleTests.swift`
- `RelaxShortTests/RankingResponseDTOTests.swift`
- `RelaxShortTests/InstallIdentityProviderTests.swift`
- `RelaxShortTests/DiscoveryAnalyticsReporterTests.swift`
- `RelaxShortTests/SearchAnalyticsTests.swift`

执行：

```bash
xcodebuild test \
  -project RelaxShort.xcodeproj \
  -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

测试 target 配置错误不算 RED。必须先让测试真正运行。

### A2. 播放生命周期 RED 测试

至少覆盖：

```swift
@MainActor
func testDeactivateRevokesPlaybackIntent() {
    let engine = ShortVideoPlayerEngine()
    engine.play()
    XCTAssertTrue(engine.wantsPlayback)

    engine.deactivate()

    XCTAssertFalse(engine.wantsPlayback)
    XCTAssertEqual(engine.state, .pausedBySystem)
}
```

以及 Coordinator：

```swift
@MainActor
func testReleaseSeriesRevokesOwnerAndPlaybackIntent() {
    // claim Series 后 release exact owner
    // 断言 owner == nil、wantsPlayback == false
}
```

如果 `PlayerPlaybackState` 尚未 `Equatable`，使用 switch 断言，不为测试随意改变生产枚举。

## Phase B：修复 SeriesPlayer 所有权生命周期

### B1. Engine 区分“临时暂停”和“所有权释放”

修改 `ShortVideoPlayerEngine.swift`，保留现有：

```swift
pause(reason: .system)
```

用于临时遮挡、切 Tab 等可恢复场景。

新增：

```swift
func deactivate() {
    let wasPreparing = state == .preparing
    wantsPlayback = false
    generation &+= 1
    cancelAllPreloadTasks()
    subtitleTask?.cancel()
    recoveryController.cancelPendingRecovery()
    currentPlayer?.pause()
    if wasPreparing {
        currentItem = nil
    }
    state = .pausedBySystem
}
```

要求：

- 撤销 `wantsPlayback`
- 使进行中的 prepare generation 失效
- 取消预加载、readiness、字幕和 Recovery 异步任务
- 不调用完整 `cleanup()`，因为 Engine 仍由 For You/Series 共享
- 已经 attach 的同一 item 可保留当前位置，重新进入时 `claimSeries` 必须显式 `play()`

### B2. Recovery 提供明确取消 API

修改 `PlayerRecoveryController.swift`：

```swift
func cancelPendingRecovery() {
    recoveryTask?.cancel()
    recoveryTask = nil
    stablePlaybackTask?.cancel()
    stablePlaybackTask = nil
    wasPlaying = false
    wasUserPaused = false
    lastItem = nil
}
```

所有 sleep 后继续已有 `Task.isCancelled` 检查。不得吞掉取消后继续 seek/play。

### B3. Coordinator 管理可取消的 handoff

修改 `PlayerCoordinator.swift`：

- 保存 `seriesResumeTask`
- 每次 claim 新 owner 或 release 时取消旧 task
- 使用 claim token 或递增 generation
- handoff 到不同 item 前先 `engine.deactivate()`，再 `prepare()`，避免旧播放意图让新 item 在 seek 前抢先播放
- “同 item 直接复用”必须同时满足目标 ID 一致、`currentPlayer != nil` 且 Engine 不处于 `.preparing`
- 所有 seek completion、ready 轮询和 timeout fallback 在 `play()` 前同时验证：
  - 当前 owner 仍是同一 `.series(dramaID:)`
  - claim token 未失效
  - Task 未取消
  - `engine.currentItem?.id` 仍是目标媒体 ID
  - Engine 已离开 `.preparing`，目标媒体已真正 attach

禁止保留当前“局部 KVO + 3 秒后无条件 play”的实现。推荐改为单个可取消 Task：

```swift
seriesResumeTask = Task { @MainActor [weak self, weak engine] in
    guard let self, let engine else { return }
    let deadline = Date().addingTimeInterval(3)
    while (engine.state == .preparing ||
           engine.currentPlayer?.currentItem?.status != .readyToPlay),
          Date() < deadline {
        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled,
              self.isCurrentSeriesClaim(owner, token: token),
              engine.currentItem?.id == targetItemID else { return }
    }
    guard self.isCurrentSeriesClaim(owner, token: token),
          engine.currentItem?.id == targetItemID,
          engine.state != .preparing,
          engine.currentPlayer?.currentItem?.status == .readyToPlay else { return }
    engine.seekTime(resumeTime) { [weak self, weak engine] _ in
        guard let self, let engine,
              self.isCurrentSeriesClaim(owner, token: token),
              engine.currentItem?.id == targetItemID,
              engine.state != .preparing else { return }
        engine.play()
    }
}
```

不得只检查 `engine.currentItem` 后立即读取 `currentPlayer.currentItem.status`。`prepare()` 会先更新逻辑
`currentItem`，此时 `currentPlayer` 仍可能挂着上一条视频；必须等待 Engine 从 `.preparing`
进入 attach 后状态，再执行 seek/play。

`release()` 必须：

```swift
guard self.owner == owner else { return }
invalidateCurrentClaim()
engine.deactivate()
self.owner = nil
```

### B4. Series `.task` 取消后禁止重新 claim

修改 `SeriesPlayerView.loadEpisodes()`：

- 每个 `await` 返回后检查 `Task.isCancelled`
- `initializeEpisodePlayer()` 前最后检查一次
- `.onDisappear` 保持同步执行 `release`

结构：

```swift
private func loadEpisodes() async {
    do {
        episodes = try await dependencies.detailRepository.fetchEpisodes(
            dramaId: drama.id
        )
    } catch is CancellationError {
        return
    } catch {
        guard !Task.isCancelled else { return }
        episodes = (try? await MockDetailRepository()
            .fetchEpisodes(dramaId: drama.id)) ?? []
    }

    guard !Task.isCancelled else { return }
    _ = await ensurePlayAsset(for: currentEpisode)
    guard !Task.isCancelled else { return }
    initializeEpisodePlayer()
}
```

### B5. 自动播放合同

验证所有入口：

- Home -> Series，无 handoff：prepare 完成后自动播放
- Search -> Series，无 handoff：prepare 完成后自动播放
- For You -> Series，有 handoff：seek 到断点后自动播放
- 退出后再次进入同一集：保留合理播放位置并自动播放
- 用户上次主动暂停不影响“新页面默认自动播放”合同

不能用页面出现后固定延迟 `play()`。

## Phase C：完成 R4B-1 原计划

### C1. 拆分 Analytics 文件

从 `APIClient.swift` 移出全部新增 Analytics 类型，恢复网络客户端单一职责：

- `Core/Analytics/InstallIdentityProvider.swift`
- `Core/Analytics/DiscoveryEvent.swift`
- `Core/Analytics/DiscoveryEventTransport.swift`
- `Core/Analytics/DiscoveryEventQueueStore.swift`
- `Core/Analytics/DiscoveryAnalyticsReporter.swift`
- `Core/Analytics/DiscoveryAnalyticsClient.swift`
- `Models/API/RankingResponseDTO.swift`
- `Models/RankingEntry.swift`

将文件正确加入 App target 和 Test target。禁止继续以内联方式规避 pbxproj。

### C2. 修复安装 ID 并发

不能只依赖 `@unchecked Sendable`。使用锁保护 `memoryID` 的完整读、Keychain 读取/生成、写入流程，确保并发请求只生成一个 UUID。

测试至少并发调用 20 次并断言结果唯一值数量为 1。

### C3. Reporter 取消与后台策略

- `Task.sleep` 使用 `try await`，CancellationError 立即终止本轮重试
- 前台 flush：首次请求 + 2/5/15/60 秒最多四次重试
- 后台 flush：只做一次 best-effort 请求，不启动 82 秒重试链
- 延迟 flush Task 取消后不得再次进入发送
- partial acknowledge 保留未确认批次
- 队列损坏文件改名隔离，不静默删除全部证据

删除未使用的：

```swift
SearchViewModel.flushPendingEvents()
SearchViewModel.flushForBackground()
```

App 生命周期继续由 `DependencyContainer.discoveryAnalytics` 统一管理。

### C4. 补齐测试

必须真实运行并通过：

- 嵌套 Ranking DTO / Int64 metric
- Repository 不本地重排
- Ranking formatter
- Install ID 稳定与并发
- Reporter 20 条 flush、15 秒可控延迟、失败保留、成功删除
- Reporter cancellation 和 background best-effort
- 持久化恢复和 500 条上限
- Search 防抖不报 submit
- 键盘、Recent、Trending 各一次 submit
- Result click 携带 query + Int64 series ID
- Player deactivate / release / canceled async start

## Phase D：验收

### D1. 构建与测试

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'

xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)'

xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'

xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

设备不存在时使用 `xcrun simctl list devices available` 中同级设备并如实记录。

### D2. 手工播放器验收

用户在模拟器执行：

1. Home 点击任意短剧，进入后无需点击自动播放。
2. 返回 Home，等待至少 5 秒，完全无 Series 音频。
3. 快速进入并立即返回，等待 5 秒，不能出现延迟漏音。
4. 再次进入同一短剧，自动播放。
5. 从 For You 的 Watch Full 进入并返回，不能漏音。

Xcode 日志必须能看到 release/deactivate，之后不得出现该 Series owner 的 `attach: 自动播放` 或 `recovery play resumed`。

### D3. Analytics 联调

后端由用户在 IDEA 显式运行。完成一次搜索提交和一次结果点击后检查：

```sql
SELECT event_id, event_type, series_id, search_term,
       content_language, country_code, source_scene, occurred_at
FROM rs_discovery_events
WHERE source_scene = 'search'
ORDER BY id DESC
LIMIT 10;
```

还需确认三个榜单 UI 顺序和 `metric_value` 与 API 一致；`new_releases` 空数组必须显示空态，不回退 Mock。

### D4. 最终检查

```bash
git diff --check
git status --short
```

交付简报必须列出真实测试数量、三类尺寸构建、播放器五步验收和数据库事件证据。不得再次把“待做测试、待拆文件、待真实联调”写成完成。
