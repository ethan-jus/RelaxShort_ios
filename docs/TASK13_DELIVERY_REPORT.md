# Task 13 交付报告：iOS Real API Phase 1

**分支**: `task/task13-ios-real-api-phase1`
**日期**: 2026-06-21

## 执行摘要

实现 iOS 从 Mock 到真实 API 首个闭环：app init → For You 推荐流 → 剧集列表 → 播放地址。

## 修改文件清单

### 新增（10 个）

| 文件 | 说明 |
|------|------|
| `RelaxShort/Core/Services/APIConfig.swift` | baseURL 配置（Debug=127.0.0.1:8080，UserDefaults 可覆盖） |
| `RelaxShort/Core/Services/DTO/APIResponseEnvelope.swift` | `ApiResponse<T>` 信封 + `APIError` 业务错误类型 |
| `RelaxShort/Core/Services/AppInitService.swift` | 启动初始化服务：POST /api/v2/app/init + 5 秒超时降级 |
| `RelaxShort/Core/Services/RealHomeRepository.swift` | 真实 Home 仓库 + `FeedCardDTOMapper` DTO→UI 映射 |
| `RelaxShort/Core/Services/RealDetailRepository.swift` | 真实 Detail 仓库：剧集列表 + 播放地址 + PlayerMediaSource |
| `RelaxShort/Models/API/AppInitResponseDTO.swift` | AppInit / Update / AdsConfig DTO |
| `RelaxShort/Models/API/ForYouFeedResponseDTO.swift` | ForYouFeed / FeedCard / Monetization / PlayAsset / Quality / Subtitle DTO |
| `RelaxShort/Models/API/SeriesEpisodesResponseDTO.swift` | EpisodeList / EpisodePlay / Thumbnail DTO |
| `RelaxShort/Models/API/PlayerMediaSource.swift` | 播放媒体源模型（HLS+MP4+qualities+subtitles+thumbnail） |
| `docs/TASK13_DELIVERY_REPORT.md` | 本报告 |

### 修改（4 个）

| 文件 | 变更 |
|------|------|
| `RelaxShort/App/RelaxShortApp.swift` | SplashView 添加 `.task { await AppInitService.shared.initialize() }` |
| `RelaxShort/Core/Services/APIClient.swift` | 新增 `requestData<T>()` 自动解包 envelope；原 `request` → `requestRaw` |
| `RelaxShort/Core/Services/APIEndpoint.swift` | 新增真实 v2 端点（appInit/forYou/seriesEpisodes/episodePlay），保留旧 mock 端点 |
| `RelaxShort/Core/Services/DependencyContainer.swift` | 增加 `useRealAPI` UserDefaults 开关，Home/Detail 按开关选 Real/Mock |

## baseURL 配置方式

- `APIConfig.baseURL`：优先 `UserDefaults.string("api_base_url")` → Debug 默认 `http://127.0.0.1:8080`
- Release 从 Info.plist `API_BASE_URL` 读取
- 不硬编码生产 IP

## Mock/Real 切换方式

**UserDefaults 驱动，无需改源码：**

```bash
# 切换到真实 API
defaults write com.relaxshort.ios use_real_api -bool true

# 切回 Mock
defaults write com.relaxshort.ios use_real_api -bool false
```

`DependencyContainer` 在 `init()` 中根据 `UserDefaults.bool("use_real_api")` 决定注入 `RealHomeRepository`/`RealDetailRepository` 或 `MockHomeRepository`/`MockDetailRepository`。

## 已接入接口

| 接口 | 接入方式 | 对应 Repository |
|------|----------|----------------|
| `POST /api/v2/app/init` | `AppInitService.initialize()` — SplashView task | AppInitService |
| `GET /api/v2/feed/for-you` | `RealHomeRepository.fetchForYou()` | RealHomeRepository |
| `GET /api/v2/series/{id}/episodes` | `RealDetailRepository.fetchEpisodes()` | RealDetailRepository |
| `GET /api/v2/episodes/{id}/play` | `RealDetailRepository.fetchPlayAsset()` | RealDetailRepository |

## DTO 映射说明

| 后端 DTO | iOS DTO | UI Model | 关键转换 |
|----------|---------|----------|----------|
| `ForYouFeedResponse` | `ForYouFeedResponseDTO` | `[DramaItem]` | `FeedCardDTOMapper.toDramaItem()` |
| `FeedCardDto` | `FeedCardDTO` | `DramaItem` | `seriesId` Int64→String；`monetization`→`isVIPOnly`/`coinPrice` |
| `EpisodeListResponse` | `SeriesEpisodesResponseDTO` | `[Episode]` | `episodeId` Int64→String |
| `EpisodePlayResponse` | `EpisodePlayResponseDTO` | `PlayerMediaSource` + `Episode.videoURL` | `sourceType`→播放类型；`preferredPlaybackURL`（HLS>MP4>first quality） |

**Task12 Gap 处理**：后端暂缺字段（`view_count`、`category`、`region_tag`、`language_tag`、`free_episode_range`）给安全默认值，代码注释标 `"Gap: Task12 P1/P2"`。

## 播放模型兼容

- 新增 `PlayerMediaSource` 表达完整 HLS/qualiities/subtitles/thumbnail
- `Episode.videoURL` 临时填 `preferredPlaybackURL` 兼容现有 `VideoPlayerView`/`PlayerPool`
- 现有 `AVPlayer(url:)` 播放流程不受影响

## 验证

### xcodebuild

```bash
$ xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
    -destination 'generic/platform=iOS Simulator' build
```

**失败**：本机缺少 `CoreSimulator.framework`（路径 `/Library/Developer/PrivateFrameworks/CoreSimulator.framework` 不存在）。Xcode 命令行工具插件加载失败。

### 替代检查

```bash
$ git diff --check
（通过，无 whitespace 错误）

$ git diff --stat
（4 modified + 10 new files）

$ git status --short --branch
## task/task13-ios-real-api-phase1
```

## ECC 使用记录

| ECC 能力 | 实际可用？ | 说明 |
|----------|-----------|------|
| `/plugin list ecc@ecc` | ❌ | VSCode 扩展环境不支持 |
| `/ecc:plan` | ❌ | 同上 |
| Explore agent（3 个并行） | ✅ | 读取全部 iOS 源码 + 后端合同 |
| **手工审计替代** | ✅ | 按 CLAUDE.md/AGENTS.md 规则逐文件审查：MainActor、Codable snake_case、DTO/UI Model 分离、Repository 边界、安全默认值 |

## 未完成事项

1. **xcodebuild 编译验证**：本机无 CoreSimulator.framework，需在配备完整 Xcode 环境的机器上验证
2. **播放页 SeriesPlayerView 未改为调用 RealDetailRepository**：当前仍硬编码 `MockDetailRepository()`，Task13+ 应通过 DependencyContainer 注入
3. **RecommendViewModel 仍走 `fetchDramas(category:)` 而非独立 `fetchForYou(cursor:)`**：cursor 分页状态需 Task13+ 补充
4. **后端暂停字段**：`view_count`/`category`/`region_tag`/`language_tag`/`free_episode_range` 暂用默认值

## 下一步建议

- Task13+: 播放页对接 RealDetailRepository，加入 cursor 分页状态
- Task14: 补后端暂停字段 + iOS RealAdService 接入 reward session
