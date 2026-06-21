# Task 16 R2 交付报告：iOS Real API Phase 3 返工

**分支**: `task/task16-ios-real-api-phase3`
**R1 提交**: `06a05fb` | **R2 提交**: （本次）
**日期**: 2026-06-21

## 执行摘要

按 `docs/CC_TASK16_IOS_REAL_API_PHASE3.md` 完成 Search 真实分页、Search Default 真实数据源、Ranking 协议调用后端、Categories code 映射、错误态/空态可见处理。

## 修改文件清单

| 文件 | 变更 |
|------|------|
| `RelaxShort/Core/Services/RepositoryProtocols.swift` | HomeRepositoryProtocol 新增 `fetchRankings(type:)` + 默认协议扩展（本地排序降级） |
| `RelaxShort/Core/Services/RealHomeRepository.swift` | `fetchDramas` 扩展 Home/categories 分支；新增 Categories DTO |
| `RelaxShort/ViewModels/SearchViewModel.swift` | 新增分页状态（`nextCursor`/`hasMore`/`isLoadingMore`/`loadMoreIfNeeded`）；关键词变化重置分页；失败不清空结果 |
| `RelaxShort/ViewModels/SearchDefaultViewModel.swift` | 新增 `searchRepository` 依赖；真实模式优先 `RealSearchRepository.fetchDramas`（走 search/default）；Mock 保留 Home 本地排序 |
| `RelaxShort/ViewModels/RankViewModel.swift` | 改为通过 `fetchRankings(type:)` 协议调用后端 rankings；新增 `mapToRankingType()` 映射 |
| `RelaxShort/Views/Search/SearchView.swift` | SearchDefaultViewModel 初始化传入 `searchRepository` |
| `RelaxShort/Views/Search/SearchDefaultView.swift` | Preview 初始化适配新 SearchDefaultViewModel 构造器 |
| `RelaxShort/Core/Services/MockAPIRepository.swift` | MockSearchRepository.search 支持分页（cursor page + hasMore） |
| `AGENTS.md` | 更新 Task16 合并后状态 |

## Search 分页行为

| 状态 | 行为 |
|------|------|
| 新搜索 | `resetPagination()`，`cursor=nil`，请求 20 条 |
| 滚动到底 | `loadMoreIfNeeded(currentItem:)` 检查是否为最后一条 + `hasMore`，触发下一页 |
| 关键词变化 | 自动 `resetPagination()`，重新搜索 |
| 网络失败 | 不清空已有结果，`errorMessage` 显示；可重试 |
| Mock 模式 | `cursor` 传 page number，按 page×limit 偏移分页 |

## Ranking type 映射

| iOS RankCategory | 后端 type 参数 | 调用路径 |
|-----------------|---------------|---------|
| `.hot` (热播榜) | `popular` | `repository.fetchRankings(type: "popular")` |
| `.trending` (热搜榜) | `trending` | `repository.fetchRankings(type: "trending")` |
| `.new` (新剧榜) | `new` | `repository.fetchRankings(type: "new")` |

Mock 模式走协议默认扩展（全量本地排序）；Real 模式走 `RealHomeRepository.fetchRankings()`。

## Categories code 映射（Task16 R2 真实实现）

- 真实模式：`RealHomeRepository.fetchCategories()` → `/api/v2/categories` 获取后端 `CategoryItemDTO`（code/localizedName）
- `matchCategoryCode()` 将 iOS `DramaCategory` 中文枚举值（如 "现代言情"）匹配后端 `localizedName`，匹配成功则用 code 调 `categorySeries`
- 匹配失败或 API 不可用时降级到 For You
- Mock 模式：继续使用 `DramaCategory` 中文枚举本地过滤
- Gap：匹配依赖后端 `localizedName` 与 iOS 中文枚举完全一致（如 "现代言情"），若后端返回不同写法则匹配失败

## 错误态和空态

| 页面 | 错误态 | 空态 | 重试 |
|------|--------|------|------|
| Home | `errorMessage` 文案 + 空 UI | 空态兜底 | 无按钮（`loadData` 在 task 中自动重试） |
| Search | `errorMessage` 文案，已搜索结果不清空 | 放大镜图标 +"无搜索结果" | 重新输入关键词自动重试 |
| Search Default | `errorMessage` + `L10n.retry` 按钮 | Tab 内"暂无数据" | 有重试按钮 |
| Ranking | `errorMessage` + 保持旧数据 | "暂无排行数据" | 切换分类自动重试 |

## 验证

```bash
$ git diff --check
（通过）

$ xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
    -destination 'platform=iOS Simulator,name=iPhone 17' build
** BUILD SUCCEEDED **

$ rg -n "SearchView\\(|RankView\\(|SearchViewModel\\(repository: MockSearchRepository|SearchDefaultViewModel\\(repository: MockHomeRepository|RankView\\(playerDrama:.*MockHomeRepository" RelaxShort
（仅 Preview/测试样例出现 Mock 硬编码，主运行入口无）
```

## ECC 使用记录

| ECC 能力 | 可用？ | 说明 |
|----------|--------|------|
| `/plugin list ecc@ecc` | ❌ | VSCode 扩展环境不支持 |
| Explorer agent（2 个并行） | ✅ | 读取全部 ViewModel/View/Repository 源码 |
| java-reviewer（手工） | ✅ | 审计协议扩展 Mock/Real 双实现 |
| grep 自检（手工） | ✅ | `rg` 搜索主入口硬编码 Mock 引用 |

## R2 修复清单

| 等级 | 问题 | 修复 |
|------|------|------|
| **P0** | Categories code 映射文档声称完成但未实现 | 真实实现：`RealHomeRepository.fetchDramas` 非 `.all` 时通过 `matchCategoryCode()` 匹配后端 categories localizedName→code，再调 `categorySeries`；降级走 For You |
| **P1** | SearchView 无 `loadMoreIfNeeded` 触发路径 | `ScrollView` 内加 `LazyVStack`，底部 `Color.clear.onAppear` 触发加载更多 + `isLoadingMore` 时显示 `ProgressView` |
| **P1** | Mock ranking 默认实现只处理 `hot`，不处理 `popular` | `fetchRankings` 默认扩展 `"popular", "hot"` 合并为同一 case（播放量降序） |
| **P1** | AGENTS.md 写 xcodebuild 不可用 | 修正为当前事实：本机 xcodebuild 已通过 |
| **P2** | 交付报告 hash 为空 | R2 填入真实 commit hash |

## 真实遗留问题

1. **Categories code 双向映射表**：后端 `rs_categories.code`（英文）与 iOS `DramaCategory`（中文枚举）无完整 1:1 映射表。本期优先展示后端 `localizedName`，后续需建映射
2. **Search Default 三榜来源**：真实模式走 `search/default` 的 `hot_series`（单榜），三榜内容相同；后续后端若补三榜数据可对齐
3. **Ranking 类型参数**：`popular`/`trending`/`new` 映射基于 API 合同约定，未经真实后端联调验证
4. **AGENTS.md** 已同步 Task16 事实；CLAUDE.md 保持 Task13 版本不变
