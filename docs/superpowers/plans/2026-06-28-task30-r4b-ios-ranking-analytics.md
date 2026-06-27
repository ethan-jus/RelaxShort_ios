# Task30 R4B iOS 榜单联调与事件上报 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 使用后端真实排名和指标，可靠上报搜索及播放行为，并修复 Home Tab 闪烁和 Search 标题字重。

**Architecture:** Repository 把 Rankings 新合同转换为 `RankingEntry`，Search/Home 只消费领域模型。独立 Analytics Actor 持久化批量事件，播放器只提供媒体身份和进度，Tracker 负责生成事件，网络失败不进入播放器状态机。

**Tech Stack:** Swift 6、SwiftUI、Combine、URLSession、Security/Keychain、Swift Concurrency、Xcode 16+

---

## 前置条件与边界

- 工作目录：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`
- R4A 已通过 Codex review，以下接口可用：
  - `GET /api/v2/rankings`
  - `GET /api/v2/search/default`
  - `POST /api/v2/events/discovery/batch`
- 先阅读根目录和 iOS 规则、R4 设计、R4A 最终 API 示例。
- 使用 ECC Swift/SwiftUI/Concurrency/Testing rules；先检查现有依赖注入和命名。
- 不改已验收的 Search 布局尺寸、间距、颜色、渐变和分页方式。
- 不把 Analytics 网络调用写入 `ShortVideoPlayerEngine`。
- 不提交或推送最终整包，等待 Codex review。

## 文件结构

**创建：**

- `RelaxShort/Models/RankingEntry.swift`
- `RelaxShort/Models/API/RankingResponseDTO.swift`
- `RelaxShort/Core/Analytics/InstallIdentityProvider.swift`
- `RelaxShort/Core/Analytics/DiscoveryEvent.swift`
- `RelaxShort/Core/Analytics/DiscoveryAnalyticsReporter.swift`
- `RelaxShort/Core/Analytics/PlaybackAnalyticsTracker.swift`
- 对应测试文件；若仓库仍无测试 target，新增最小 `RelaxShortTests` target

**修改：**

- `RelaxShort.xcodeproj/project.pbxproj`
- `RelaxShort/Core/Services/APIEndpoint.swift`
- `RelaxShort/Core/Services/APIClient.swift`
- `RelaxShort/Core/Services/RepositoryProtocols.swift`
- `RelaxShort/Core/Services/RealHomeRepository.swift`
- `RelaxShort/Core/Services/DependencyContainer.swift`
- `RelaxShort/Models/RankDrama.swift`
- `RelaxShort/PlayerKit/PlayerMediaModels.swift`
- `RelaxShort/Views/RecommendPage/VideoPlayerView.swift`
- `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- `RelaxShort/ViewModels/SearchDefaultViewModel.swift`
- `RelaxShort/ViewModels/SearchViewModel.swift`
- `RelaxShort/Views/Search/SearchView.swift`
- `RelaxShort/Views/Search/SearchDefaultView.swift`
- `RelaxShort/ViewModels/RankViewModel.swift`
- `RelaxShort/Views/Home/HomeView.swift`
- `RelaxShort/App/RelaxShortApp.swift`

### Task 1: Rankings 新合同与领域模型

- [ ] **Step 1: 创建 DTO 解码失败测试**

使用 R4A 实际响应 fixture，断言：

```swift
let response = try decoder.decode(RankingResponseDTO.self, from: fixture)
XCTAssertEqual(response.items.first?.rankPosition, 1)
XCTAssertEqual(response.items.first?.metricValue, 106_000)
XCTAssertEqual(response.items.first?.metricType, "qualified_play_count_24h")
XCTAssertEqual(response.items.first?.card.seriesId, 20_250_312_000_001)
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test \
  -project RelaxShort.xcodeproj \
  -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/RankingResponseDTOTests
```

- [ ] **Step 3: 创建 DTO 和领域模型**

```swift
struct RankingEntry: Identifiable {
    let rankPosition: Int
    let metricType: String
    let metricValue: Int64
    let drama: DramaItem

    var id: String { "\(rankPosition):\(drama.id)" }
}
```

DTO 必须显式包含 `generatedAt` 和嵌套 `card`，不要继续使用只含 `items: [FeedCardDTO]` 的旧私有 DTO。

- [ ] **Step 4: 修改 Repository 协议**

```swift
protocol HomeRepositoryProtocol {
    func fetchRankingEntries(type: String) async throws -> [RankingEntry]
}
```

Mock 默认实现可以从本地数据生成明确的 `RankingEntry`，但真实 Search/Home 路径只使用后端数据。删除旧的 `fetchRankings(type:) -> [DramaItem]`，一次性更新调用方，避免双合同长期共存。

- [ ] **Step 5: 修改 RealHomeRepository**

映射规则：

```swift
RankingEntry(
    rankPosition: dto.rankPosition,
    metricType: dto.metricType,
    metricValue: dto.metricValue,
    drama: FeedCardDTOMapper.toDramaItem(from: dto.card)
)
```

不得用 `enumerated()`、`viewCount` 或本地排序覆盖后端排名。

- [ ] **Step 6: 运行 DTO 测试和构建**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/RankingResponseDTOTests
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

- [ ] **Step 7: 提交合同检查点**

```bash
git add RelaxShort RelaxShortTests RelaxShort.xcodeproj/project.pbxproj
git commit -m "feat: consume ranked entry API contract"
```

### Task 2: Search/Home 使用真实排名指标

- [ ] **Step 1: 写格式化测试**

```swift
XCTAssertEqual(RankingMetricFormatter.string(from: 51_000), "51K")
XCTAssertEqual(RankingMetricFormatter.string(from: 1_250_000), "1.3M")
XCTAssertEqual(RankingMetricFormatter.string(from: 999), "999")
```

- [ ] **Step 2: 修改 RankDrama**

`RankDrama` 从 `RankingEntry` 创建：

```swift
init(entry: RankingEntry) {
    rank = entry.rankPosition
    hot = RankingMetricFormatter.string(from: entry.metricValue)
    drama = entry.drama
    // 其余展示字段来自 entry.drama
}
```

- [ ] **Step 3: 修改榜单类型**

固定标题与 API 类型：

```text
Top Searched  -> top_searched
Most Trending -> trending
New Releases  -> new_releases
```

同步更新 `SearchDefaultViewModel` 和 `RankViewModel`，禁止 iOS 再按 `viewCount` 排序。

- [ ] **Step 4: Search 标题加粗**

三个固定标题统一：

```swift
.font(.system(size: 16, weight: .bold))
```

只改变字重，不改变现有高度、间距、颜色或选中逻辑。

- [ ] **Step 5: 运行测试与构建**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/RankingMetricFormatterTests
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

- [ ] **Step 6: 提交展示检查点**

```bash
git add RelaxShort RelaxShortTests
git commit -m "feat: display backend ranking metrics"
```

### Task 3: 安装身份和统一请求头

- [ ] **Step 1: 写安装身份测试**

使用可注入 Keychain store，断言：

```swift
XCTAssertEqual(provider.installID(), provider.installID())
XCTAssertNotEqual(providerA.installID(), providerB.installID())
XCTAssertNotNil(UUID(uuidString: provider.installID()))
```

- [ ] **Step 2: 实现 InstallIdentityProvider**

- 首次生成 UUID。
- 保存到 Keychain，service 使用 App bundle ID，account 固定为 `install-id`。
- Keychain 临时失败时使用内存值，不在每次请求生成新 UUID。
- 不读取 IDFA，不记录到控制台。

- [ ] **Step 3: APIClient 添加请求头**

统一使用后端已支持的：

```swift
base["X-Device-Id"] = InstallIdentityProvider.shared.installID()
```

不要同时新增 `X-Install-Id`，避免同一语义两个 header。

- [ ] **Step 4: 运行测试与构建**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/InstallIdentityProviderTests
```

- [ ] **Step 5: 提交身份检查点**

```bash
git add RelaxShort/Core/Analytics RelaxShort/Core/Services/APIEndpoint.swift RelaxShortTests
git commit -m "feat: add anonymous install identity"
```

### Task 4: 持久化批量 Analytics Reporter

- [ ] **Step 1: 写 Actor 行为测试**

覆盖：

```swift
// 同一 eventID 只进入队列一次。
// 20 条事件自动 flush。
// flush 失败后事件仍保留。
// flush 成功后只删除本次已经确认的事件。
// 持久化恢复后顺序和 eventID 不变。
// 队列超过 500 条时按最旧非关键事件淘汰。
```

- [ ] **Step 2: 新增 APIEndpoint**

```swift
case discoveryEvents(DiscoveryEventBatchRequest)
```

路径 `/api/v2/events/discovery/batch`，方法 POST，body 使用 `JSONEncoder`，禁止 `[String: Any]` 手拼。

- [ ] **Step 3: 实现 DiscoveryEvent**

```swift
struct DiscoveryEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let eventType: DiscoveryEventType
    let seriesID: String?
    let episodeID: String?
    let searchTerm: String?
    let contentLanguage: String
    let countryCode: String
    let sourceScene: String?
    let occurredAt: Date
}
```

- [ ] **Step 4: 实现 Reporter Actor**

接口保持最小：

```swift
actor DiscoveryAnalyticsReporter {
    func track(_ event: DiscoveryEvent)
    func flush()
    func flushForBackground()
}
```

达到 20 条或首条等待 15 秒后提交。网络失败指数退避且有上限；不得无限创建 `Task`。持久化文件写入 Application Support，使用原子替换。

- [ ] **Step 5: 注入并处理生命周期**

`DependencyContainer` 持有 reporter；App 进入 background 时调用 `flushForBackground()`。Reporter 失败只记一条简洁 DEBUG 日志。

- [ ] **Step 6: 运行 Reporter 测试**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/DiscoveryAnalyticsReporterTests
```

- [ ] **Step 7: 提交 Reporter 检查点**

```bash
git add RelaxShort/Core/Analytics RelaxShort/Core/Services RelaxShort/App RelaxShortTests
git commit -m "feat: batch discovery analytics events"
```

### Task 5: 搜索提交和点击事件

- [ ] **Step 1: 写 SearchViewModel 测试**

断言输入防抖搜索不产生提交事件，以下动作各产生一次：

```swift
viewModel.submitSearch()
viewModel.searchFromHistory("Jiang")
viewModel.searchFromTrending("CEO")
```

同一次动作不得因为搜索请求、历史写入和导航重复上报。

- [ ] **Step 2: 修改 SearchViewModel**

`submitSearch` 在规范化非空后上报 `search_submit`。防抖 `performSearch` 不上报。历史/热门词点击统一进入同一个明确提交入口。

- [ ] **Step 3: 上报搜索结果点击**

点击结果时上报：

```swift
eventType: .searchResultClick
seriesID: drama.id
searchTerm: normalizedCurrentQuery
sourceScene: "search"
```

事件入队后立即导航，不等待网络。

- [ ] **Step 4: 上报默认榜单点击**

默认页没有 query，点击榜单卡片只上报 `content_impression` 或后续导航事件，不伪造 `search_result_click`。

- [ ] **Step 5: 运行 Search 测试和构建**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/SearchAnalyticsTests
```

- [ ] **Step 6: 提交 Search Analytics 检查点**

```bash
git add RelaxShort/Views/Search RelaxShort/ViewModels RelaxShortTests
git commit -m "feat: track explicit search interactions"
```

### Task 6: 播放身份与有效播放事件

- [ ] **Step 1: 扩展 PlayerMediaItem**

增加明确字段：

```swift
let seriesID: String
let episodeID: String?
```

更新 For You 和 Series 所有构造点。不得从 `"series-episode"` 字符串拆 ID。

- [ ] **Step 2: 写 PlaybackAnalyticsTracker 测试**

用可控时钟和假 Reporter 覆盖：

```swift
// 同一播放会话累计有效播放达到 10 秒，上报一次 qualified_play。
// seek 跳到 10 秒不算累计观看。
// 暂停期间不累计。
// 切换媒体后创建新会话。
// 达到 90% 且有效观看达到阈值，上报一次 play_complete。
// View 重建不重复上报同一 session。
```

- [ ] **Step 3: 实现独立 Tracker**

Tracker 观察 engine 的 item、state 和 progress，但不修改 engine 状态。网络上报只调用 Reporter actor。

- [ ] **Step 4: 接入 For You 与 Series**

两个页面共用同一个 Tracker 类型，各自传入 scene：

```text
for_you
series_player
```

页面退出时结束当前会话；不得改变暂停、恢复、预加载、Recovery 和播放生命周期。

- [ ] **Step 5: 运行播放器 Analytics 测试**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/PlaybackAnalyticsTrackerTests
```

- [ ] **Step 6: 提交播放事件检查点**

```bash
git add RelaxShort/PlayerKit RelaxShort/Views/RecommendPage RelaxShort/Core/Analytics RelaxShortTests
git commit -m "feat: track qualified playback events"
```

### Task 7: Home Tab 远距离跳转闪烁

- [ ] **Step 1: 固化根因**

确认当前点击处理把 `selectedTab` 和 `proxy.scrollTo` 放在同一个 `withAnimation`，而内容使用 `PageTabViewStyle`。

- [ ] **Step 2: 修改点击事务**

实现：

```swift
Button {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        viewModel.selectedTab = idx
    }
    withAnimation(.easeInOut(duration: 0.22)) {
        proxy.scrollTo(idx, anchor: .center)
    }
} label: {
    // 保持现有 UI
}
```

`onChange` 只负责顶部 Tab 条居中，不再次改变 selection。不要增加 delay、opacity 或中间状态。

- [ ] **Step 3: 构建并手工验证**

验收：

- Popular 点击 Anime 直接显示 Anime。
- Popular 点击 Original+ 直接显示 Original+。
- 中间 Tab 不闪烁。
- 手势左右分页仍有系统动画。
- 顶部 Tab 条仍会居中。

- [ ] **Step 4: 提交 Tab 修复检查点**

```bash
git add RelaxShort/Views/Home/HomeView.swift
git commit -m "fix: jump directly between home tabs"
```

### Task 8: 前后端联合验收

- [ ] **Step 1: API 合同 smoke**

对三个榜单分别确认 12 条数据，记录首名、`rank_position`、`metric_value` 和 `generated_at`。

- [ ] **Step 2: 模拟器联调**

验证：

- Search 三个榜单顺序与 curl 一致。
- 热度与 API `metric_value` 一致，不等同于普通 `view_count`。
- Trending Searches 与 `/search/default` 一致。
- 提交搜索、点击结果、播放 10 秒后，后端事件表出现对应事件。
- Worker 下一轮运行后，相关小时聚合发生变化。

- [ ] **Step 3: 多尺寸构建**

```bash
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)'
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

若本机没有指定 runtime，使用已安装的同级小屏、标准屏、大屏设备并如实记录。

- [ ] **Step 4: 全量检查**

```bash
git diff --check
git status --short
```

确认无临时日志、无 fixture 进入生产 bundle、无未使用旧 Ranking DTO。

- [ ] **Step 5: 最终交付**

只给简短中文简报：

- 修改文件和关键合同。
- 测试/构建结果。
- Tab 闪烁、标题字重、真实榜单指标验收结果。
- 事件从 iOS 到 Worker 聚合的数据库证据。
- 真实遗留风险。

不要另写重复交付报告，不提交、不推送最终整包，等待 Codex review。
