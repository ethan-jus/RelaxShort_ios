# Task30 R4B-1 R4 最终集成

## 目标

只修复两项剩余阻断：Discovery Event acronym JSON round-trip 和 Analytics 文件正式加入
Xcode target。不要扩展功能，不要提交或推送。

## 1. 修复 `eventID` / `seriesID` round-trip

`.convertFromSnakeCase` 会把 `event_id` 转成 `eventId`，不会转成 `eventID`。
因此 `DiscoveryEvent` 必须使用 camelCase raw value，而不是蛇形 raw value：

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

    enum CodingKeys: String, CodingKey {
        case eventID = "eventId"
        case eventType
        case seriesID = "seriesId"
        case searchTerm
        case contentLanguage
        case countryCode
        case sourceScene
        case occurredAt
    }
}
```

禁止写成 `"event_id"` 或 `"series_id"`，因为 Encoder/Decoder strategy 会负责 snake_case。

必须执行 round-trip，结果同时满足：

- 编码 JSON 包含 `event_id`、`series_id`、`event_type`。
- 同一 Decoder 能恢复原 `eventID` 和 `seriesID`。
- `accepted_count` 能解码为 `acceptedCount`。

## 2. 正式拆分并加入 App target

当前 `APIClient.swift` 实际为约 430 行，仍内联全部 Analytics；报告中的“160 行纯客户端”
不符合源码。完成后它应在网络客户端结束处停止，不得保留 Analytics 定义。

最终文件：

- `RelaxShort/Core/Analytics/InstallIdentityProvider.swift`
- `RelaxShort/Core/Analytics/DiscoveryEvent.swift`
- `RelaxShort/Core/Analytics/DiscoveryAnalyticsReporter.swift`
- `RelaxShort/Core/Analytics/DiscoveryAnalyticsClient.swift`
- `RelaxShort/Models/API/RankingResponseDTO.swift`
- `RelaxShort/Models/RankingEntry.swift`

从以下旧文件移除对应定义：

- `RelaxShort/Core/Services/APIClient.swift`
- `RelaxShort/Models/API/ForYouFeedResponseDTO.swift`
- `RelaxShort/Models/RankDrama.swift`

上一任务使用 `python-pbxproj force=False` 会扫描含 `productRef` 的 PBXBuildFile 并报
`fileRef` 缺失。已在临时工程副本验证：改用 `force=True` 可以正常加入文件。

```python
from pbxproj import XcodeProject

project = XcodeProject.load("RelaxShort.xcodeproj/project.pbxproj")
paths = [
    "RelaxShort/Core/Analytics/InstallIdentityProvider.swift",
    "RelaxShort/Core/Analytics/DiscoveryEvent.swift",
    "RelaxShort/Core/Analytics/DiscoveryAnalyticsReporter.swift",
    "RelaxShort/Core/Analytics/DiscoveryAnalyticsClient.swift",
    "RelaxShort/Models/API/RankingResponseDTO.swift",
    "RelaxShort/Models/RankingEntry.swift",
]
for path in paths:
    project.add_file(path, target_name="RelaxShort", force=True)
project.save()
```

不要创建 Test Target，不要修改现有 target 配置。

## 3. 验证

```bash
rg -n "^(final |struct |actor |protocol |enum ).*(InstallIdentityProvider|DiscoveryEvent|DiscoveryAnalytics|DiscoveryEventQueue|DiscoveryEventTransport|RankingResponseDTO|RankingEntry)" \
  RelaxShort -g '*.swift'

xcodebuild -project RelaxShort.xcodeproj -list

xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,id=FFF36E82-EFBF-48A8-B999-89FB45193AAD' build

git diff --check
git status --short
```

验收要求：

- 每个类型只有一个定义。
- `APIClient.swift` 不包含 Analytics 类型。
- 六个独立文件都出现在 `project.pbxproj` 的 file reference 和 Sources phase。
- iPhone 17 与 SE 构建通过。
- `git diff --check` 无输出。
- 不提交、不推送，只给中文简报。
