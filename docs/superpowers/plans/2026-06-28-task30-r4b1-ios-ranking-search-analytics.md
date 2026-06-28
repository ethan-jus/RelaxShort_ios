# Task30 R4B-1 iOS 榜单与搜索事件联调 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 严格消费后端动态榜单合同，并通过可靠、持久化的批量队列上报搜索提交和搜索结果点击事件。

**Architecture:** Repository 把后端榜单 DTO 转成 `RankingEntry`，ViewModel 只消费领域模型。`DiscoveryAnalyticsReporter` Actor 独立负责持久化、批量发送和重试，`DiscoveryAnalyticsClient` 为 UI 提供同步、非阻塞的搜索事件接口。

**Tech Stack:** Swift 6、SwiftUI、Swift Concurrency、URLSession、Security.framework、XCTest、Xcode 16+

---

## 执行边界

- 工作目录：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`
- 先读取根目录与 iOS `AGENTS.md`、`CLAUDE.md` 和设计文档：
  - `docs/superpowers/specs/2026-06-28-task30-r4b1-ios-ranking-search-analytics-design.md`
- 后端已提供：
  - `GET /api/v2/rankings`
  - `GET /api/v2/search/default`
  - `POST /api/v2/events/discovery/batch`
- 使用 ECC Swift、SwiftUI、Concurrency、Testing、Security 规则，并在简报中列出实际参考项。
- 不修改 Search 已验收的布局、颜色、渐变、分页和间距。
- 不修改 PlayerKit、播放器 View、播放生命周期或播放器日志。
- 不接入 `qualified_play`、`play_complete`；这些属于 R4B-2。
- 不增加第三方 Analytics SDK，不读取 IDFA。
- 不写重复交付报告，只输出简短中文交付简报。
- 不提交、不推送最终整包，等待 Codex review。

## 文件结构

**创建：**

- `RelaxShort/Models/RankingEntry.swift`
- `RelaxShort/Models/API/RankingResponseDTO.swift`
- `RelaxShort/Core/Analytics/InstallIdentityProvider.swift`
- `RelaxShort/Core/Analytics/DiscoveryEvent.swift`
- `RelaxShort/Core/Analytics/DiscoveryEventTransport.swift`
- `RelaxShort/Core/Analytics/DiscoveryEventQueueStore.swift`
- `RelaxShort/Core/Analytics/DiscoveryAnalyticsReporter.swift`
- `RelaxShort/Core/Analytics/DiscoveryAnalyticsClient.swift`
- `RelaxShortTests/RankingResponseDTOTests.swift`
- `RelaxShortTests/InstallIdentityProviderTests.swift`
- `RelaxShortTests/DiscoveryAnalyticsReporterTests.swift`
- `RelaxShortTests/SearchAnalyticsTests.swift`

**修改：**

- `RelaxShort.xcodeproj/project.pbxproj`
- `RelaxShort/Core/Services/APIEndpoint.swift`
- `RelaxShort/Core/Services/APIClient.swift`
- `RelaxShort/Core/Services/RepositoryProtocols.swift`
- `RelaxShort/Core/Services/RealHomeRepository.swift`
- `RelaxShort/Core/Services/RealAPISmokeRunner.swift`
- `RelaxShort/Core/Services/DependencyContainer.swift`
- `RelaxShort/Models/RankDrama.swift`
- `RelaxShort/ViewModels/SearchDefaultViewModel.swift`
- `RelaxShort/ViewModels/SearchViewModel.swift`
- `RelaxShort/ViewModels/RankViewModel.swift`
- `RelaxShort/Views/Search/SearchRankTheme.swift`
- `RelaxShort/Views/Search/SearchView.swift`
- `RelaxShort/Views/MainTabView.swift`
- `RelaxShort/App/RelaxShortApp.swift`

## Task 1：建立最小测试 Target

**Files:**

- Modify: `RelaxShort.xcodeproj/project.pbxproj`
- Create: `RelaxShortTests/RankingResponseDTOTests.swift`

- [ ] **Step 1：新增 `RelaxShortTests` Unit Test Target**

Target 必须：

- product type 为 `com.apple.product-type.bundle.unit-test`
- 依赖 `RelaxShort` App target
- `PRODUCT_BUNDLE_IDENTIFIER = com.relaxshort.ios.tests`
- `TEST_HOST = $(BUILT_PRODUCTS_DIR)/RelaxShort.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/RelaxShort`
- `BUNDLE_LOADER = $(TEST_HOST)`
- 加入共享 scheme 的 Test action

不得重排或批量重写无关 `project.pbxproj` 区块。

- [ ] **Step 2：增加最小失败测试**

```swift
import XCTest
@testable import RelaxShort

final class RankingResponseDTOTests: XCTestCase {
    func testDecodesNestedRankingItemContract() throws {
        let json = """
        {
          "type":"trending",
          "content_language":"en",
          "country_code":"GLOBAL",
          "generated_at":"2026-06-28T04:20:00",
          "items":[{
            "rank_position":1,
            "metric_type":"qualified_play_count_24h",
            "metric_value":12,
            "card":{
              "series_id":20250312000005,
              "localized_title":"What a Good Girl",
              "cover_url":"https://example.com/cover.jpg"
            }
          }]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(
            RankingResponseDTO.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(dto.generatedAt, "2026-06-28T04:20:00")
        XCTAssertEqual(dto.items.first?.rankPosition, 1)
        XCTAssertEqual(dto.items.first?.metricValue, 12)
        XCTAssertEqual(dto.items.first?.card.seriesId, 20_250_312_000_005)
    }
}
```

- [ ] **Step 3：运行测试确认 RED**

```bash
xcodebuild test \
  -project RelaxShort.xcodeproj \
  -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/RankingResponseDTOTests
```

预期：因为新 DTO 尚不存在而失败；不能以 scheme 未包含 Test target 作为 RED。

## Task 2：修正 Rankings 合同和三个榜单映射

**Files:**

- Create: `RelaxShort/Models/RankingEntry.swift`
- Create: `RelaxShort/Models/API/RankingResponseDTO.swift`
- Modify: `RelaxShort/Core/Services/RepositoryProtocols.swift`
- Modify: `RelaxShort/Core/Services/RealHomeRepository.swift`
- Modify: `RelaxShort/Core/Services/RealAPISmokeRunner.swift`
- Modify: `RelaxShort/Models/RankDrama.swift`
- Modify: `RelaxShort/ViewModels/SearchDefaultViewModel.swift`
- Modify: `RelaxShort/ViewModels/RankViewModel.swift`
- Modify: `RelaxShort/Views/Search/SearchRankTheme.swift`
- Test: `RelaxShortTests/RankingResponseDTOTests.swift`

- [ ] **Step 1：实现 DTO 与领域模型**

```swift
struct RankingResponseDTO: Decodable {
    let type: String
    let contentLanguage: String
    let countryCode: String
    let generatedAt: String?
    let matchedLanguage: String?
    let fallbackReason: String?
    let items: [RankingItemDTO]
}

struct RankingItemDTO: Decodable {
    let rankPosition: Int
    let metricType: String
    let metricValue: Int64
    let card: FeedCardDTO
}

struct RankingEntry: Identifiable {
    let rankPosition: Int
    let metricType: String
    let metricValue: Int64
    let drama: DramaItem

    var id: String { "\(rankPosition):\(drama.id)" }
}
```

删除 `RealHomeRepository.swift` 末尾旧的：

```swift
struct RankingResponseDTO: Decodable {
    let items: [FeedCardDTO]?
}
```

- [ ] **Step 2：修改 Repository 合同**

```swift
protocol HomeRepositoryProtocol {
    func fetchRankingEntries(type: String) async throws -> [RankingEntry]
}
```

一次性删除旧 `fetchRankings(type:) -> [DramaItem]`，更新全部调用方，不保留双合同。

Mock 默认实现允许使用本地 `viewCount` 生成测试指标，但只能存在于 Mock：

```swift
func fetchRankingEntries(type: String) async throws -> [RankingEntry] {
    let dramas = try await fetchDramas(category: .all)
    return dramas.prefix(20).enumerated().map { index, drama in
        RankingEntry(
            rankPosition: index + 1,
            metricType: "mock_view_count",
            metricValue: Int64(drama.viewCount),
            drama: drama
        )
    }
}
```

- [ ] **Step 3：Real Repository 严格映射后端顺序**

```swift
func fetchRankingEntries(type: String) async throws -> [RankingEntry] {
    let contentLanguage = UserDefaults.standard.string(
        forKey: "app_content_language"
    )
    let countryCode = UserDefaults.standard.string(
        forKey: "app_country_code"
    )
    let dto: RankingResponseDTO = try await client.requestData(
        .rankings(
            type: type,
            contentLanguage: contentLanguage,
            countryCode: countryCode
        )
    )
    return dto.items.map {
        RankingEntry(
            rankPosition: $0.rankPosition,
            metricType: $0.metricType,
            metricValue: $0.metricValue,
            drama: FeedCardDTOMapper.toDramaItem(from: $0.card)
        )
    }
}
```

禁止 `enumerated()`、`sorted`、`viewCount` 覆盖后端排名。

- [ ] **Step 4：修正固定标题与 API type**

`SearchRankTheme`：

```swift
case .topSearched:   return "top_searched"
case .mostTrending:  return "trending"
case .newReleases:   return "new_releases"
```

`RankCategory` 保持现有 UI case，但映射必须为：

```swift
case .hot:       return "trending"
case .trending:  return "top_searched"
case .new:       return "new_releases"
```

- [ ] **Step 5：RankDrama 使用真实指标**

```swift
init(entry: RankingEntry) {
    id = entry.drama.id
    rank = entry.rankPosition
    title = entry.drama.title
    coverURL = entry.drama.coverURL
    category = entry.drama.category
    tags = entry.drama.tags
    hot = RankingMetricFormatter.string(from: entry.metricValue)
    drama = entry.drama
}
```

`RankingMetricFormatter` 至少覆盖：

```swift
XCTAssertEqual(RankingMetricFormatter.string(from: 999), "999")
XCTAssertEqual(RankingMetricFormatter.string(from: 51_000), "51K")
XCTAssertEqual(RankingMetricFormatter.string(from: 1_250_000), "1.3M")
```

`RankingMetricFormatter` 放在 `RankDrama.swift`，只负责整数指标显示，不读取 `DramaItem.viewCount`。

- [ ] **Step 6：更新 ViewModel 和 Smoke Runner**

`SearchDefaultViewModel`、`RankViewModel` 直接执行：

```swift
let entries = try await repository.fetchRankingEntries(type: type)
dramas = entries.map(RankDrama.init(entry:))
```

`RealAPISmokeRunner` 从 `dto.items.first?.card.seriesId` 读取 series ID。

- [ ] **Step 7：验证 GREEN**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/RankingResponseDTOTests
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

## Task 3：稳定匿名安装身份

**Files:**

- Create: `RelaxShort/Core/Analytics/InstallIdentityProvider.swift`
- Modify: `RelaxShort/Core/Services/APIEndpoint.swift`
- Test: `RelaxShortTests/InstallIdentityProviderTests.swift`

- [ ] **Step 1：写失败测试**

使用内存 Keychain fake：

```swift
func testInstallIDIsStable() {
    let store = InMemoryKeychainStore()
    let providerA = InstallIdentityProvider(store: store)
    let first = providerA.installID()
    let providerB = InstallIdentityProvider(store: store)

    XCTAssertEqual(first, providerA.installID())
    XCTAssertEqual(first, providerB.installID())
    XCTAssertNotNil(UUID(uuidString: first))
}
```

另测 Keychain 写入失败时，同一 provider 实例始终返回同一个内存 UUID。

- [ ] **Step 2：运行测试确认 RED**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/InstallIdentityProviderTests
```

- [ ] **Step 3：实现真实 Keychain**

```swift
protocol KeychainStoring {
    func data(service: String, account: String) -> Data?
    func save(_ data: Data, service: String, account: String) throws
}

final class InstallIdentityProvider {
    static let shared = InstallIdentityProvider(store: SystemKeychainStore())

    private let store: KeychainStoring
    private var memoryID: String?

    func installID() -> String {
        if let memoryID { return memoryID }
        if let data = store.data(service: service, account: "install-id"),
           let value = String(data: data, encoding: .utf8),
           UUID(uuidString: value) != nil {
            memoryID = value
            return value
        }
        let value = UUID().uuidString.lowercased()
        try? store.save(Data(value.utf8), service: service, account: "install-id")
        memoryID = value
        return value
    }
}
```

`SystemKeychainStore` 使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。不得修改现有登录 Token 的存储实现。

- [ ] **Step 4：统一真实 API 请求头**

在 `APIEndpoint.headers` 为真实 `/api/v2/**` 请求增加：

```swift
base["X-Device-Id"] = InstallIdentityProvider.shared.installID()
```

不要输出此值，不增加 `X-Install-Id`。

- [ ] **Step 5：验证 GREEN**

运行安装身份测试和 App build。

## Task 4：事件 DTO、Transport 与持久化 Reporter

**Files:**

- Create: `RelaxShort/Core/Analytics/DiscoveryEvent.swift`
- Create: `RelaxShort/Core/Analytics/DiscoveryEventTransport.swift`
- Create: `RelaxShort/Core/Analytics/DiscoveryEventQueueStore.swift`
- Create: `RelaxShort/Core/Analytics/DiscoveryAnalyticsReporter.swift`
- Modify: `RelaxShort/Core/Services/APIEndpoint.swift`
- Modify: `RelaxShort/Core/Services/APIClient.swift`
- Test: `RelaxShortTests/DiscoveryAnalyticsReporterTests.swift`

- [ ] **Step 1：定义后端合同 DTO**

```swift
enum DiscoveryEventType: String, Codable, Sendable {
    case searchSubmit = "search_submit"
    case searchResultClick = "search_result_click"
}

struct DiscoveryEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let eventType: DiscoveryEventType
    let seriesID: Int64?
    let searchTerm: String?
    let contentLanguage: String
    let countryCode: String
    let sourceScene: String
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "event_id"
        case eventType
        case seriesID
        case searchTerm
        case contentLanguage
        case countryCode
        case sourceScene
        case occurredAt
    }
}

struct DiscoveryEventBatchRequest: Encodable, Sendable {
    let events: [DiscoveryEvent]
}

struct DiscoveryEventBatchResponseDTO: Decodable, Sendable {
    let acceptedCount: Int
    let duplicateCount: Int
    let totalCount: Int
}
```

为 `DiscoveryEvent` 提供显式 `CodingKeys`，把 `id` 编码为 `event_id`，日期使用 ISO-8601。不能把字符串 series ID 原样发给后端数字字段。

同文件定义专用编解码器，避免依赖全局默认策略：

```swift
extension JSONEncoder {
    static func discoveryEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static func discoveryDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 2：新增 typed POST endpoint**

```swift
case discoveryEvents(DiscoveryEventBatchRequest)
```

- path：`/api/v2/events/discovery/batch`
- method：POST
- baseURL：真实 v2
- body：`try? JSONEncoder.discoveryEncoder().encode(request)`

不得使用 `[String: Any]` 手拼事件 body。

`APIClient.logRequest` 必须能识别 `.discoveryEvents`。该端点只记录 method 和 URL，禁止打印 body；不要改变其他接口的错误映射。

- [ ] **Step 3：定义可测试 Transport**

```swift
protocol DiscoveryEventTransport: Sendable {
    func send(events: [DiscoveryEvent]) async throws
        -> DiscoveryEventBatchResponseDTO
}

struct APIClientDiscoveryEventTransport: DiscoveryEventTransport {
    func send(events: [DiscoveryEvent]) async throws
        -> DiscoveryEventBatchResponseDTO {
        try await APIClient.shared.requestData(
            .discoveryEvents(.init(events: events))
        )
    }
}
```

- [ ] **Step 4：写 Reporter RED 测试**

覆盖：

```swift
// 20 条事件触发一次发送。
// 发送失败后队列仍保留。
// accepted + duplicate == batch.count 时删除当前批次。
// flush 期间新入队事件不会被旧响应删除。
// 重建 Reporter 后恢复 event_id 和顺序。
// 测试注入 10ms delay，验证低于 20 条的延迟 flush。
// 超过 500 条只保留最新 500 条。
```

测试必须使用 Fake Transport 和临时目录，禁止真实网络。

- [ ] **Step 5：实现原子队列存储**

```swift
struct DiscoveryEventQueueStore {
    let fileURL: URL

    func load() -> [DiscoveryEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.discoveryDecoder().decode(
            [DiscoveryEvent].self,
            from: data
        )) ?? []
    }

    func save(_ events: [DiscoveryEvent]) throws {
        let data = try JSONEncoder.discoveryEncoder().encode(events)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

生产文件位于 Application Support。损坏文件隔离后从空队列恢复，不循环崩溃。

- [ ] **Step 6：实现 Actor**

```swift
actor DiscoveryAnalyticsReporter {
    private var queue: [DiscoveryEvent]
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false
    private let transport: DiscoveryEventTransport
    private let store: DiscoveryEventQueueStore
    private let flushDelayNanoseconds: UInt64

    func track(_ event: DiscoveryEvent) async {
        guard !queue.contains(where: { $0.id == event.id }) else { return }
        queue.append(event)
        if queue.count > 500 { queue.removeFirst(queue.count - 500) }
        try? store.save(queue)
        if queue.count >= 20 {
            await flush()
        } else {
            scheduleFlushIfNeeded()
        }
    }

    func flush() async {
        guard !isFlushing, !queue.isEmpty else { return }
        flushTask?.cancel()
        flushTask = nil
        isFlushing = true
        defer { isFlushing = false }

        let batch = Array(queue.prefix(20))
        do {
            let response = try await sendWithRetry(batch)
            let confirmed = response.acceptedCount + response.duplicateCount
            guard confirmed == batch.count else { return }
            remove(batch)
        } catch NetworkError.unauthorized {
            remove(batch)
        } catch NetworkError.badStatus(let code)
                    where (400..<500).contains(code) {
            remove(batch)
        } catch {
            // 可恢复错误保留原队列，等待生命周期或后续事件再次触发。
        }
    }

    private func sendWithRetry(
        _ batch: [DiscoveryEvent]
    ) async throws -> DiscoveryEventBatchResponseDTO {
        let delays: [UInt64] = [0, 2, 5, 15, 60]
        var lastError: Error = NetworkError.invalidResponse
        for seconds in delays {
            if seconds > 0 {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
            do {
                return try await transport.send(events: batch)
            } catch {
                if let networkError = error as? NetworkError {
                    switch networkError {
                    case .badStatus(let code) where (400..<500).contains(code),
                         .unauthorized:
                        throw networkError
                    default:
                        break
                    }
                }
                lastError = error
            }
        }
        throw lastError
    }

    private func remove(_ batch: [DiscoveryEvent]) {
        let confirmedIDs = Set(batch.map(\.id))
        queue.removeAll { confirmedIDs.contains($0.id) }
        try? store.save(queue)
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else { return }
        let delay = flushDelayNanoseconds
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            await self?.runScheduledFlush()
        }
    }

    private func runScheduledFlush() async {
        flushTask = nil
        await flush()
    }
}
```

要求：

- 仅一个延迟 flush Task。
- 首次发送失败后按 2、5、15、60 秒最多重试 4 次，之后保留队列等待下次触发。
- 4xx 合同错误丢弃当前无效批次并写一条 DEBUG 日志。
- 网络错误、超时和 5xx 保留批次。
- Release 不打印 event body、搜索词或安装 ID。

- [ ] **Step 7：运行 Reporter 测试确认 GREEN**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/DiscoveryAnalyticsReporterTests
```

## Task 5：UI Analytics Client 与搜索事件接入

**Files:**

- Create: `RelaxShort/Core/Analytics/DiscoveryAnalyticsClient.swift`
- Modify: `RelaxShort/Core/Services/DependencyContainer.swift`
- Modify: `RelaxShort/ViewModels/SearchViewModel.swift`
- Modify: `RelaxShort/Views/Search/SearchView.swift`
- Modify: `RelaxShort/Views/MainTabView.swift`
- Modify: `RelaxShort/App/RelaxShortApp.swift`
- Test: `RelaxShortTests/SearchAnalyticsTests.swift`

- [ ] **Step 1：定义同步、可注入的 UI 协议**

```swift
@MainActor
protocol DiscoveryAnalyticsTracking {
    func trackSearchSubmit(query: String)
    func trackSearchResultClick(query: String, seriesID: String)
    func flushPending()
    func flushForBackground()
}

@MainActor
struct NoopDiscoveryAnalyticsTracker: DiscoveryAnalyticsTracking {
    func trackSearchSubmit(query: String) {}
    func trackSearchResultClick(query: String, seriesID: String) {}
    func flushPending() {}
    func flushForBackground() {}
}
```

`DiscoveryAnalyticsClient` 读取当前 `app_content_language` 和 `app_country_code`，创建事件后用短 Task 投递给 Reporter。无法转换为 `Int64` 的 series ID 不上报并仅写 DEBUG 日志。

`SearchViewModel` 构造器调整为：

```swift
init(
    repository: SearchRepositoryProtocol,
    analytics: DiscoveryAnalyticsTracking = NoopDiscoveryAnalyticsTracker()
) {
    self.repository = repository
    self.analytics = analytics
    loadHistory()

    $searchText
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .removeDuplicates()
        .sink { [weak self] query in
            Task { await self?.performSearch(query: query) }
        }
        .store(in: &cancellables)
}
```

- [ ] **Step 2：写 Search RED 测试**

使用 Spy Tracker 断言：

```swift
viewModel.searchText = "  Jiang   Nan  "
viewModel.submitSearch()
XCTAssertEqual(spy.submittedQueries, ["Jiang Nan"])

viewModel.searchFromHistory("CEO")
XCTAssertEqual(spy.submittedQueries.last, "CEO")

viewModel.trackResultClick(dramaID: "20250312000001")
XCTAssertEqual(spy.resultClicks.last?.query, "CEO")
```

另外断言：

- 输入防抖不会调用 tracker。
- Retry 和分页不会产生 `search_submit`。
- 空查询不产生事件。

- [ ] **Step 3：规范化查询词并接入提交**

`SearchViewModel.normalize` 必须 trim 并折叠连续空白：

```swift
query
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .split(whereSeparator: \.isWhitespace)
    .joined(separator: " ")
```

`submitSearch` 和 `searchFromHistory` 每个用户动作只调用一次 `trackSearchSubmit`。

- [ ] **Step 4：搜索结果点击先入队再导航**

新增：

```swift
func trackResultClick(dramaID: String) {
    let query = normalize(searchText)
    guard !query.isEmpty else { return }
    analytics.trackSearchResultClick(query: query, seriesID: dramaID)
}
```

`SearchView.onChange(of: playerDrama)`：

```swift
guard let drama else { return }
viewModel.trackResultClick(dramaID: drama.id)
openPlayer(drama)
playerDrama = nil
```

默认页榜单继续直接 `openPlayer`，不得伪造搜索结果点击。

- [ ] **Step 5：DependencyContainer 注入**

真实 API 模式使用 `DiscoveryAnalyticsClient`，Mock 模式使用 Noop：

```swift
let discoveryAnalytics: DiscoveryAnalyticsTracking
```

`DependencyContainer.init` 接收可选 `discoveryAnalytics` 测试依赖；未传入时按 `use_real_api` 创建真实 Client 或 Noop。创建 `SearchViewModel` 时显式传入该依赖，禁止在 ViewModel 内访问单例。

`SearchView` initializer 新增 `analytics` 参数；`MainTabView` 搜索导航必须传入：

```swift
SearchView(
    searchRepository: dependencies.searchRepository,
    discoveryRepository: dependencies.homeRepository,
    analytics: dependencies.discoveryAnalytics
)
```

- [ ] **Step 6：App 生命周期 flush**

在已有 `scenePhase` 处理内增加：

```swift
if newPhase == .background {
    dependencies.discoveryAnalytics.flushForBackground()
}
if newPhase == .active {
    dependencies.discoveryAnalytics.flushPending()
}
```

不得阻塞热启动广告逻辑。

- [ ] **Step 7：运行 Search 测试确认 GREEN**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:RelaxShortTests/SearchAnalyticsTests
```

## Task 6：联合验证和交付

**Files:**

- Verify only; no duplicate delivery report.

- [ ] **Step 1：全量测试与标准构建**

```bash
xcodebuild test -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 2：多尺寸编译门禁**

```bash
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)'
xcodebuild build -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

若设备未安装，只替换为本机已有的同级小屏/大屏，并如实报告。

- [ ] **Step 3：真实 API smoke**

确认三个接口：

```bash
curl -sS 'http://127.0.0.1:8080/api/v2/rankings?type=top_searched&content_language=en&country_code=GLOBAL'
curl -sS 'http://127.0.0.1:8080/api/v2/rankings?type=trending&content_language=en&country_code=GLOBAL'
curl -sS 'http://127.0.0.1:8080/api/v2/rankings?type=new_releases&content_language=en&country_code=GLOBAL'
```

记录 `generated_at`、首名 `series_id`、`metric_type` 和 `metric_value`；`new_releases` 允许真实返回空数组。

- [ ] **Step 4：模拟器手工联调清单**

由用户在 Xcode 模拟器验证：

- Search 三榜单顺序和热度与 API 一致。
- Top Searched 与 Most Trending 不再显示相同错误映射。
- 空 New Releases 正常显示空态，不出现 Mock。
- 键盘提交、Recent Searches、Trending Searches 各上报一次。
- 点击搜索结果后立即导航，不等待上报网络。
- 关闭后端时搜索和导航仍可工作，事件保留；恢复后可 flush。

- [ ] **Step 5：数据库证据**

用户完成一次搜索提交和一次结果点击后，检查：

```sql
SELECT event_id, event_type, series_id, search_term,
       content_language, country_code, source_scene, occurred_at
FROM rs_discovery_events
WHERE source_scene = 'search'
ORDER BY id DESC
LIMIT 10;
```

确认事件合法、无重复、时间为 UTC 语义；不得在交付报告暴露安装 ID hash。

- [ ] **Step 6：代码质量检查**

```bash
git diff --check
git status --short
rg -n 'qualified_play|play_complete|PlayerKit|ShortVideoPlayerEngine' RelaxShort/Core/Analytics
```

最后一条不得发现本任务新增的播放器实现。

- [ ] **Step 7：交付简报**

只输出：

- 修改文件与合同。
- XCTest 和三类尺寸 build 结果。
- 三榜单真实 API 对齐结果。
- 搜索事件入库证据。
- 真实遗留风险。

不得新增重复 `TASK30_R4B1_DELIVERY_REPORT.md`，不得提交或推送最终整包。
