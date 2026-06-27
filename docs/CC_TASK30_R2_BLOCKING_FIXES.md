# Task30 R2 Search 露出式榜单与阻断修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 R1 的真实搜索阻断问题，并将 Search 默认页实现为固定标题、真实数据、右侧露出下一榜单的吸附式横向分页。

**Architecture:** `SearchView` 管理输入、历史、搜索状态和导航；`SearchDefaultView` 组合最近搜索、固定标题栏和独立 `SearchRankingPager`；`SearchDefaultViewModel` 并发加载三个真实榜单。分页使用 iOS 17 横向 `ScrollView` 的 view-aligned snapping，不使用全宽 `TabView`。

**Tech Stack:** SwiftUI、Combine、iOS 17 ScrollView APIs、现有 Repository/ViewModel 架构、`/api/v2/search`、`/api/v2/rankings`

---

## 0. 执行边界

### 必读

- `/Users/ethan/myspance/relaxshort/AGENTS.md`
- `/Users/ethan/myspance/relaxshort/ios/v1.0.0/AGENTS.md`
- `/Users/ethan/myspance/relaxshort/ios/v1.0.0/CLAUDE.md`
- `docs/superpowers/specs/2026-06-27-task30-search-ranking-design.md`
- 本任务书

### 当前工作区

R1 尚未提交，以下修改和未跟踪文件属于本任务，必须在原改动上修复，禁止回滚：

```text
RelaxShort/Utils/LocalizationHelper.swift
RelaxShort/ViewModels/SearchDefaultViewModel.swift
RelaxShort/ViewModels/SearchViewModel.swift
RelaxShort/Views/Search/SearchDefaultView.swift
RelaxShort/Views/Search/SearchView.swift
RelaxShort/Localizable.strings
RelaxShort/Views/Search/SearchRankCardView.swift
RelaxShort/Views/Search/SearchRankTheme.swift
```

`RelaxShort/Localizable.strings` 是 R1 创建在错误位置的文件，本轮必须删除。

### 禁止事项

- 不修改后端。
- 不新增 Flyway migration。
- 不恢复本地伪排序。
- 不使用全宽 `TabView` 实现榜单分页。
- 不硬编码英文榜单标题；固定标题仍必须通过 `L10n`。
- 不调整 Home、For You、播放器、底部导航。
- 不自行 commit 或 push。
- 不写交付报告文档。

### 数据映射

固定标题不由后端配置：

```text
Top Searched   -> trending
Most Trending  -> popular
New Releases   -> new
```

---

## 1. 修复真实搜索状态机

**Files:**

- Modify: `RelaxShort/ViewModels/SearchViewModel.swift`
- Modify: `RelaxShort/Views/Search/SearchView.swift`

- [ ] **Step 1：删除 R1 无效代码**

从 `SearchViewModel` 删除空的：

```swift
Task {
}
```

继续删除 Task 编号注释和中文展示硬编码。日志可以保留中文。

- [ ] **Step 2：增加完整搜索状态**

在 `SearchViewModel` 增加：

```swift
@Published private(set) var hasCompletedSearch = false
private var latestQuery = ""
```

`retry()` 保持公开，但只负责重新执行当前查询：

```swift
func retry() {
    Task {
        await performSearch(query: searchText)
    }
}
```

- [ ] **Step 3：重写首屏搜索**

`performSearch(query:)` 必须使用规范化查询，并防止旧请求覆盖新请求：

```swift
private func performSearch(query: String) async {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    latestQuery = normalizedQuery

    guard !normalizedQuery.isEmpty else {
        searchResults = []
        isSearching = false
        errorMessage = nil
        hasCompletedSearch = false
        resetPagination()
        return
    }

    isSearching = true
    errorMessage = nil
    resetPagination()

    defer {
        if latestQuery == normalizedQuery {
            isSearching = false
        }
    }

    do {
        let (items, cursor, more) = try await repository.search(
            query: normalizedQuery,
            cursor: nil,
            limit: 20
        )
        guard latestQuery == normalizedQuery else { return }
        searchResults = items
        nextCursor = cursor
        hasMore = more
        hasCompletedSearch = true
    } catch {
        guard latestQuery == normalizedQuery else { return }
        errorMessage = L10n.searchFailed
        hasCompletedSearch = true
        logError("SearchViewModel.performSearch failed: \(error)")
    }
}
```

- [ ] **Step 4：修复加载更多的查询竞争**

请求前捕获规范化查询，返回后再次校验：

```swift
let requestQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
guard !requestQuery.isEmpty, requestQuery == latestQuery else { return }
```

接口返回后，在追加数据前执行：

```swift
guard requestQuery == latestQuery else { return }
```

使用 `defer { isLoadingMore = false }`，禁止任何提前返回让 loading 卡住。

- [ ] **Step 5：恢复键盘提交**

在顶部 `TextField` 添加：

```swift
.submitLabel(.search)
.onSubmit {
    viewModel.submitSearch()
}
```

- [ ] **Step 6：按优先级展示搜索结果状态**

`searchText` 非空时按以下顺序：

1. `isSearching && searchResults.isEmpty`：居中 `ProgressView`。
2. `errorMessage != nil && searchResults.isEmpty`：错误文案和 Retry。
3. `hasCompletedSearch && searchResults.isEmpty`：空结果。
4. 其他情况：现有结果网格。

首屏错误 Retry：

```swift
Button(L10n.retry) {
    viewModel.retry()
}
```

有旧结果时请求失败不得清空网格。

---

## 2. 完成独立文件和 Xcode target

**Files:**

- Modify: `RelaxShort.xcodeproj/project.pbxproj`
- Modify: `RelaxShort/ViewModels/SearchDefaultViewModel.swift`
- Modify: `RelaxShort/Views/Search/SearchDefaultView.swift`
- Modify: `RelaxShort/Views/Search/SearchRankTheme.swift`
- Modify: `RelaxShort/Views/Search/SearchRankCardView.swift`
- Create: `RelaxShort/Views/Search/SearchRankingPager.swift`

- [ ] **Step 1：消除重复定义**

最终归属必须唯一：

```text
SearchRankTheme      -> SearchRankTheme.swift
SearchRankCardView   -> SearchRankCardView.swift
SearchRankingPager   -> SearchRankingPager.swift
```

从 `SearchDefaultViewModel.swift` 删除 `SearchRankTheme`。

从 `SearchDefaultView.swift` 删除 `SearchRankCardView`。

每个 Swift 文件只保留一个顶部 `import SwiftUI`，文件末尾必须有换行。

- [ ] **Step 2：修复独立卡片文件的编译错误**

分类与第一个 tag 合并后必须 join：

```swift
private var metadataText: String {
    ([item.category] + item.tags.prefix(1))
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
}
```

禁止：

```swift
Text([item.category] + item.tags.prefix(1))
```

- [ ] **Step 3：加入 Xcode 工程**

将以下三个文件加入 Search group 和 RelaxShort target 的 Sources build phase：

```text
SearchRankTheme.swift
SearchRankCardView.swift
SearchRankingPager.swift
```

修改 `project.pbxproj` 时沿用现有 PBXFileReference、PBXBuildFile 和 Sources 结构，不重排无关 UUID，不引入整文件格式化。

- [ ] **Step 4：确认实际编译文件**

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' clean build \
  | tee /tmp/task30-r2-build.log

grep -q "SearchRankTheme.swift" /tmp/task30-r2-build.log
grep -q "SearchRankCardView.swift" /tmp/task30-r2-build.log
grep -q "SearchRankingPager.swift" /tmp/task30-r2-build.log
```

预期：构建成功，三条 `grep` 均返回 0。

---

## 3. 固定榜单语义和真实数据

**Files:**

- Modify: `RelaxShort/Views/Search/SearchRankTheme.swift`
- Modify: `RelaxShort/ViewModels/SearchDefaultViewModel.swift`

- [ ] **Step 1：定义固定主题**

`SearchRankTheme` 必须是 `Hashable`，供 `scrollPosition(id:)` 使用：

```swift
enum SearchRankTheme: Int, CaseIterable, Identifiable, Hashable {
    case topSearched
    case mostTrending
    case newReleases

    var id: Self { self }

    var apiType: String {
        switch self {
        case .topSearched:
            return "trending"
        case .mostTrending:
            return "popular"
        case .newReleases:
            return "new"
        }
    }

    var title: String {
        switch self {
        case .topSearched:
            return L10n.topSearchedTab
        case .mostTrending:
            return L10n.mostTrendingTab
        case .newReleases:
            return L10n.newReleasesTab
        }
    }
}
```

- [ ] **Step 2：集中卡片颜色**

在 `SearchRankTheme` 提供：

```swift
var topRankGradientColors: [Color]
var regularCardColor: Color { Color(hex: "#101011") }
```

颜色要求：

```text
Top Searched:  #3A0614 -> #160107
Most Trending: #382313 -> #160D07
New Releases:  #17382C -> #08140F
```

这些颜色只用于前三名卡片，不得设置为整页背景。

- [ ] **Step 3：使用一个 rankings 状态源**

`SearchDefaultViewModel` 改为：

```swift
@Published var selectedTheme: SearchRankTheme = .topSearched
@Published private(set) var rankings: [SearchRankTheme: [RankDrama]] = [:]
@Published private(set) var isLoading = false
@Published private(set) var errorMessage: String?
```

读取方法：

```swift
func items(for theme: SearchRankTheme) -> [RankDrama] {
    rankings[theme] ?? []
}
```

删除 `topSearched`、`mostTrending`、`newReleases` 三套重复 Published 数组和未使用的 `currentDramas`。

- [ ] **Step 4：并发加载三个真实榜单**

```swift
func loadData() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
        async let topItems = fetchRanked(.topSearched)
        async let trendingItems = fetchRanked(.mostTrending)
        async let releaseItems = fetchRanked(.newReleases)

        let loaded = try await (topItems, trendingItems, releaseItems)
        rankings = [
            .topSearched: loaded.0,
            .mostTrending: loaded.1,
            .newReleases: loaded.2
        ]
    } catch {
        errorMessage = L10n.searchFailed
        logError("SearchDefaultViewModel.loadData failed: \(error)")
    }
}
```

接口返回顺序就是排名顺序，不得再次排序。

---

## 4. 实现右侧露出的吸附式分页

**Files:**

- Create: `RelaxShort/Views/Search/SearchRankingPager.swift`
- Modify: `RelaxShort/Views/Search/SearchDefaultView.swift`

- [ ] **Step 1：建立分页组件输入**

```swift
struct SearchRankingPager: View {
    @ObservedObject var viewModel: SearchDefaultViewModel
    let onDramaSelected: (DramaItem) -> Void

    @State private var scrollTarget: SearchRankTheme? = .topSearched
}
```

组件只负责榜单横向分页和每页纵向列表，不负责历史记录或网络请求。

- [ ] **Step 2：计算响应式页面宽度**

在 `GeometryReader` 内使用：

```swift
let horizontalInset: CGFloat = 16
let pageSpacing: CGFloat = 12
let peekWidth = min(max(proxy.size.width * 0.15, 52), 72)
let pageWidth = proxy.size.width - horizontalInset - peekWidth
```

结果要求：

- 小屏至少露出 52pt。
- 大屏最多露出 72pt。
- 当前页仍有足够空间完整显示热度。
- 禁止写死某个 iPhone 的最终 page width。

- [ ] **Step 3：实现横向吸附**

核心结构：

```swift
ScrollView(.horizontal, showsIndicators: false) {
    LazyHStack(alignment: .top, spacing: pageSpacing) {
        ForEach(SearchRankTheme.allCases) { theme in
            rankingPage(theme)
                .frame(width: pageWidth)
                .id(theme)
        }
    }
    .scrollTargetLayout()
}
.contentMargins(.horizontal, horizontalInset, for: .scrollContent)
.scrollTargetBehavior(.viewAligned(limitBehavior: .always))
.scrollPosition(id: $scrollTarget, anchor: .leading)
```

禁止使用 `.paging`，因为页面宽度小于视口；使用 `.viewAligned` 才能按每个榜单的 leading edge 吸附。

- [ ] **Step 4：同步手势与标题状态**

手势完成吸附后：

```swift
.onChange(of: scrollTarget) { _, newValue in
    guard let newValue, newValue != viewModel.selectedTheme else { return }
    viewModel.selectTheme(newValue)
}
```

点击标题改变 ViewModel 后：

```swift
.onChange(of: viewModel.selectedTheme) { _, newValue in
    guard scrollTarget != newValue else { return }
    withAnimation(.easeInOut(duration: 0.25)) {
        scrollTarget = newValue
    }
}
```

`selectTheme(_:)` 只设置状态，不在 ViewModel 内调用 `withAnimation`：

```swift
func selectTheme(_ theme: SearchRankTheme) {
    selectedTheme = theme
}
```

动画属于 View 层。

- [ ] **Step 5：每页使用独立纵向列表**

`rankingPage(_:)`：

```swift
private func rankingPage(_ theme: SearchRankTheme) -> some View {
    ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.items(for: theme)) { item in
                SearchRankCardView(
                    item: item,
                    theme: theme,
                    onTap: { onDramaSelected(item.drama) }
                )
            }
        }
        .padding(.bottom, 40)
    }
}
```

不增加纵向滚动位置缓存或恢复逻辑。

- [ ] **Step 6：替换旧 `TabView`**

`SearchDefaultView` 删除：

```swift
TabView(selection:)
.tabViewStyle(.page)
```

替换为：

```swift
SearchRankingPager(
    viewModel: viewModel,
    onDramaSelected: onDramaSelected
)
```

标题栏使用 `SearchRankTheme.allCases` 等宽布局，点击调用 `viewModel.selectTheme(theme)`。

---

## 5. 实现前三名渐变卡片

**Files:**

- Modify: `RelaxShort/Views/Search/SearchRankCardView.swift`

- [ ] **Step 1：按排名生成背景**

```swift
@ViewBuilder
private var cardBackground: some View {
    if item.rank <= 3 {
        LinearGradient(
            colors: theme.topRankGradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    } else {
        theme.regularCardColor
    }
}
```

将背景应用在卡片本身：

```swift
.background(cardBackground)
.clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
```

不得给整个榜单页添加主题渐变。

- [ ] **Step 2：统一排名角标**

前三名：

```text
1 -> DB.logoRed
2 -> 低饱和橙 #D97735
3 -> 低饱和金 #B8923E
```

第 4 名以后使用半透明黑底和白字。角标覆盖封面左上角，不单独占据横向列。

- [ ] **Step 3：保护标题和热度布局**

卡片结构使用：

```swift
HStack(spacing: 10) {
    poster
    titleAndMetadata
        .frame(maxWidth: .infinity, alignment: .leading)
    heat
        .fixedSize(horizontal: true, vertical: false)
}
```

标题最多两行，metadata 一行。卡片高度保持 `104`，封面 `64 x 88`。

- [ ] **Step 4：本地化无障碍文案**

增加格式化 key：

```swift
static func searchRankAccessibility(rank: Int, title: String) -> String
```

禁止保留：

```swift
.accessibilityLabel("Rank \(item.rank): \(item.title)")
```

---

## 6. 完成九种语言资源

**Files:**

- Delete: `RelaxShort/Localizable.strings`
- Modify: `RelaxShort/Utils/LocalizationHelper.swift`
- Modify: `RelaxShort/Base.lproj/Localizable.strings`
- Modify: `RelaxShort/en.lproj/Localizable.strings`
- Modify: `RelaxShort/zh-Hans.lproj/Localizable.strings`
- Modify: `RelaxShort/zh-Hant.lproj/Localizable.strings`
- Modify: `RelaxShort/es.lproj/Localizable.strings`
- Modify: `RelaxShort/pt.lproj/Localizable.strings`
- Modify: `RelaxShort/ja.lproj/Localizable.strings`
- Modify: `RelaxShort/ko.lproj/Localizable.strings`
- Modify: `RelaxShort/ar.lproj/Localizable.strings`

- [ ] **Step 1：删除错误资源文件**

删除：

```text
RelaxShort/Localizable.strings
```

- [ ] **Step 2：补齐全部 key**

九个语言目录都必须包含：

```text
search.failed
search.recent_searches
search.clear_history
search.tab.top_searched
search.tab.most_trending
search.tab.new_releases
search.rank_accessibility_format
```

Base 与 en 使用英文；其余语言使用对应翻译。禁止空值、复制 key、遗漏语言。

- [ ] **Step 3：补充 L10n 格式化方法**

先在 `zhFallback` 中补齐本轮七个 key 的简体中文兜底值。然后沿用 `LocalizationHelper.swift` 现有 `loc(_:formatArgs:)` 实现：

```swift
static func searchRankAccessibility(rank: Int, title: String) -> String {
    loc(
        "search.rank_accessibility_format",
        formatArgs: [rank, title]
    )
}
```

调用参数顺序必须与各语言格式字符串一致。

- [ ] **Step 4：自动检查资源完整性**

```bash
for file in RelaxShort/*.lproj/Localizable.strings; do
  for key in \
    search.failed \
    search.recent_searches \
    search.clear_history \
    search.tab.top_searched \
    search.tab.most_trending \
    search.tab.new_releases \
    search.rank_accessibility_format; do
    grep -q "\"${key}\"" "$file" || {
      echo "missing ${key} in ${file}"
      exit 1
    }
  done
done
```

预期：无 missing 输出，退出码 0。

---

## 7. 接口、构建和模拟器验收

**Files:**

- Verify only

- [ ] **Step 1：真实接口 smoke**

后端需由用户在 IDEA 显式启动。执行：

```bash
for type in trending popular new; do
  curl -fsS "http://127.0.0.1:8080/api/v2/rankings?type=${type}&content_language=en&country_code=GLOBAL&limit=20" \
    | jq -e '.data.items | length > 0'
done

curl -fsS "http://127.0.0.1:8080/api/v2/search?q=Jiang&content_language=en&country_code=GLOBAL&limit=20" \
  | jq -e '.data.items | length > 0'
```

预期：四次均输出 `true`。

- [ ] **Step 2：静态质量检查**

```bash
git diff --check

rg -n 'Task[0-9]+|Text\\(\\[item\\.category\\]|accessibilityLabel\\(\"Rank' \
  RelaxShort/Views/Search RelaxShort/ViewModels/Search
```

预期：`git diff --check` 无输出；第二条无命中。

- [ ] **Step 3：干净构建**

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' clean build \
  | tee /tmp/task30-r2-build.log
```

预期：`BUILD SUCCEEDED`，且三个新组件均出现在编译日志。

- [ ] **Step 4：模拟器验收清单**

由用户执行，CC 在交付中标记为“待用户验收”，不得声称已通过：

1. 当前页完整，右侧能看到下一榜单约半张封面。
2. 左右滑动每次吸附到一个榜单，不停在中间。
3. 点击标题与手势滑动的选中态同步。
4. 三个榜单只有前三名有主题渐变，第 4 名以后为近黑背景。
5. 输入搜索词能返回真实结果，不再永久 loading。
6. 键盘 Search 写入历史，点击历史可重新搜索。
7. 首屏错误显示 Retry，空结果显示空态。
8. 点击榜单卡片进入正确 Series Player。
9. 小屏、标准屏、Pro Max 无横向溢出或热度被遮挡。

- [ ] **Step 5：交付简报**

终端只输出：

1. 修改文件。
2. 三个标题与 API type 映射。
3. 横向分页使用的 API 和露出宽度算法。
4. API smoke 结果。
5. 多语言检查结果。
6. Xcode build 结果。
7. 明确列出“模拟器 UI 待用户验收”。

不要 commit、push 或创建交付报告。
