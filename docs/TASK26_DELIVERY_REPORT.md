# Task26 For You / Series Player UI Polish — Delivery Report

> 日期：2026-06-23
> R1: 2026-06-23 initial | **R2: 2026-06-23 Codex review 返工**

## R2 修改文件（增量）

| 文件 | 变更 | 说明 |
|------|------|------|
| `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift` | 重写核心 | **P0**: `switchToEpisode` 先拉真实 play asset 再 prepare/play；`EpisodePlayableItem` + `buildPlayableItems` + `ensurePlayAsset`；**P1**: 单一 `PlayerSheet` enum router（`.sheet(item: $activeSheet)`）替代 4 个 `.sheet(isPresented:)`；**P1**: `EpisodePickerSheet` 改为 6 列 + range tabs（30集一组）+ poster header + playing bars + lock badge；**P2**: 删除 `currentQualityLabel()` 死参数，`qualityOptions()` 标注 fallback |
| `RelaxShort.xcodeproj/project.pbxproj` | 修改 | 添加 `PlayerOptionSheets.swift` 到 app target |

## R1 已修改文件（保留）

| 文件 | 说明 |
|------|------|
| `RelaxShort/Views/RecommendPage/VideoPlayerView.swift` | `RecommendPlayableItem` struct；For You index 映射 |
| `RelaxShort/Views/RecommendPage/RecommendView.swift` | For You 暂停态中央圆形播放按钮 |
| `RelaxShort/Views/RecommendPage/PlayerOptionSheets.swift` | 新增：Speed/Quality/More 三个底部 sheet |

## R2 根因与修复

### P0: Series Player 切集播放源

**R1 问题**：`handleEpisodeTransition` 先 `engine.move(to: episodeNumber - 1)`（用 episodeNumber 做 index，错误），然后异步 `fetchPlayAssetForEpisode`，不重建 engine items。

**R2 修复**：
- `switchToEpisode(episodeNumber)` 先锁检查，再 `ensurePlayAsset(for:)` 阻塞等待真实源
- 无缓存时调用 `RealDetailRepository.fetchPlayAsset(episodeId:)`
- `buildPlayableItems(from:)` 从 `sourceForEpisode` 构造 `EpisodePlayableItem` 列表（保证 playable index 安全）
- `engine.prepare(items: playable.map(\.item), index: playableIndex)` 用正确索引

### P1: 6 列剧集 Sheet

**R2 修复**：
- 6 列 Grid（原 5 列）
- Range tabs：30 集一组（`1-30`、`31-60`…）
- Poster header（封面 + 标题 + views + rating）
- 当前集：粉色高亮 + 左下角 playing bars 动画
- 锁定集：右上角 lock badge（`drama.freeEpisodeRange ?? 1...3`）
- 点击已解锁集 → `onSelectEpisode(ep)` → `switchToEpisode(ep)`

### P1: 单一 Sheet Router

**R1 问题**：4 个独立 `.sheet(isPresented:)` modifier，`PlayerMoreSheet.onQuality` 里 `dismiss()` + `showQualitySheet = true` 导致 SwiftUI 丢 presentation。

**R2 修复**：`PlayerSheet` enum（`.share`/`.speed`/`.quality`/`.more`），单一 `.sheet(item: $activeSheet)`。More→Quality 用 `activeSheet = nil` + `DispatchQueue.main.asyncAfter` 延迟 0.25s 再 set。

### P2: Quality fallback & Package.resolved

- Package.resolved 未被删除（`git status` 确认）✅
- `currentQualityLabel()` 死参数已删除
- `qualityOptions()` 注释标注「fallback UI，无多码率数据」

## 验证

| 命令 | 结果 |
|------|------|
| `xcodebuild ... build` | ✅ **BUILD SUCCEEDED** |
| `git status --short` | 无 `Package.resolved` 删除 ✅ |
| `curl /feed/for-you` | ✅ play_asset 含真实 CDN MP4 |

## 遗留风险

1. **Quality 为 fallback UI**：未绑定 `engine.selectQuality()`，选项 Auto/720p/1080p(disabled)/540p 为静态
2. **Download / Join membership UI-only**：点击打印日志，无真实操作
3. **More sheet Subtitles / Report disabled**：点击无操作
4. **pbxproj ShareSheet 行缩进偏差**：1 行 tab 数少 3，xcodebuild 通过但格式化不完美（P2 已验证无功能影响）
5. **无后端改动**

---

# R3: UI 小范围返工 (2026-06-23)

## R3 修改文件

| 文件 | 变更 |
|------|------|
| `RelaxShort/Views/RecommendPage/RecommendView.swift` | **Fix 1**: 删除 Task26 新增的中央播放按钮（与 `ShortVideoPlayerView` 内置按钮重复导致双外圈）；**Fix 2**: `synopsisView` 仅当 `shouldShowMore(for:)` (trimmed count > 90) 时显示 `... more`；**Fix 3**: `pageBottomOverlay` 响应式宽度：`horizontalPadding=16`、`actionRailWidth=50`、`actionRailGap=max(18, width*0.055)`、`contentWidth=min(maxContentWidth, width*0.74)`、`tabBarAvoidance=safeArea.bottom+70` |
| `RelaxShort/Views/Components/DramaBoxBottomTabBar.swift` | **Fix 4**: tab button hit area 35→44、icon 18→20、文字 12→11、间距 3→4、底部固定视觉 padding=8，不手动叠加 safe area |
| `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift` | **Fix 6**: 拖动切集改用 `requestEpisodeSwitch(target)` 不直接设置 `currentEpisode`；`switchToEpisode` 加 `episodeNumber != currentEpisode` guard 防 onChange 循环；锁定/失败时 `currentEpisode` 不变 |

## R3 根因

| 问题 | 根因 | 修复 |
|------|------|------|
| 暂停双外圈 | RecommendView + ShortVideoPlayerView 各画一个 play button | 删除 RecommendView 的重复按钮，复用 ShortVideoPlayerView 内置 |
| 短简介出现 `... more` | 无条件拼接 `... more`，不管是否截断 | `shouldShowMore(for:)`: trimmed count > 90 才显示 |
| 文案区拥挤 | actionRailGap=10、contentWidth 无上限 | 响应式 gap=max(18, w*0.055)、maxWidth=w*0.74 |
| tab bar 太矮 | button hit area=35 | 保留 44pt 最小点击热区，底部栏由 SwiftUI 系统 safe area 自动定位，组件内部只加固定视觉 padding |
| 切集失败 currentEpisode 跳错 | 拖动直接改 currentEpisode → onChange → switchToEpisode | requestEpisodeSwitch 只在成功时设置 currentEpisode |

## R3 验证

| 命令 | 结果 |
|------|------|
| `xcodebuild ... iPhone 17` | ✅ BUILD SUCCEEDED |
| `xcodebuild ... iPhone 17 Pro Max` | ✅ BUILD SUCCEEDED |
| `git diff --check` | ✅ 无输出 |

---

# R4: 小返工 (2026-06-23)

## R4 修改

| 文件 | 变更 |
|------|------|
| `SeriesPlayerView.swift` | **P1**: `ensurePlayAsset` 三层回退：① cached source → ② episode.videoURL（Mock）→ ③ RealDetailRepository.fetchPlayAsset（Real）。Mock 模式不再因缺少 RealDetailRepository 返回 false |
| `SeriesPlayerView.swift` | **P1**: `EpisodePickerSheet.onUnlock` 保存 `pendingLockedEpisode = ep`，解锁后 `playUnlockedPendingEpisode` 能读取目标集并调用 `switchToEpisode(pending)` |
| `RecommendView.swift` | `shouldShowMore(for:contentWidth:)` 按 `(contentWidth / 7.5) * 2` 估算两行容量，替代硬编码 90 |

## R4 验证

| 命令 | 结果 |
|------|------|
| `xcodebuild ... iPhone 17` | ✅ BUILD SUCCEEDED |
| `git diff --check` | ✅ clean |

---

# Codex Follow-up: 通知弹窗与底部栏修正 (2026-06-23)

## 修改

| 文件 | 变更 |
|------|------|
| `RecommendView.swift` | 删除 For You 自动弹出的 `Turn on Notifications` 自定义通知弹窗，包括状态、延迟触发和 `NotificationPromptView`。通知引导后续作为独立任务重新设计 |
| `DramaBoxBottomTabBar.swift` | 删除 `bottomInset` 参数，恢复 `.frame(height: 44)` 点击热区，底部只保留固定视觉 padding=8，避免 safe area 重复叠加 |
| `MainTabView.swift` | 删除外层 `GeometryReader` 和手动 `.frame(width:height:)`，底部栏不再接收 `geo.safeAreaInsets.bottom`，由系统自动把栏放在安全区内 |
| `RecommendView.swift` | For You 底部浮层改为避让 `UIApplication.safeAreaInsets.bottom + DramaBoxBottomTabBar.totalHeight`，进度条底部对齐底部栏顶部，标题/按钮/右侧操作栏整体同步上移 |
| `RecommendView.swift` | 简介 `... more` 改为按实际 13pt 文本两行高度测量，并用二分截断适配不同屏宽，避免字符数估算造成短文也显示 more |
| `RecommendView.swift` | 非拖动状态进度条布局高度从 32 收到 14，让 `Watch Full Series` 内容组自然下移贴近进度线；按钮圆角从 5 收到 3，视觉更利落 |

## 验证

| 命令 | 结果 |
|------|------|
| `rg "Turn on Notifications|NotificationPromptView|showNotificationPrompt|hasShownNotification" RecommendView.swift` | ✅ 无结果 |
| `rg "bottomInset|GeometryReader" MainTabView.swift DramaBoxBottomTabBar.swift` | ✅ 无结果 |
| `git diff --check` | ✅ clean |
| `xcodebuild ... iPhone 17` | ✅ BUILD SUCCEEDED |

## 布局决策

- `DramaBoxBottomTabBar.totalHeight = topPadding(8) + itemHitHeight(44) + bottomPadding(8)` 是底部栏高度唯一来源。
- `MainTabView` 不手动传 safe area，底部栏由 SwiftUI 系统 safe area 自动定位。
- `RecommendView` 是全屏沉浸式页面，会忽略 safe area，因此 For You 底部浮层用真实 window safe area 加底部栏高度避让，避免内部 `GeometryReader.safeAreaInsets.bottom` 在 `.ignoresSafeArea()` 后变为 0。
