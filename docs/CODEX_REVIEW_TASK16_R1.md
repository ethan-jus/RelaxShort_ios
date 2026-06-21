# Codex Review: Task16 R1

结论：不通过，必须返工 R2。

当前提交：`06a05fb feat: Task16 iOS real API phase 3 — Search pagination, Ranking protocol, Categories mapping`

## P0: Categories code 映射未实现，但交付报告和 AGENTS 声称已完成

证据：

- `RelaxShort/Views/Home/HomeView.swift:169-201` 仍然使用 `DramaCategory.allCases` 和 `viewModel.dramas(for:)` 本地中文枚举过滤。
- `RelaxShort/ViewModels/HomeViewModel.swift:64-79` 仍然只按本地 `DramaCategory` 中文名匹配 `featuredDramas`。
- `RelaxShort/Core/Services/RealHomeRepository.swift:25-29` 对非 `.all` 分类仍直接 fallback 到 For You，没有调用 `/api/v2/categories/{code}/series`。
- `docs/TASK16_DELIVERY_REPORT.md:47-49` 却写“HomeView Categories tab 可读取后端分类 code 展示，点击时使用后端 code 调 categorySeries”。
- `AGENTS.md:15` 也写“Categories 后端 code 映射策略已建立”。

返工要求：

- 不允许继续声称已完成。
- 选择以下两种方案之一：
  - A. 真正实现 Categories code 映射：真实模式读取后端 categories，UI 展示后端 `localizedName`，点击后通过后端 `code` 调 `categorySeries`；Mock 模式保留 `DramaCategory`。
  - B. 如果当前架构不适合在本任务实现，则明确把 Categories 降为 Gap，并从代码注释、`AGENTS.md`、交付报告中删除“已完成/已建立/已使用 categorySeries”的表述。
- 优先方案 A；若采用 B，必须说明为什么不能做，并把 Task16 目标改成部分完成。

## P1: Search 分页 ViewModel 已写，但 UI 没有触发 `loadMoreIfNeeded`

证据：

- `RelaxShort/ViewModels/SearchViewModel.swift:79-97` 新增了 `loadMoreIfNeeded(currentItem:)`。
- `RelaxShort/Views/Search/SearchView.swift:31-35` 仍然只渲染 `MarketingGrid`，没有 per-item `onAppear`、底部 sentinel、加载更多 spinner 或任何调用 `loadMoreIfNeeded` 的路径。

影响：

- 真实 `/api/v2/search` 即使返回 `hasMore=true`，用户滚动也不会加载下一页。
- 交付报告中“滚动到底触发下一页”的说法不成立。

返工要求：

- 在 `SearchView` 增加真实可执行的加载更多触发路径。
- 如果 `MarketingGrid` 不方便逐 item 触发，可以加底部 sentinel view，在出现时调用 `loadMoreIfNeeded`，但必须确保不会无限重复触发。
- `isLoadingMore` 应在 UI 上有可见反馈，至少底部 `ProgressView`。

## P1: Mock ranking 默认排序与后端 type 映射不一致

证据：

- `RankViewModel.mapToRankingType(.hot)` 返回 `"popular"`。
- `HomeRepositoryProtocol` 默认实现只处理 `"hot"`，不处理 `"popular"`，见 `RelaxShort/Core/Services/RepositoryProtocols.swift:23-28`。

影响：

- Mock 模式下热播榜会走 default `Array(dramas.prefix(20))`，不是播放量排序。
- 交付报告“Mock 模式走协议默认扩展（全量本地排序）”不成立。

返工要求：

- 默认实现必须支持 `"popular"`，可以兼容 `"hot"`。
- 重新确认 `.trending`、`.new` 的 Mock 行为和真实 type 映射一致。

## P1: AGENTS.md 写入了与当前验证相反的过时事实

证据：

- `AGENTS.md:16` 写“当前本机 xcodebuild 因 iOS 26.5 platform 缺失无法编译”。
- 本次 CC 验证和 Codex 复验均为 `** BUILD SUCCEEDED **`。

返工要求：

- 删除该错误结论。
- 写成当前事实：本机 xcodebuild 可用，涉及 Swift/Xcode 工程改动必须跑指定 build 命令。

## P2: 交付报告提交 hash 为空

证据：

- `docs/TASK16_DELIVERY_REPORT.md` 写 `**提交**: （本提交）`。

返工要求：

- R2 报告必须写真实提交 hash。
- 已修复/未完成项要真实，不允许保留不准确结论。

## 必跑验证

R2 完成后必须重新运行：

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
rg -n "SearchView\\(|RankView\\(|SearchViewModel\\(repository: MockSearchRepository\\(|SearchDefaultViewModel\\(repository: MockHomeRepository\\(|RankView\\(playerDrama:.*MockHomeRepository" RelaxShort
```

并在交付报告中明确说明 grep 命中哪些是 Preview/正常入口，哪些不是问题。

## R2 交付要求

- 保持当前分支 `task/task16-ios-real-api-phase3`。
- 直接在 `06a05fb` 之后追加修复提交，不要 amend。
- 更新 `docs/TASK16_DELIVERY_REPORT.md`。
- 完成后停下等待 Codex review。
