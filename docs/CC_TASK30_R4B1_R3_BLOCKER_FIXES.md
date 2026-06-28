# Task30 R4B-1 R3 阻断问题收敛计划

> **执行代理要求：** 严格逐项执行。不要提交、不要推送、不要再手写创建 Test Target。

## 目标

修复 R2 中已确认的 JSON 合同错误、安装 ID 并发竞态、播放器旧 Recovery 回调复活、
文件边界和工作树污染。R3 不扩展功能，不调整 UI。

## 当前结论

R2 不通过，原因不是“缺少测试”这么简单：

1. `APIClient` 使用 `.convertFromSnakeCase`，新增 DTO 又使用蛇形 `CodingKeys`，
   `rank_position`、`accepted_count` 等字段必然解码失败。
2. `DiscoveryEvent` 持久化也使用相同错误组合，App 重启后队列无法恢复。
3. `InstallIdentityProvider` 的锁只保护局部读写，未保护完整 read-or-create 流程，
   并发调用仍可能返回多个 UUID。
4. `cancelPendingRecovery()` 只能取消 Task，已经进入 `AVPlayer.seek` 的 completion
   仍可能在重新进入页面、`wantsPlayback` 再次变为 true 后恢复旧播放器。
5. Analytics 文件同时存在于 `APIClient.swift` 和未加入工程的 `Core/Analytics/`，
   当前是重复半成品。
6. `Package.resolved` 被意外删除，`git diff --check` 仍有错误。

## 禁止事项

- 不改 UI。
- 不调整后端。
- 不删除真实 API 行为。
- 不保留两套 Analytics 类型。
- 不把测试或文件拆分再次写成“后续 PR”。
- 不手写 Test Target，不修改 PBX target 结构。
- 不提交、不推送。

## Task 1：恢复干净工程基线

### 修改

恢复意外删除的锁文件：

```bash
git restore -- RelaxShort.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

清理所有 trailing whitespace，不改变相关逻辑。

### 验证

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -list
```

要求：

- `git diff --check` 无输出。
- `xcodebuild -list` 能正常读取工程。

## Task 2：修复 DTO 与持久化 JSON 合同

### 文件

- 新建 `RelaxShort/Models/API/RankingResponseDTO.swift`
- 新建 `RelaxShort/Models/RankingEntry.swift`
- 修改 `RelaxShort/Core/Analytics/DiscoveryEvent.swift`
- 修改 `RelaxShort/Core/Services/APIClient.swift`
- 修改 `RelaxShort/Models/API/ForYouFeedResponseDTO.swift`
- 修改 `RelaxShort/Models/RankDrama.swift`

### Ranking DTO

项目统一 Decoder 已执行 `.convertFromSnakeCase`，因此 DTO 不得再声明蛇形
`CodingKeys`：

```swift
struct RankingResponseDTO: Decodable, Sendable {
    let type: String
    let contentLanguage: String?
    let countryCode: String?
    let generatedAt: String?
    let matchedLanguage: String?
    let fallbackReason: String?
    let items: [RankingItemDTO]
}

struct RankingItemDTO: Decodable, Sendable {
    let rankPosition: Int
    let metricType: String
    let metricValue: Int64
    let card: FeedCardDTO
}
```

从 `ForYouFeedResponseDTO.swift` 删除这两个类型。

### Discovery Event

不要用 `id = "event_id"` 的自定义 CodingKey。使用真实属性 `eventID`，让
`.convertToSnakeCase/.convertFromSnakeCase` 自动处理：

```swift
struct DiscoveryEvent: Codable, Identifiable, Sendable {
    let eventID: UUID
    let eventType: DiscoveryEventType
    let seriesID: Int64?
    let searchTerm: String?
    let contentLanguage: String
    let countryCode: String
    let sourceScene: String
    let occurredAt: Date

    var id: UUID { eventID }
}

struct DiscoveryEventBatchResponseDTO: Decodable, Sendable {
    let acceptedCount: Int
    let duplicateCount: Int
    let totalCount: Int
}
```

同步修改所有构造调用，从 `id:` 改为 `eventID:`。

### 验证

增加一个临时、可删除的 Swift 合同验证脚本或在现有 Debug smoke 中验证以下 JSON：

```json
{
  "type": "trending",
  "content_language": "en",
  "country_code": "GLOBAL",
  "items": [{
    "rank_position": 1,
    "metric_type": "qualified_play_count_24h",
    "metric_value": 51,
    "card": {}
  }]
}
```

Ranking 测试中的 `card` 必须使用完整可解码的 `FeedCardDTO` fixture，不能用空对象。

还必须完成 Discovery Event round-trip：

1. 编码后包含 `event_id`、`event_type`、`occurred_at`。
2. 写入队列文件后能重新 load。
3. `accepted_count` 响应能正确解码。

## Task 3：完成 Analytics 文件拆分

### 最终文件

- `RelaxShort/Core/Analytics/InstallIdentityProvider.swift`
- `RelaxShort/Core/Analytics/DiscoveryEvent.swift`
- `RelaxShort/Core/Analytics/DiscoveryEventTransport.swift`
- `RelaxShort/Core/Analytics/DiscoveryEventQueueStore.swift`
- `RelaxShort/Core/Analytics/DiscoveryAnalyticsReporter.swift`
- `RelaxShort/Core/Analytics/DiscoveryAnalyticsClient.swift`
- `RelaxShort/Models/API/RankingResponseDTO.swift`
- `RelaxShort/Models/RankingEntry.swift`

`APIClient.swift` 只保留网络客户端，不得保留 `// MARK: - Analytics Types` 后的
Analytics 定义。

本机已安装 `python-pbxproj`。只用它添加普通 Swift 文件到现有 App target，
不得用它创建 Target：

```python
from pbxproj import XcodeProject

project = XcodeProject.load("RelaxShort.xcodeproj/project.pbxproj")
paths = [
    "RelaxShort/Core/Analytics/InstallIdentityProvider.swift",
    "RelaxShort/Core/Analytics/DiscoveryEvent.swift",
    "RelaxShort/Core/Analytics/DiscoveryEventTransport.swift",
    "RelaxShort/Core/Analytics/DiscoveryEventQueueStore.swift",
    "RelaxShort/Core/Analytics/DiscoveryAnalyticsReporter.swift",
    "RelaxShort/Core/Analytics/DiscoveryAnalyticsClient.swift",
    "RelaxShort/Models/API/RankingResponseDTO.swift",
    "RelaxShort/Models/RankingEntry.swift",
]
for path in paths:
    project.add_file(path, target_name="RelaxShort", force=False)
project.save()
```

执行后用 `rg` 确认每个类型只有一份定义。

## Task 4：修复安装 ID 原子性

### 文件

- `RelaxShort/Core/Analytics/InstallIdentityProvider.swift`

锁必须覆盖完整 read-or-create 临界区：

```swift
func installID() -> String {
    lock.lock()
    defer { lock.unlock() }

    if let memoryID {
        return memoryID
    }

    if let data = store.data(service: service, account: account),
       let value = String(data: data, encoding: .utf8),
       UUID(uuidString: value) != nil {
        memoryID = value
        return value
    }

    let value = UUID().uuidString.lowercased()
    do {
        try store.save(Data(value.utf8), service: service, account: account)
    } catch {
        Logger.analytics.error("Install ID persistence failed: \(error.localizedDescription)")
    }
    memoryID = value
    return value
}
```

不得在锁外执行 Keychain 读取、生成或保存。

## Task 5：封住 Recovery 旧 completion

### 文件

- `RelaxShort/PlayerKit/PlayerRecoveryController.swift`
- `RelaxShort/PlayerKit/PlayerCoordinator.swift`

在 Recovery Controller 增加递增 token：

```swift
private var recoveryGeneration = 0
```

`cancelPendingRecovery()` 必须先：

```swift
recoveryGeneration &+= 1
```

每次 `attemptRecovery()` 取消旧任务后也生成新的 token，并捕获：

```swift
recoveryGeneration &+= 1
let token = recoveryGeneration
let expectedItemID = item.id
```

在 sleep 后、ready 后、seek completion 内、更新 Engine state 前全部验证：

```swift
guard self.recoveryGeneration == token,
      engine.currentItem?.id == expectedItemID,
      engine.currentPlayer === player,
      engine.wantsPlayback else {
    continuation.resume()
    return
}
```

旧任务结束时不得把新任务的 `recoveryTask` 清空：

```swift
if self.recoveryGeneration == token {
    self.recoveryTask = nil
}
```

`PlayerCoordinator.claimForYou` 在真正切换 owner 前调用
`invalidateCurrentClaim()`，取消遗留 Series handoff；同 owner、同 item 直接复用可提前返回。

## Task 6：修复队列可靠性

### 文件

- `RelaxShort/Core/Analytics/DiscoveryEventQueueStore.swift`
- `RelaxShort/Core/Analytics/DiscoveryAnalyticsReporter.swift`

要求：

- 队列 JSON 损坏时重命名为
  `discovery_event_queue.corrupt-<timestamp>.json`，不得直接删除。
- HTTP 408、429 不得作为永久 4xx 删除事件，应保留并按可重试错误处理。
- 只有明确不可重试的请求校验错误才可丢弃批次，并记录错误日志。
- 保留后台单次 best-effort，不启动长重试链。

后端批次接口是事务性完整校验，正常成功响应应满足：

```swift
acceptedCount + duplicateCount == totalCount
```

若响应计数不完整，保留整个批次并记录错误，不猜测已确认事件 ID。

## Task 7：真实验证

### 工程验证

先恢复依赖：

```bash
xcodebuild -resolvePackageDependencies -project RelaxShort.xcodeproj
```

然后：

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,id=FFF36E82-EFBF-48A8-B999-89FB45193AAD' build

git diff --check
```

SE 只能用设备 ID 或显式 `OS=17.0`，因为 `name=...` 默认选择 latest runtime，
失败原因不是 Swift 6。

### API 联调

后端由用户在 IDEA 显式启动。验证：

1. 三个 rankings type 均能解码并展示，不走 Mock。
2. 搜索提交一次，结果点击一次。
3. App 进入后台再回前台。
4. 数据库出现 `search_submit` 和 `search_result_click`。
5. 重启 App 后待发送队列仍可恢复。

### 播放器手工验收

1. Home 进入 Series 自动播放。
2. 返回后等待 5 秒无声音。
3. 快速进入立即返回，等待 5 秒无延迟漏音。
4. 再次进入自动播放。
5. For You 进入 Series 后返回无漏音。

## 交付要求

只给中文简报，必须包含：

- DTO 合同验证结果。
- Analytics 类型唯一性检查。
- 两种设备构建结果。
- `git diff --check` 结果。
- rankings 与事件入库证据。
- 播放器五步手工验收注明“由用户待测”，不得伪造。
- 不得提交、不得推送。
