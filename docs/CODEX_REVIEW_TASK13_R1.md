# Codex Review: Task13 R1 iOS Real API Phase 1

**结论**: 不通过，需 R2 返工。

Task13 R1 增加了 API DTO、真实 Repository 和 app/init 调用雏形，但当前实现没有形成可运行、可验证的真实 API 闭环。主要问题是新增 Swift 文件未加入 Xcode target，且 For You / Series Player 实际 UI 路径仍在使用 Mock Repository。

## 必改问题

### P0: 新增 Swift 文件未加入 Xcode project Sources，当前工程无法编译

新增文件存在于文件系统：

- `RelaxShort/Core/Services/APIConfig.swift`
- `RelaxShort/Core/Services/AppInitService.swift`
- `RelaxShort/Core/Services/DTO/APIResponseEnvelope.swift`
- `RelaxShort/Core/Services/RealHomeRepository.swift`
- `RelaxShort/Core/Services/RealDetailRepository.swift`
- `RelaxShort/Models/API/AppInitResponseDTO.swift`
- `RelaxShort/Models/API/ForYouFeedResponseDTO.swift`
- `RelaxShort/Models/API/SeriesEpisodesResponseDTO.swift`
- `RelaxShort/Models/API/PlayerMediaSource.swift`

但 `RelaxShort.xcodeproj/project.pbxproj` 的 `PBXSourcesBuildPhase` 没有这些文件引用。当前已纳入 target 的只有旧文件，例如 `APIClient.swift`、`APIEndpoint.swift`、`DependencyContainer.swift`、`RelaxShortApp.swift` 等。

影响：

- `RelaxShortApp.swift` 已引用 `AppInitService`。
- `APIEndpoint.swift` 已引用 `APIConfig`。
- `DependencyContainer.swift` 已引用 `RealHomeRepository`、`RealDetailRepository`。
- 如果直接用当前 `.xcodeproj` 构建，会出现 `Cannot find ... in scope` 类编译错误。

R2 要求：

- 将所有新增 Swift 文件加入 `RelaxShort` target 的 Sources。
- 如果使用 XcodeGen/project.yml 管理工程，可以更新 `project.yml` 后重新生成 `.xcodeproj`；否则直接维护 `project.pbxproj`。
- 交付报告必须说明采用哪种方式。

### P0: For You 实际 UI 路径仍硬编码 MockHomeRepository，RealHomeRepository 没有被页面使用

- 位置: `RelaxShort/Views/MainTabView.swift:17-18`
- 当前代码:
  - `HomeViewModel(repository: MockHomeRepository())`
  - `RecommendViewModel(repository: MockHomeRepository())`

虽然 `DependencyContainer` 增加了 `use_real_api` 开关，但 `MainTabView` 没有从 `@EnvironmentObject var dependencies` 读取 repository，导致切换开关不会影响 Home / For You 页面。

影响：

- `GET /api/v2/feed/for-you` 不会在真实 UI 路径触发。
- Task13 目标“app init → For You 推荐流”没有闭环。

R2 要求：

- `MainTabView` 必须通过 `DependencyContainer` 注入 `homeRepository`，让 `RecommendViewModel` 在 `use_real_api=true` 时走 `RealHomeRepository`。
- 保持 Mock fallback，但不能继续在主入口硬编码 Mock。
- 注意 `@StateObject` 初始化和 `@EnvironmentObject` 生命周期；可用明确的 initializer 或容器创建 VM，避免 SwiftUI 重建导致状态丢失。

### P0: SeriesPlayerView 仍硬编码 MockDetailRepository，剧集列表/播放地址没有真实闭环

- 位置: `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift:144-147`
- 当前代码:
  - `let repo = MockDetailRepository()`
  - `repo.fetchEpisodes(dramaId:)`

影响：

- `GET /api/v2/series/{seriesId}/episodes` 不会在播放页真实路径触发。
- `GET /api/v2/episodes/{episodeId}/play` 没有被 `SeriesPlayerView` 使用。
- 新增的 `PlayerMediaSource` 和 `RealDetailRepository.fetchPlayAsset()` 只是孤立代码，未接入实际播放器。

R2 要求：

- `SeriesPlayerView` 必须通过依赖注入使用 `DependencyContainer.detailRepository`，不能硬编码 `MockDetailRepository()`。
- 真实模式下加载剧集列表后，至少为当前集调用 `episodePlay` 获取 `preferredPlaybackURL` 并喂给 `PlayerPool`。
- 保持失败降级：真实播放地址失败时可以使用已有 episode videoURL 或展示封面/错误态，但必须记录日志，不崩溃。

### P1: Task13 计划文档和本地协作规则缺失

Codex 之前在 Task13 分支创建过：

- `AGENTS.md`
- `CLAUDE.md`
- `docs/CC_TASK13_IOS_REAL_API_PHASE1.md`

当前 R1 分支没有这些文件，说明实现分支没有基于计划提交继续，或中途重置丢失了计划文档。

R2 要求：

- 恢复这三个文件，或重新加入等价内容。
- 后续 review 和交付必须能在 iOS 仓库内看到任务边界、CC 规则和执行计划。

### P2: APIClient 网络错误映射退化

`APIClient.requestRaw` / `requestArray` 直接 `try await session.data(for:)`，没有像旧实现一样把 `URLSession` 错误通过 `NetworkError.from(error)` 映射。

R2 要求：

- 恢复网络错误映射，至少对 timeout/no connection 保持原有 `NetworkError` 语义。
- 不要让底层 `URLError` 直接穿透到 UI 层。

## 验证情况

已执行：

```bash
git diff --check
```

结果通过。

已尝试执行：

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'generic/platform=iOS Simulator' build
```

结果失败，原因是本机 Xcode 缺少 `CoreSimulator.framework`，与交付报告一致。由于无法实际编译，R1 review 使用项目文件静态检查确认新增 Swift 文件未加入 Sources。

## R2 验收标准

1. 新增 Swift 文件全部加入 `RelaxShort` target。
2. `use_real_api=true` 时，For You 实际 UI 路径调用 `RealHomeRepository`。
3. `use_real_api=true` 时，Series Player 实际 UI 路径调用 `RealDetailRepository`，并至少对当前集调用 `episodePlay` 获取播放 URL。
4. 恢复 `AGENTS.md`、`CLAUDE.md`、`docs/CC_TASK13_IOS_REAL_API_PHASE1.md`。
5. 更新 `docs/TASK13_DELIVERY_REPORT.md`，说明 R2 修复和验证结果。
6. 执行并记录：

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'generic/platform=iOS Simulator' build
```

如果 `xcodebuild` 仍因本机 CoreSimulator 缺失失败，必须至少证明 `.xcodeproj` Sources 已包含新增文件，并记录完整错误。
