# Codex Review: Task13 R2 iOS Real API Phase 1

**结论**: 不通过，需 R3 小范围返工。

R2 已修复一部分关键问题：新增 Swift 文件已加入 `RelaxShort.xcodeproj` Sources，`APIClient` 网络错误映射已恢复，`SeriesPlayerView` 也开始通过 `DependencyContainer.detailRepository` 加载剧集。但当前仍有确定的编译级错误和真实播放路径风险，不能合并。

## 必改问题

### P0: `Episode.videoURL` 是 `let`，但 SeriesPlayerView 尝试赋值，当前会编译失败

- `RelaxShort/Models/Episode.swift:14`
- `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift:165`

当前 `Episode` 定义：

```swift
let videoURL: String
```

R2 代码：

```swift
episodes[epIndex].videoURL = url
```

这是确定的 Swift 编译错误。由于本机 `xcodebuild` 被 CoreSimulator 缺失阻断，编译器没有跑到这一步，但静态代码已经能确认问题。

R3 要求：

- 二选一：
  - 将 `Episode.videoURL` 改为 `var videoURL: String`，并确认所有现有初始化/Hashable/Codable 使用不受影响。
  - 或者保持 `Episode` 不可变，用复制替换方式更新数组中的元素。
- 交付报告必须说明选择哪种方案。

### P0: 真实 For You 卡片 `episodeCount=0`，进入 SeriesPlayerView 后分页边界不可靠

- `RelaxShort/Core/Services/RealHomeRepository.swift:51`
- `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift:37-42`
- `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift:231-234`

真实 For You 映射当前写死：

```swift
episodeCount: 0
```

但 `SeriesPlayerView` 初始化时使用：

```swift
private var totalEpisodes: Int
self.totalEpisodes = drama.episodeCount
```

然后分页逻辑依赖 `totalEpisodes`。真实 API 模式下，从 For You 点进播放页时 `totalEpisodes=0`，而 `currentEpisode` 至少为 1，`visibleEpisodeIndices()` 会得到不合理区间。即使剧集列表后续加载到了，`totalEpisodes` 也不会随 `episodes.count` 更新。

R3 要求：

- `SeriesPlayerView` 的总集数必须在真实剧集列表加载后更新，或改为从 `episodes.count` 派生，而不是只用初始化时的 `drama.episodeCount`。
- For You 映射可以继续默认 `episodeCount=0`，但播放器必须能处理这个真实场景。
- `visibleEpisodeIndices()` 必须防御 `episodes.isEmpty` / `totalEpisodes <= 0`，不能构造无效范围。

### P1: 交付报告仍保留已修复问题为“未完成事项”

- `docs/TASK13_DELIVERY_REPORT.md:126-135`

R2 修复清单说 `SeriesPlayerView` 已通过 `DependencyContainer` 接入 `RealDetailRepository`，但未完成事项仍写：

> 播放页 SeriesPlayerView 未改为调用 RealDetailRepository

这会误导后续任务判断。

R3 要求：

- 清理过时未完成项。
- 保留真实未完成事项，例如 `xcodebuild` 环境问题、cursor 分页尚未完整实现、后端缺展示字段等。

### P2: AGENTS/CLAUDE 恢复位置与计划不一致

当前恢复在：

- `RelaxShort/AGENTS.md`
- `RelaxShort/CLAUDE.md`

原 Task13 计划要求在 iOS 仓库根目录：

- `AGENTS.md`
- `CLAUDE.md`

R3 要求：

- 将规则文件恢复到仓库根目录，或在交付报告中明确说明为什么放在 `RelaxShort/` 子目录，并保证后续代理进入仓库时能读到。
- 建议按原计划放回仓库根目录。

## 已确认通过的 R2 项

- 新增 Swift 文件已经加入 `RelaxShort.xcodeproj` 的 Sources。
- `APIClient.requestRaw()` / `requestArray()` 已恢复 `NetworkError.from(error)`。
- `SeriesPlayerView` 已开始从 `dependencies.detailRepository` 加载 episodes。
- `git diff --check` 通过。

`xcodebuild` 仍因本机缺少 `CoreSimulator.framework` 失败，属于环境问题；R3 仍需记录该失败。

## R3 验收标准

1. 修复 `Episode.videoURL` 赋值导致的编译错误。
2. 修复真实 For You `episodeCount=0` 进入播放器后的分页边界问题。
3. 清理交付报告的过时未完成事项。
4. 将 `AGENTS.md` / `CLAUDE.md` 放回仓库根目录，或给出明确理由。
5. 执行并记录：

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'generic/platform=iOS Simulator' build
```

如果 `xcodebuild` 仍因 CoreSimulator 缺失失败，保留完整错误摘要即可。
