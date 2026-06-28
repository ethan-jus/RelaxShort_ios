# Task30 Player Routing And Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复所有入口选片、自动播放和退出漏音，并完成播放行为驱动的动态榜单联调。

**Architecture:** PlayerCoordinator 独占共享 Engine 生命周期；Series 页面进入即取得 owner，
先用卡片预览源秒开，再异步校准正式播放源。后端提供准确权益状态，Analytics Reporter
持久化上报真实用户行为。

**Tech Stack:** SwiftUI, AVFoundation, XCTest, Spring Boot, MyBatis, MySQL, Redis, JUnit 5

---

### Task 1: 建立 iOS 测试 Target

**Files:**
- Modify: `RelaxShort.xcodeproj/project.pbxproj`
- Create: `RelaxShortTests/PlayerCoordinatorLifecycleTests.swift`
- Create: `RelaxShortTests/DiscoveryEventCodingTests.swift`
- Create: `RelaxShortTests/APIEndpointHeaderTests.swift`

- [ ] 通过 Xcode 工程操作创建 `RelaxShortTests` Unit Test target，依赖 App target。
- [ ] 确认 `xcodebuild -list` 同时显示 `RelaxShort` 和 `RelaxShortTests`。
- [ ] 运行空测试，确认测试基础设施本身可执行。

### Task 2: 播放所有权 RED 测试

**Files:**
- Test: `RelaxShortTests/PlayerCoordinatorLifecycleTests.swift`
- Modify: `RelaxShort/PlayerKit/PlayerCoordinator.swift`

- [ ] 编写失败测试：`beginSeries` 后 owner 必须是所选 drama，旧播放意图为 false。
- [ ] 编写失败测试：错误 owner 不能释放当前 Series。
- [ ] 编写失败测试：`release` 后 owner 为 nil、`wantsPlayback=false`。
- [ ] 编写失败测试：For You resume 在 owner 为 Series 时不得启动 Engine。
- [ ] 运行测试确认因 API 缺失而 RED。
- [ ] 实现 `beginSeries/pauseForYou/resumeForYou`，运行测试转 GREEN。

### Task 3: 正确入口与预览源秒开

**Files:**
- Modify: `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- Modify: `RelaxShort/Views/RecommendPage/VideoPlayerView.swift`
- Modify: `RelaxShort/Views/RecommendPage/RecommendView.swift`
- Modify: `RelaxShort/Views/MainTabView.swift`
- Modify: `RelaxShort/Models/DramaItem.swift`
- Modify: `RelaxShort/Core/Services/RealHomeRepository.swift`

- [ ] 添加 `DramaItem.previewEpisodeID` 并映射后端 `preview_episode_id`。
- [ ] 提取纯函数生成初始 `PlayerMediaItem`，测试不同 drama 生成不同稳定 ID 与 URL。
- [ ] Series `.task(id: drama.id)` 首行调用 `beginSeries`。
- [ ] 卡片存在合法媒体时立即 `claimSeries` 自动播放。
- [ ] Episodes 返回后按 `previewEpisodeID` 或 `startEpisode` 定位，禁止默认落到其他剧。
- [ ] 请求失败时显示当前错误或继续合法预览源，禁止保留旧 Engine 媒体。
- [ ] 删除 real API 的 Mock episodes fallback。
- [ ] RecommendView 所有系统暂停/恢复改走 Coordinator owner API。

### Task 4: 权益请求与错误合同

**Files:**
- Test: `RelaxShortTests/APIEndpointHeaderTests.swift`
- Modify: `RelaxShort/Core/Services/APIEndpoint.swift`
- Modify: `RelaxShort/Core/Services/APIClient.swift`
- Modify: `app-server/v2/src/main/java/com/relaxshort/v2/common/error/GlobalExceptionHandler.java`
- Modify: `app-server/v2/src/test/java/com/relaxshort/v2/app/content/ContentControllerTest.java`

- [ ] RED：real API `.episodePlay` 应携带 `X-User-Id: 1`。
- [ ] RED：`EPISODE_LOCKED` HTTP 状态应为 403。
- [ ] 将 `.episodePlay` 纳入 dev 用户桥头部。
- [ ] 后端映射 `EPISODE_LOCKED -> FORBIDDEN`。
- [ ] iOS 非 2xx 响应解析 `error.code/message`，不丢失业务错误。
- [ ] 运行 iOS/后端测试转 GREEN。

### Task 5: 下一集预取

**Files:**
- Modify: `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- Create: `RelaxShort/Core/Services/PlaybackSourcePrewarmer.swift`
- Test: `RelaxShortTests/PlaybackSourcePrewarmerTests.swift`

- [ ] 当前集稳定播放后异步获取下一集 play asset。
- [ ] 缓存下一集 `PlayerMediaSource`。
- [ ] 用 `AVURLAsset.load(.isPlayable)` 做可取消元数据预热。
- [ ] 页面退出时取消预热 Task。
- [ ] 不重建当前 AVPlayer，不阻塞主线程。

### Task 6: 排行榜真实事件

**Files:**
- Modify: `RelaxShort/Core/Analytics/DiscoveryEvent.swift`
- Modify: `RelaxShort/Core/Analytics/DiscoveryAnalyticsClient.swift`
- Modify: `RelaxShort/Views/RecommendPage/RecommendView.swift`
- Modify: `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- Modify: `RelaxShort/Views/Rank/RankView.swift`
- Test: `RelaxShortTests/DiscoveryEventCodingTests.swift`

- [ ] 扩展事件枚举：impression、qualifiedPlay、playComplete、bookmark、share。
- [ ] 事件包含正确 `series_id`，播放事件包含 `episode_id`。
- [ ] 会话内 impression/qualifiedPlay 去重。
- [ ] 播放阈值达到后上报 qualified play，结束时上报 complete。
- [ ] 收藏和分享只在用户动作成功后上报。
- [ ] 编码 round-trip 和队列恢复测试通过。

### Task 7: 真实联调与性能门禁

**Files:**
- Modify only if a verified contract defect is found.

- [ ] 后端 `mvn test`。
- [ ] 后端 `mvn package -DskipTests`。
- [ ] iOS `xcodebuild test`。
- [ ] iPhone SE、17、17 Pro Max 构建。
- [ ] curl 验证三部不同 series 的 episodes/play 返回各自媒体 URL。
- [ ] 模拟四类入口，日志中 media ID 与所选 series 一致。
- [ ] 快速进入退出 10 次，退出后无 attach/recovery/play。
- [ ] 以 10 并发、总计 100 请求对 rankings/home/play 做本地 smoke，记录 p50/p95/错误率。
- [ ] 查询 `rs_discovery_events` 验证真实事件。
- [ ] 触发 Worker 后确认榜单 API 使用新快照。
- [ ] `git diff --check`，分别审查 iOS/后端 diff，不跨仓库提交。
