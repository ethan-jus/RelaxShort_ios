# CC Task16: iOS Real API Phase 3

## 背景

当前 iOS `main` 已合并到 `3f6ed81`：

- Task13/Task15 已进入 `main`。
- Home、For You、Search、Search Default、Rankings、Series Player 主入口已按 `use_real_api` 注入 Mock/Real Repository。
- `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build` 已可用。

本任务继续推进真实 API 模式下的可用性，不做 UI 大改版。

## 分支

从最新 `main` 新建分支：

```bash
git checkout main
git pull --ff-only origin main
git checkout -b task/task16-ios-real-api-phase3
```

禁止在 `main` 上直接开发。

## 目标

让 `use_real_api=true` 时 Home/Search/Ranking/Categories 的数据行为更接近真实产品可用状态：

1. 搜索页使用后端真实搜索接口，并补齐分页/加载更多基础能力。
2. 首页 Categories tab 使用后端分类 code 映射，不能继续只靠中文 `DramaCategory` 本地枚举过滤。
3. Ranking tab 使用后端 rankings 类型参数，而不是只拉全量再本地排序。
4. 真实 API 错误态、空态、重试路径可见且不误导。
5. 更新项目记忆和交付报告，不能留下已修复问题作为“未完成”。

## 任务范围

允许修改：

- `RelaxShort/Core/Services/RepositoryProtocols.swift`
- `RelaxShort/Core/Services/RealHomeRepository.swift`
- `RelaxShort/Core/Services/RealSearchRepository.swift`
- `RelaxShort/Core/Services/MockAPIRepository.swift`
- `RelaxShort/ViewModels/HomeViewModel.swift`
- `RelaxShort/ViewModels/SearchViewModel.swift`
- `RelaxShort/ViewModels/SearchDefaultViewModel.swift`
- `RelaxShort/ViewModels/RankViewModel.swift`
- `RelaxShort/Views/Home/HomeView.swift`
- `RelaxShort/Views/Search/SearchView.swift`
- `RelaxShort/Views/Search/SearchDefaultView.swift`
- `RelaxShort/Views/Rank/RankView.swift`
- 必要的本地化文案文件
- `AGENTS.md`
- `CLAUDE.md`
- `docs/TASK16_DELIVERY_REPORT.md`

如需修改其他文件，必须在交付报告里说明原因。

## 禁止事项

- 不改整体 UI 布局，不重做页面。
- 不删除 Mock Repository；Mock 模式必须继续可用。
- 不把服务器地址、token、数据库密码、生产密钥写进仓库。
- 不绕过 `DependencyContainer` 直接在页面里 new 真实 Repository。
- 不声称“真实联调通过”，除非明确说明后端服务地址、开关、操作步骤和结果。
- 不保留“CoreSimulator.framework 缺失导致无法编译”这类过时结论。

## 具体要求

### 1. Search 真实搜索分页

当前 `SearchViewModel` 已能调用 `repository.search(query:cursor:limit:)`，但还没有分页状态。

要求：

- `SearchRepositoryProtocol` 支持搜索分页语义，字段至少包括 items、nextCursor、hasMore。
- `RealSearchRepository` 使用 `/api/v2/search` 返回的 `nextCursor`、`hasMore`。
- `MockSearchRepository` 提供等价分页行为，方便 Mock 模式验证。
- `SearchViewModel` 增加：
  - `nextCursor`
  - `hasMore`
  - `isLoadingMore`
  - `loadMoreIfNeeded(currentItem:)` 或同等能力
- 搜索关键词变化时必须重置分页状态。
- 网络失败时不能清空已有结果；应显示错误提示或允许重试。

### 2. Search Default 数据来源

当前 Search Default 通过 `HomeRepositoryProtocol.fetchDramas(.all)` 构造三榜。

要求：

- 若后端 `search/default` 已能返回 hot series/suggestions/categories，真实模式优先用 `RealSearchRepository.fetchDramas` 或专门方法。
- 不要让 Search Default 在真实模式继续无条件走 Mock 或 Home 全量假数据。
- 若协议需要扩展，保持 Mock/Real 对齐。

### 3. Ranking 使用后端榜单类型

当前 `RankViewModel` 仍通过 `fetchDramas(.all)` 后本地排序。

要求：

- 为排行榜建立清晰的数据入口：
  - 可以新增 `RankingRepositoryProtocol`，或在 `HomeRepositoryProtocol` 增加 `fetchRankings(type:)`。
  - 选择更小改动方案，但要避免 ViewModel 依赖具体 `RealHomeRepository`。
- `RealHomeRepository.fetchRankings(type:)` 已存在，可复用。
- `RankCategory.hot/trending/new` 必须映射到后端支持的 type。若后端 type 名称不确定，先查 `app-server/v2/docs/IOS_API_CONTRACT_V1.md` 和后端代码后再决定。
- Mock 模式保留本地排序即可，但通过同一协议入口。

### 4. Categories 后端 code 映射

当前 iOS `DramaCategory` 是中文枚举，后端 `categories.code` 是英文 code，Task15 遗留 gap。

要求：

- 真实模式下，Home Categories tab 应优先读取后端 `/api/v2/categories`。
- 建立 `CategoryItemDTO` 到 UI 分类展示项的映射，不要硬编码只依赖中文枚举。
- 点击后端分类时，使用后端 code 调用真实分类剧集接口；如果后端接口暂不支持，必须在交付报告标成真实 gap，并保留合理降级。
- Mock 模式继续使用 `DramaCategory`。

### 5. 错误态和空态

要求：

- Home、Search、Rank 的真实 API 错误要能在 UI 或日志中定位，不允许静默变成 Mock 数据后声称真实成功。
- 可以保留 Mock fallback，但必须清晰区分：
  - 真实模式请求失败后的 UI 空态/错误态
  - Mock 模式正常数据
- 交付报告必须列出哪些页面有重试按钮、哪些仅有日志。

## ECC 使用要求

如果 CC 环境里 ECC 插件可用，按以下方式使用并在交付报告记录结果：

1. 开工前用 ECC 做一次 plan/analysis，确认改动面和风险。
2. 实现后用 ECC 做一次 self-review，重点检查：
   - 是否仍有真实入口硬编码 Mock。
   - 协议扩展是否 Mock/Real 都实现。
   - 分页状态是否在新 query 时重置。
   - 交付报告是否存在过时结论。
3. 如果 ECC 命令在当前环境不可用，交付报告必须写明不可用原因，并用手工 grep/审计替代。

## 必跑验证

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

同时做 grep 自检：

```bash
rg -n "SearchView\\(|RankView\\(|SearchViewModel\\(repository: MockSearchRepository\\(\\)|SearchDefaultViewModel\\(repository: MockHomeRepository\\(\\)|RankView\\(playerDrama:.*MockHomeRepository" RelaxShort
```

允许 Preview 或测试样例出现 Mock；主运行入口不允许。

## 交付报告

新增：

```text
docs/TASK16_DELIVERY_REPORT.md
```

必须包含：

- 分支名和提交 hash。
- 修改文件清单。
- Search 分页行为说明。
- Ranking type 映射说明。
- Categories code 映射说明。
- Mock/Real 分别如何验证。
- ECC 使用记录或不可用原因。
- 必跑验证命令和结果。
- 真实遗留问题，只写仍然存在的问题，不写已修复问题。

## Codex 验收重点

Codex review 会重点看：

- `use_real_api=true` 时主页面路径是否真的走真实 Repository。
- Search 是否调用真实 `/api/v2/search`，而不是本地过滤假完成。
- Ranking 是否通过协议调用后端 rankings，而不是 ViewModel 硬转具体类。
- Categories 是否有后端 code 映射策略。
- Mock/Real 是否都能编译。
- 文档是否真实、不过时、不夸大联调结果。
