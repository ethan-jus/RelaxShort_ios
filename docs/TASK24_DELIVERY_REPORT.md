# Task24 iOS Delivery Report

> 日期：2026-06-22
> 目标：修复 iOS PlayerKit 播放旧 HTTP MP4 时 CoreMediaErrorDomain -12882 和无限 recovery

## 修改文件

| 文件 | 变更说明 |
|------|---------|
| `RelaxShort/Core/Services/RealHomeRepository.swift` | **A1**: `videoURL` 映射添加 `mp4FallbackUrl` fallback |
| `RelaxShort/Models/API/PlayerMediaSource.swift` | **A2**: 新增 `PlaybackMediaSourceDTO.toPlayerMediaSource()` 根据 sourceType 构造 PlayerMediaSource |
| `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift` | **A2**: 新增 `episodeMediaSources` 状态字典；`fetchCurrentEpisodePlaybackURL()` 改用 `fetchPlayAsset` 并缓存 source；`playerItems(from:)` 优先使用缓存 source |
| `RelaxShort/PlayerKit/PlayerItemFactory.swift` | **A3**: `makePlaybackItem(from:)` MP4 一律直连，移除 cache scheme 条件分支 |
| `RelaxShort/PlayerKit/PlayerRecoveryController.swift` | **A4**: 新增 `failureCounts` 字典 + `maxRecoveryAttempts=3` 上限；`attemptRecovery` 检查计数；播放恢复时清除计数 |

## 根因分析

### CoreMediaErrorDomain -12882

**根因链：**
1. `ShortVideoPlayerEngine.startWarmCache` 预加载下一条时，通过 HTTP Range 请求把首段 1MB 写入 `HTTPRangeMediaCache`
2. `PlayerItemFactory.makePlaybackItem` 检测到 `hasPlayableLeadCache` 为 true，走 `makeManagedItem` → 将 URL scheme 改为 `relaxshort-cache://`
3. `PlayerResourceLoaderDelegate` 拦截 `relaxshort-cache://` 请求，但对于 `cdn.bjyoushi.top` 的 HTTP MP4（无 HLS 包装、无标准 Content-Range 语义的旧 CDN），loader 无法正确完成 `contentInformationRequest` 和 `finishLoading`
4. AVPlayer 在 cache scheme 加载失败后抛出 `CoreMediaErrorDomain -12882`，`CustomURLFlume` 报 `err=-12939`

### 无限 Recovery

**根因：** `PlayerRecoveryController.attemptRecovery` 没有任何失败次数上限。每次 `onFailed` / `onStalled` / `onNetworkChange` 都触发一次 recover → rebuild → 再次失败 → 再次 recover，形成死循环。

## 修复说明

### A1: 推荐卡片 MP4 fallback
- `FeedCardDTOMapper.toDramaItem` 的 `videoURL` 从仅 `hlsMasterUrl` 改为 `hlsMasterUrl ?? mp4FallbackUrl`
- 后端 V5 只填 `mp4_fallback` 不填 HLS 时，推荐页也能拿到播放 URL

### A2: 播放页使用真实 source type
- `PlaybackMediaSourceDTO.toPlayerMediaSource()` 根据 `sourceType`（`hls` / `mp4` / `hls_with_fallback`）构造正确的 `PlayerMediaSource` 枚举
- `SeriesPlayerView` 新增 `episodeMediaSources: [String: PlayerMediaSource]` 缓存
- `fetchCurrentEpisodePlaybackURL()` 调用 `fetchPlayAsset()` 获取完整 DTO 并保存 source
- `playerItems(from:)` 优先使用缓存的 source（含正确类型），fallback 才用 `ep.videoURL` 转 `.mp4`

### A3: MP4 强制直连
- `makePlaybackItem(from:)` 不再检查 `hasPlayableLeadCache`，对 MP4 一律走 `makeDirectItem`
- 添加诊断日志：`[PlayerKit] makePlaybackItem source=MP4 url=... strategy=direct leading=...`
- 预热缓存仍通过 `startWarmCache` 写入 `HTTPRangeMediaCache`，但不通过 cache scheme 代理播放
- `makeManagedItem` 保留供未来 HLS 或可信 CDN 使用

### A4: 防止无限 recovery
- 新增 `failureCounts: [String: Int]` 按 `PlayerMediaItem.id` 跟踪连续恢复失败次数
- `maxRecoveryAttempts = 3`
- `attemptRecovery` 开头检查计数，超过上限 → `engine.updateState(.failed(message: "连续恢复失败(N次)"))` 停止恢复
- `timeControlObs` 检测到 `.playing` 时清除当前 item 的失败计数

## 验证命令与结果

| 命令 | 结果 |
|------|------|
| `xcodebuild ... build` | ✅ **BUILD SUCCEEDED** |
| `xcrun simctl spawn booted defaults read com.relaxshort.ios use_real_api` | `1` ✅ |
| `xcrun simctl spawn booted defaults read com.relaxshort.ios api_base_url` | `http://127.0.0.1:8080` ✅ |

## 模拟器 UI smoke
⏭ 后端未运行，无法验证端到端播放。后端启动后预期：
- For You 第一条进入播放，Xcode 控制台应显示 `[PlayerKit] makePlaybackItem source=MP4 url=http://cdn.bjyoushi.top/videos/... strategy=direct`
- 不再出现 `CoreMediaErrorDomain -12882` 和无限 `recovery start`

## 遗留风险

1. **cache scheme 全局禁用**：MP4 一律直连意味着不再利用 HTTP 缓存代理。未来需要 cache scheme 时需确认 CDN 支持正确的 Content-Range / CORS 响应
2. **HLS fallback 未端到端测试**：HLS+MP4 fallback 路径在 engine 的 `setupItemStatusKVO` 中已有处理，但无真实 HLS 数据验证
3. **recovery cap 可能过于激进**：网络短暂闪断 3 次即停止，可能在某些差网络环境下过早放弃

---

# Task24 R2: For You play_asset 解码修复

> 日期：2026-06-22
> 目标：修复 For You feed 的 `play_asset` key 不匹配导致 `DramaItem.videoURL=nil`，`about:blank` 进入 PlayerKit

## R2 根因

**症状：**
```text
[PlayerKit] prepare: idx=0 id=20250312000001-1 gen=1 url=mp4(about:blank)
[PlayerKit] makePlaybackItem source=MP4 url=about:blank strategy=direct
```

**根因链：**
1. 后端 feed 快照 `play_asset_json` 的 key 是 `hls` 和 `mp4_fallback`（V5 迁移的 JSON_OBJECT）
2. iOS 全局 `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` 只把 `mp4_fallback` → `mp4Fallback`，不把 `hls` → `hlsMasterUrl`
3. `PlayAssetDTO` 属性名为 `hlsMasterUrl` / `mp4FallbackUrl`，与解码后的 key 不匹配 → 两个字段都是 `nil`
4. `FeedCardDTOMapper.toDramaItem` 的 `videoURL: card.playAsset?.hlsMasterUrl ?? card.playAsset?.mp4FallbackUrl` 为 `nil`
5. `DramaItem.videoURL = nil` → `toPlayerMediaItem()` 走 `?? .mp4(URL(string: "about:blank")!)` → `about:blank` 进入 AVPlayer → CoreMediaErrorDomain -12882

## R2 修改文件

| 文件 | 变更说明 |
|------|---------|
| `RelaxShort/Models/API/ForYouFeedResponseDTO.swift` | **Task A**: `PlayAssetDTO` 新增自定义 `CodingKeys`（`hls`/`hlsMasterUrl`/`mp4Fallback`/`mp4FallbackUrl`）和 `init(from:)`，兼容后端两类 key |
| `RelaxShort/Views/RecommendPage/VideoPlayerView.swift` | **Task B**: `toPlayerMediaItem()` 改为可失败（`PlayerMediaItem?`），检查 http/https scheme，跳过 `about:blank`；`initializePool` 改用 `compactMap` + 空检查 |
| `RelaxShort/Core/Services/RealHomeRepository.swift` | **Task C**: `toDramaItem` 先算 `resolvedVideoURL`，nil 时打印诊断日志 `missing playAsset url seriesId=...` |

## R2 验证

| 命令 | 结果 |
|------|------|
| `xcodebuild ... build` | ✅ **BUILD SUCCEEDED** |
| `curl ... /feed/for-you?limit=1&content_language=en` | ✅ `play_asset.hls` = `http://cdn.bjyoushi.top/videos/JIANG-NAN-SHI-JIE/.../20250312125604XjeM1.mp4` |
| `curl ... /feed/for-you?limit=1&content_language=en` | ✅ `play_asset.mp4_fallback` = 同上 MP4 |
| 模拟器 `use_real_api` | ✅ `1` |
| 模拟器 `api_base_url` | ✅ `http://127.0.0.1:8080` |

### R2 预期 Xcode 控制台日志

修复前：
```text
[PlayerKit] prepare: idx=0 id=20250312000001-1 gen=1 url=mp4(about:blank)
```

修复后（预期）：
```text
[PlayerKit] prepare: idx=0 id=20250312000001-1 gen=1 url=mp4(http://cdn.bjyoushi.top/videos/JIANG-NAN-SHI-JIE/2025/03/12/20250312125604XjeM1.mp4)
[PlayerKit] makePlaybackItem source=MP4 url=http://cdn.bjyoushi.top/videos/JIANG-NAN-SHI-JIE/2025/03/12/20250312125604XjeM1.mp4 strategy=direct
```

**说明**：后端已启动，feed 接口返回正确的 `play_asset.hls` 和 `play_asset.mp4_fallback`，均为真实 CDN MP4 URL。PlayAssetDTO 自定义解码器现在能将 `hls`→`hlsMasterUrl` 和 `mp4Fallback`→`mp4FallbackUrl`。模拟器 UI smoke 待用户运行 App 后在 Xcode 控制台确认不再出现 `about:blank`。

## R2 遗留风险

1. **模拟器 UI smoke 未跑**：App 需在模拟器中运行以确认第一条 prepare 日志中的 URL 已变为真实 CDN MP4
2. **AVPlayer HTTP MP4 兼容性**：即使 URL 正确，AVPlayer 对 HTTP（非 HTTPS）MP4 可能有额外限制。如果仍无法播放但 URL 正确，需检查 ATS 配置和 AVPlayer 错误日志
3. **about:blank 防护覆盖**：当前只修了 `VideoPlayerView.toPlayerMediaItem()`；`SeriesPlayerView.playerItems(from:)` 没有同样的 about:blank 问题（它有 `guard let url = URL(string: ep.videoURL)`），但如果其他地方直接构造 `.mp4(url)` 仍需注意
