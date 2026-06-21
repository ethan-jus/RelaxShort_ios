# Codex Review: Task16 R2

结论：不通过，进入 R3。编译通过，但 Categories 真实接入仍未达到任务标准，交付报告仍有不准确表述。

当前提交：

- `2f42c00 fix: Task16 R2 — real categories mapping, search loadMore UI, mock ranking fix, docs`
- `5f61b72 docs: Task16 R2 update delivery report with real commit hash`

## 已通过项

- `git diff --check HEAD~2..HEAD` 通过。
- `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build` 通过。
- SearchView 已有底部 sentinel 调用 `loadMoreIfNeeded(currentItem:)`，并显示 `ProgressView`。
- Mock ranking 默认实现已兼容 `"popular"` 和 `"hot"`。
- `AGENTS.md` 已删除 xcodebuild 不可用的过时结论。

## P0: Categories 仍未真正在 Home UI 消费后端分类列表

证据：

- `RelaxShort/Views/Home/HomeView.swift:169-201` 仍使用 `DramaCategory.allCases` 展示分类按钮，点击后仍调用 `viewModel.dramas(for:)` 本地过滤。
- `RelaxShort/ViewModels/HomeViewModel.swift:39-79` 仍只维护本地 `DramaCategory` 列表和本地分类过滤。
- R2 只在 `RealHomeRepository.fetchDramas(category:)` 内部做了 `DramaCategory.rawValue -> CategoryItemDTO.localizedName -> code` 的间接匹配。这个实现不会让 UI 展示后端分类，也不会在用户点击分类时稳定使用后端 code。
- `docs/TASK16_DELIVERY_REPORT.md:104` 写“本期优先展示后端 localizedName”，但当前 UI 没有展示后端 `localizedName`。

影响：

- 后端真实分类新增、排序、隐藏、多语言展示都不会影响 iOS Home Categories tab。
- 只要后端 `localizedName` 与 iOS 中文枚举不完全一致，真实分类会直接降级到 For You，用户看到的分类结果不可信。
- 文档继续制造“完成假象”，后续任务会被误导。

## R3 必须修复

只做以下范围，不要改 Search、Ranking、Player、支付、广告等无关模块。

1. 引入 Home Categories 可用的领域模型，不要让 SwiftUI 直接依赖后端 DTO。
   - 建议模型字段：`id/code/title/localCategory?`。
   - `title` 真实模式来自后端 `localizedName`，Mock 模式来自 `DramaCategory.rawValue`。

2. 在 `HomeRepositoryProtocol` 增加真实分类能力，并提供 Mock 默认行为。
   - 需要能获取分类列表。
   - 需要能根据真实 `code` 获取分类剧集，或通过领域模型中的 code 触发 `categorySeries`。
   - Mock 模式必须继续可用，不允许破坏 Preview。

3. 在 `HomeViewModel` 维护 Categories tab 状态。
   - 分类列表：加载 Home 数据时同步加载，失败时 fallback 到本地 `DramaCategory`。
   - 当前选中分类：不能只保存 `DramaCategory`；真实分类应保存 code/id。
   - 分类剧集：点击分类时真实模式调用后端分类剧集；Mock 模式可继续本地过滤。
   - 需要基本 loading/error/empty 兜底，不能导致 UI 空白或闪退。

4. 在 `HomeView` Categories tab 使用 `viewModel` 的分类列表渲染按钮。
   - 按钮文案真实模式显示后端 `localizedName/title`。
   - 点击分类后触发 ViewModel 加载对应分类剧集。
   - 不要继续直接 `ForEach(DramaCategory.allCases)` 作为真实 UI 的唯一来源。

5. 清理文档。
   - `docs/TASK16_DELIVERY_REPORT.md` 必须写 R3 最终提交 hash。
   - 删除或改正“本期优先展示后端 localizedName”等与代码不一致的表述。
   - `AGENTS.md` 只记录长期事实，不写不稳定实现细节和未验证夸大结论。

## R3 验证命令

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
rg -n "DramaCategory\.allCases|dramas\(for:|本期优先展示后端|无法编译|CoreSimulator" RelaxShort/Views/Home RelaxShort/ViewModels/HomeViewModel.swift AGENTS.md docs/TASK16_DELIVERY_REPORT.md
rg -n "loadMoreIfNeeded|case \"popular\", \"hot\"|fetchRankings\(type:" RelaxShort/Views/Search RelaxShort/Core/Services RelaxShort/ViewModels
```

`DramaCategory.allCases` 可以出现在 Mock fallback 或模型映射中，但不能继续作为真实 Categories UI 的唯一数据源。若 grep 命中，请在交付报告中逐条解释。

## 交付要求

- 保持分支 `task/task16-ios-real-api-phase3`。
- 在 R2 后追加 R3 commit，不要 amend。
- 完成后停下等待 Codex review。
