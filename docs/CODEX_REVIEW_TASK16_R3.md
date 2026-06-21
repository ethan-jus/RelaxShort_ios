# Codex Review: Task16 R3

结论：不通过，进入 R4。R3 已经让 Home Categories UI 消费 `viewModel.categories`，并且 `xcodebuild` 通过；但仍有两个真实行为问题和交付报告失真。

当前提交：

- `baec6cf fix: Task16 R3 — real Home Categories UI, domain model, backend-driven`

## 已通过项

- `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build` 通过。
- `HomeView` 不再直接用 `DramaCategory.allCases` 渲染真实 Categories UI。
- 新增 `HomeCategory` 领域模型，避免 SwiftUI 直接依赖后端 DTO。
- 后端分类 code 可以通过 `RealHomeRepository.fetchDramasByCategoryCode(code:)` 调用 `categorySeries`。

## P1: 默认高亮分类与默认展示内容不一致

证据：

- `HomeViewModel.selectedCategoryIndex` 默认是 `0`。
- `HomeView.swift:174-186` 会把 index 0 的分类按钮显示为选中态。
- `HomeView.swift:211` 在 `categoryDramas` 为空时展示 `featuredOrEmpty`。
- `HomeViewModel.loadData()` 设置 `categories` 后没有加载 index 0 对应分类剧集。

影响：

- 进入 Categories tab 时，第一个后端分类被视觉高亮，但网格展示的是首页 featured 内容，不是该分类内容。
- 用户第一次看到的分类页数据不可信。

R4 要求：

- 分类列表加载完成后，要么自动加载 index 0 的分类剧集，要么不要高亮任何分类。
- 推荐方案：`categories` 非空后调用同一条 `selectCategory(at: 0)` 路径，让默认高亮和默认内容一致。
- 如果 categories 为空，明确 fallback 到 `featuredDramas`，不要出现空按钮 + 误选中状态。

## P1: 真实 categories 失败后的本地 fallback 会被当成真实 code 调后端

证据：

- `HomeViewModel.loadData()` 中 `repository.fetchHomeCategories()` 失败后 fallback 到本地 `DramaCategory.allCases.map`，这些 `HomeCategory.localCategory` 非空，`code` 是中文 rawValue。
- 但 `loadCategoryDramas(for:)` 先判断 `DependencyContainer.useRealAPI && repository as? RealHomeRepository`，再判断 `localCategory`。
- 因此真实模式下 fallback 出来的本地分类仍会调用 `fetchDramasByCategoryCode(code:)`，把 `"现代言情"`、`"古装"` 等中文 rawValue 当后端 code 传给 `/api/v2/categories/{code}/series`。

影响：

- categories API 失败时，fallback 不是可用降级，而是会继续打错误 code 的真实接口。

R4 要求：

- 如果 `HomeCategory.localCategory != nil`，应优先走本地过滤 fallback。
- 只有 `localCategory == nil` 的真实后端分类，才允许用 `category.code` 调 `categorySeries`。
- 保持 Mock 模式和 Preview 可用。

## P1: 交付报告仍然混杂 R2 旧事实和 R3 新事实

证据：

- `docs/TASK16_DELIVERY_REPORT.md:1` 标题仍写 `Task 16 R2`。
- `docs/TASK16_DELIVERY_REPORT.md:15-23` 修改文件清单是 R1/R2 旧清单，缺少 `HomeCategory.swift`、`HomeView.swift`、`HomeViewModel.swift` 的 R3 真实改造说明。
- `docs/TASK16_DELIVERY_REPORT.md:45-51` 仍写 `Task16 R2 真实实现` 和 `matchCategoryCode()`，没有准确描述 R3 的 `HomeCategory` + `fetchHomeCategories()` + `fetchDramasByCategoryCode()`。
- `docs/TASK16_DELIVERY_REPORT.md:74-95` 代码块结构混乱，grep 命中说明和 Preview 命中说明混在同一个 fenced block 里。

R4 要求：

- 把标题改成 `Task 16 R3/R4 交付报告` 或等价准确标题。
- 修改文件清单必须覆盖本次最终代码实际改动。
- Categories 段必须描述最终 R4 行为，不再保留 R2 间接匹配作为主实现。
- 验证区只写实际运行过的命令和真实结果；grep 命中要逐条解释。
- R4 commit 后回填真实 R4 hash，不允许占位。

## P2: ViewModel 仍依赖具体 RealHomeRepository

`HomeViewModel` 当前通过 `repository as? RealHomeRepository` 调真实分类 code 接口。当前功能可运行，但协议边界不干净。R4 可以暂不重构；后续应把“按 HomeCategory/code 拉剧集”的能力收进 `HomeRepositoryProtocol`。

## R4 验证命令

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
rg -n "DramaCategory\.allCases|dramas\(for:|本期优先展示后端|无法编译|CoreSimulator|R[34] 提交.*本次|Task 16 R2|Task16 R2 真实实现|matchCategoryCode" RelaxShort/Views/Home RelaxShort/ViewModels/HomeViewModel.swift AGENTS.md docs/TASK16_DELIVERY_REPORT.md
```

允许 `DramaCategory.allCases` 只出现在 Mock/local fallback；如果命中其他位置，必须解释或修复。

## 交付要求

- 保持分支 `task/task16-ios-real-api-phase3`。
- 在 `baec6cf` 后追加 R4 commit，不要 amend。
- 完成后停下等待 Codex review。
