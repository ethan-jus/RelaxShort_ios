# Task30 Search 页面 UI 与真实榜单联调实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 将 Search 页面改造成可正式使用的搜索入口，准确实现参考图的默认页结构，并让三个榜单和关键词搜索全部来自真实后端接口。

**架构：** `SearchView` 负责页面导航、搜索输入、历史记录和搜索结果；`SearchDefaultView` 只负责默认发现页及三个榜单展示。榜单继续复用 `HomeRepositoryProtocol.fetchRankings(type:)`，禁止把同一批数据在 iOS 本地伪排序成三个榜单。后端现有接口和数据已经满足本任务，本轮默认不修改后端。

**技术栈：** SwiftUI、Combine、现有 Repository/ViewModel 架构、`/api/v2/search`、`/api/v2/rankings`

---

## 一、执行前事实

### 必须先读

- `/Users/ethan/myspance/relaxshort/AGENTS.md`
- `/Users/ethan/myspance/relaxshort/ios/v1.0.0/AGENTS.md`
- `/Users/ethan/myspance/relaxshort/ios/v1.0.0/CLAUDE.md`
- 本任务书

### 必须使用的 ECC 能力

- SwiftUI 页面和状态管理：优先参考 ECC 的 Swift/SwiftUI rules。
- 网络与 Repository：参考 iOS networking/API rules。
- 完成前：参考 iOS verification/build rules。
- 如果当前环境找不到对应 ECC 能力，在交付说明中如实记录，不得编造。

### 已验证的后端数据

2026-06-27 本地 dev 已验证：

```text
GET /api/v2/rankings?type=trending  -> 12 items
GET /api/v2/rankings?type=popular   -> 12 items
GET /api/v2/rankings?type=new       -> 12 items
GET /api/v2/search/default          -> 6 suggestions, 10 hot_series
```

本任务不允许：

- 新增重复的 Search 榜单接口。
- 新增 Flyway migration，除非上述接口在执行时已真实失效，并先停下报告。
- 修改已经应用的 V1-V13 migration。
- 使用 Mock 数据填充真实 API 页面。
-让 CC 自己查看或猜测竞品截图；以下 UI 数值和行为就是实现依据。
- 顺手重构 Home、For You、播放器、底部导航或其他页面。

---

## 二、目标 UI 规格

### 顶部搜索区

- 页面背景纯黑，内容避开状态栏。
- 隐藏系统 NavigationBar，使用页面自己的顶部 `HStack`。
- 左侧为 `chevron.left` 返回按钮，点击 `dismiss()`。
- 搜索框高度 `44`，背景 `#252525`，圆角 `4`。
- 搜索框使用剩余宽度，不设置固定 `minWidth`。
- 左右页面边距 `16`，返回按钮与搜索框间距 `12`。
- 搜索输入、清除按钮、键盘提交均需可用。
- 键盘提交后写入搜索历史；输入停止 300ms 后继续使用现有真实搜索。

### 最近搜索区

- 仅在搜索文本为空时展示。
- 标题为本地化的 `Recent Searches`，右侧使用 `trash` 图标清空。
- 没有历史记录时整个区块隐藏，不占空白高度。
- 历史词使用紧凑深灰色 chip，高度约 `36`、圆角 `4`。
- 支持横向滚动，最多沿用现有 10 条限制。
- 点击历史词立即填入输入框并执行搜索。

### 默认榜单区

- 三个 Tab 单行展示并均匀分配宽度：
  - `Top Searched` -> API type `trending`
  - `Most Trending` -> API type `popular`
  - `New Releases` -> API type `new`
- 选中字体使用 `DB.logoRed`，禁止使用 `DT.brandPink`。
- 未选中字体使用 `DB.mutedText`。
- Tab 支持点击和左右滑动，二者状态必须同步。
- 默认选择 `Top Searched`。
- 列表卡片间距 `10`，页面水平边距 `16`，圆角统一使用 `DB.posterRadius`。
- 三个榜单卡片背景：
  - Top Searched：低饱和暗酒红 `#26030D`
  - Most Trending：低饱和暗棕 `#24170D`
  - New Releases：低饱和暗青绿 `#102219`
- 颜色只用于卡片背景，不把整页染色。

### 榜单卡片

- 卡片高度约 `104`，不得因标题长短改变高度。
- 封面宽 `64`、高 `88`，圆角 `DB.posterRadius`。
- 排名数字覆盖在封面左上角，不单独占一列。
- 前三名排名底色分别使用 Logo 红、低饱和橙、低饱和金；第 4 名以后只显示白色数字，不显示大色块。
- 标题最多两行；分类和 tags 合并为一行，用 `, ` 分隔，最多一行。
- 右侧显示 `flame.fill + formattedViewCount`，固定尾部宽度，不能挤压封面。
- 整张卡片可以点击并进入对应 `SeriesPlayerView`。

### 搜索结果

- 保留现有真实 `/api/v2/search`、300ms debounce、cursor 分页和 `MarketingGrid`。
- 修复当前错误态没有展示的问题：首屏请求失败时展示错误和 Retry；加载更多失败保留已有数据。
- 搜索请求期间，有旧结果时不清空旧结果；没有结果时显示加载状态。
- 空结果、错误、Retry 文案必须本地化，禁止新增中文硬编码。

### 响应式要求

- 小屏、标准屏、大屏都不得使用针对单一机型的固定横向宽度。
- Tab 文案必须保持单行，可通过紧凑字号和均分宽度适配，不允许换行。
- 长标题不能挤掉热度或让卡片高度变化。
- 阿拉伯语环境至少保证布局不溢出；返回按钮和文字遵循系统布局方向。

---

## 三、文件结构

### 修改

- `RelaxShort/Views/Search/SearchView.swift`
  - 自定义安全区顶部搜索栏。
  - 最近搜索与默认页组合。
  - 搜索结果状态和播放页导航。
- `RelaxShort/Views/Search/SearchDefaultView.swift`
  - 三榜单 Tab、分页滑动容器、空态和错误态。
  - 改为 `@ObservedObject`，对象生命周期由父视图持有。
- `RelaxShort/ViewModels/SearchDefaultViewModel.swift`
  - 删除真实模式下一份数据本地排序逻辑。
  - 并发请求 `trending/popular/new` 三个真实榜单。
- `RelaxShort/ViewModels/SearchViewModel.swift`
  - 暴露明确的重试入口。
  - 清理 Task 编号注释和中文硬编码错误文案。
- `RelaxShort/Utils/LocalizationHelper.swift`
- `RelaxShort/*/Localizable.strings`

### 新建

- `RelaxShort/Views/Search/SearchRankCardView.swift`
  - 榜单卡片的唯一实现，避免三个榜单复制布局。
- `RelaxShort/Views/Search/SearchRankTheme.swift`
  - 榜单类型、API type、标题、背景色和空态的集中定义。

不要新建无必要的 Design System，也不要把 Search 私有颜色塞进全局 token。

---

## 四、实施步骤

### Task 1：建立榜单语义和真实数据状态

- [ ] **Step 1：确认仓库状态**

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git status --short --branch
```

预期：`main...origin/main`，工作区干净。若不干净，停止并报告，禁止覆盖现有改动。

- [ ] **Step 2：新增 `SearchRankTheme`**

必须集中定义以下映射，View 和 ViewModel 禁止再次手写字符串：

```swift
enum SearchRankTheme: Int, CaseIterable, Identifiable {
    case topSearched
    case mostTrending
    case newReleases

    var id: Int { rawValue }

    var apiType: String {
        switch self {
        case .topSearched: "trending"
        case .mostTrending: "popular"
        case .newReleases: "new"
        }
    }
}
```

标题、空态文案 key 和低饱和卡片颜色也由该类型集中提供。

- [ ] **Step 3：重写 `SearchDefaultViewModel.loadData()`**

使用 `async let` 并发请求三个真实榜单：

```swift
async let top = homeRepository.fetchRankings(type: SearchRankTheme.topSearched.apiType)
async let trending = homeRepository.fetchRankings(type: SearchRankTheme.mostTrending.apiType)
async let releases = homeRepository.fetchRankings(type: SearchRankTheme.newReleases.apiType)
let (topItems, trendingItems, releaseItems) = try await (top, trending, releases)
```

然后各自按接口返回顺序添加排名。必须删除：

- `DependencyContainer.useRealAPI` 分支判断。
- `loadFromSearchDefault()`。
- `loadFromHome()`。
- `populateRanks(from:)` 中的本地评分、播放量和 ID 排序。
- 未使用的 `searchRepository` 依赖。

Mock 模式仍可工作，因为注入的 `MockHomeRepository.fetchRankings(type:)` 已遵守同一协议。

- [ ] **Step 4：构建验证**

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

预期：`BUILD SUCCEEDED`。

### Task 2：实现统一榜单卡片

- [ ] **Step 1：创建 `SearchRankCardView.swift`**

组件输入只包含：

```swift
let item: RankDrama
let theme: SearchRankTheme
let onTap: () -> Void
```

使用固定封面尺寸、固定卡片最小高度、两行标题、单行 tags 和尾部热度。排名覆盖在封面上，不能保留当前单独占宽 `28` 的排名列。

- [ ] **Step 2：统一点击区域和无障碍**

整卡使用 `Button` + `.buttonStyle(.plain)`，并提供包含排名和标题的 accessibility label。不要在卡片外再叠透明点击层。

- [ ] **Step 3：替换 `SearchDefaultView` 内联卡片**

删除 `rankDramaRow(_:)`，三个列表只调用 `SearchRankCardView`。将 `SearchDefaultView` 的 ViewModel 属性改为：

```swift
@ObservedObject var viewModel: SearchDefaultViewModel
```

父视图已经用 `@StateObject` 持有生命周期，不允许对子对象再次错误包装为 `StateObject`。

- [ ] **Step 4：构建验证**

重复执行 iPhone 17 Pro Max build，预期 `BUILD SUCCEEDED`。

### Task 3：重构默认页结构与最近搜索

- [ ] **Step 1：调整 `SearchDefaultView` 输入边界**

增加明确的外部输入：

```swift
let searchHistory: [String]
let onHistorySelected: (String) -> Void
let onClearHistory: () -> Void
let onDramaSelected: (DramaItem) -> Void
```

默认页不允许直接访问 `UserDefaults` 或 `AppStore`。

- [ ] **Step 2：实现最近搜索区**

仅当 `searchHistory` 非空时展示标题、清空按钮和横向 chips。清空使用 `trash` 图标按钮并提供 accessibility label。

- [ ] **Step 3：实现等宽 Tab**

使用 `ForEach(SearchRankTheme.allCases)`，每项 `.frame(maxWidth: .infinity)`，选中态只改变字体颜色和字重，不新增下划线。

- [ ] **Step 4：同步点击与滑动**

`TabView(selection:)` 的 tag 必须使用 `SearchRankTheme`，点击 Tab 和横向分页共用同一个 `selectedTheme` 状态。禁止维护两个选中索引。

- [ ] **Step 5：接通卡片导航**

卡片点击调用 `onDramaSelected(item.drama)`，由 `SearchView` 设置现有 `SeriesPlayerNav`，不得在子 View 新建 NavigationStack。

### Task 4：重构顶部搜索栏和搜索结果状态

- [ ] **Step 1：移除 toolbar 搜索栏**

删除当前 `.toolbar { ToolbarItem(...) }` 和固定 `minWidth: 240`。使用：

```swift
@Environment(\.dismiss) private var dismiss
```

在页面 VStack 顶部建立安全区内的返回按钮与搜索框。不得 `ignoresSafeArea` 覆盖顶部内容。

- [ ] **Step 2：接通历史行为**

将父 ViewModel 的以下能力传给默认页：

```swift
viewModel.searchHistory
viewModel.searchFromHistory(_:)
viewModel.clearHistory()
```

键盘提交继续调用 `submitSearch()`。

- [ ] **Step 3：补齐首屏加载、错误和重试**

`SearchViewModel` 增加公开重试方法，复用当前 `searchText`。错误态不得只存在于 ViewModel 而 UI 不显示。

- [ ] **Step 4：删除无效的全量预加载**

`SearchViewModel.init` 当前执行 `loadAllDramas()`，但真实关键词搜索不使用 `allDramas`。删除：

- `allDramas`
- `loadAllDramas()`
- 初始化时的预加载 Task

搜索页只在用户输入后调用真实 `/api/v2/search`。

- [ ] **Step 5：避免过期请求覆盖新结果**

保存当前查询值。请求完成后只有结果对应的 query 仍等于当前 trim 后的 `searchText` 才更新列表，防止快速输入时旧请求晚返回覆盖新结果。

### Task 5：完成多语言

- [ ] **Step 1：添加 L10n 属性**

至少补齐：

```swift
static var recentSearches: String
static var clearSearchHistory: String
static var topSearchedTab: String
static var mostTrendingTab: String
static var newReleasesTab: String
static var searchFailed: String
```

- [ ] **Step 2：更新全部语言文件**

必须更新：

```text
Base, en, zh-Hans, zh-Hant, es, pt, ja, ko, ar
```

英文和简体中文使用准确翻译；其他语言不得缺 key，可提供准确的基础翻译，禁止留空或直接显示 key。

- [ ] **Step 3：扫描硬编码**

```bash
rg -n '"(搜索|暂无|热搜榜|热播榜|新剧榜|搜索失败)' \
  RelaxShort/Views/Search RelaxShort/ViewModels/Search
```

预期：业务展示文案无命中；日志内容可以保留中文。

### Task 6：真实接口与最终验收

- [ ] **Step 1：接口 smoke**

```bash
for type in trending popular new; do
  curl -fsS "http://127.0.0.1:8080/api/v2/rankings?type=${type}&content_language=en&country_code=GLOBAL&limit=20" \
    | jq -e '.data.items | length > 0'
done

curl -fsS "http://127.0.0.1:8080/api/v2/search?q=Jiang&content_language=en&country_code=GLOBAL&limit=20" \
  | jq -e '.data.items | length > 0'
```

预期：四条命令均输出 `true`。

- [ ] **Step 2：最终构建**

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 3：模拟器手工验收**

必须检查：

1. 默认页显示真实最近搜索和三个真实榜单。
2. 点击和滑动切换三个榜单时内容、颜色、选中态同步。
3. 榜单卡片进入正确 Series Player。
4. 输入关键词会请求真实搜索，清除后回到默认页。
5. 键盘提交写入历史，点击历史可复搜，垃圾桶可清空。
6. 搜索分页、空态、错误态和 Retry 正常。
7. iPhone 小屏、标准屏、Pro Max 至少检查 Preview 或模拟器布局，无溢出和遮挡。

- [ ] **Step 4：检查 diff**

```bash
git diff --check
git status --short
git diff --stat
```

禁止提交构建产物、用户配置、旧 SQL 或无关文件。

---

## 五、交付要求

本任务不写单独的长篇交付报告，节省 token。CC 完成后直接在终端输出中文简报：

1. 修改文件列表。
2. 三个榜单与 API type 的最终映射。
3. `xcodebuild` 结果。
4. 四条 API smoke 结果。
5. 尚未验证的真实风险。

不要自行 commit、push 或启动下一个任务，等待 Codex review。
