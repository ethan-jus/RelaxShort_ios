# Task30 R4B-1 iOS 榜单与搜索事件联调设计

## 目标

让 iOS 严格消费后端动态榜单合同，并可靠上报搜索提交和搜索结果点击事件，使真实用户行为能够进入后端小时聚合和榜单发布链路。

本阶段不修改 PlayerKit，不接入有效播放和完播事件。播放器事件单独进入 Task30 R4B-2，避免影响已经稳定的播放、预加载和恢复状态机。

## 范围

### 本阶段包含

- 消费 `GET /api/v2/rankings` 的 `rank_position`、`metric_type`、`metric_value` 和嵌套 `card`。
- 三个固定榜单映射：
  - `Top Searched` -> `top_searched`
  - `Most Trending` -> `trending`
  - `New Releases` -> `new_releases`
- 为安装实例生成稳定、匿名的 UUID，并通过 `X-Device-Id` 请求头发送。
- 通过 `POST /api/v2/events/discovery/batch` 上报：
  - `search_submit`
  - `search_result_click`
- 使用独立、持久化的 Actor 队列进行批量发送、失败保留和有限退避重试。
- 建立最小 iOS 测试 Target，验证 DTO、安装身份、队列和搜索事件语义。
- 前后端联合验证事件入库、小时聚合与动态榜单变化。

### 本阶段不包含

- `qualified_play`、`play_complete`、播放器曝光或播放时长统计。
- 修改播放器状态机、缓存、预加载、Recovery 或播放生命周期。
- 新增第三方 Analytics SDK。
- IDFA、广告追踪授权或设备指纹。
- 修改已验收的 Search 页面布局、颜色、渐变、分页和间距。

## 架构

### 榜单合同

API DTO 与 UI 模型保持分离：

```text
RankingResponseDTO
    -> RealHomeRepository
    -> RankingEntry
    -> SearchDefaultViewModel / RankViewModel
    -> Search / Home 榜单 UI
```

`RankingEntry` 保存后端排名、指标语义、指标值和 `DramaItem`。iOS 不允许使用数组下标、`viewCount` 或本地排序覆盖后端排名。

当后端返回空榜时，UI 使用现有空态，不回退 Mock 数据，也不拿上一批本地数据伪装当前榜单。

### 安装身份

`InstallIdentityProvider` 首次运行生成 UUID 并保存到 Keychain：

- service 使用 App bundle identifier。
- account 固定为 `install-id`。
- 不读取 IDFA。
- 不在日志中输出原始安装 ID。
- Keychain 临时失败时，本次进程复用同一个内存 UUID，不能每个请求重新生成。

`APIClient` 为真实 API 请求统一增加 `X-Device-Id`。不新增语义重复的 `X-Install-Id`。

### 事件 Reporter

`DiscoveryAnalyticsReporter` 是独立 Actor，职责只有队列、持久化和发送：

```text
ViewModel / View action
    -> track(event)
    -> persistent queue
    -> batch request
    -> backend ingestion API
```

约束：

- 单批最多 20 条，低于 20 条时首条事件等待最多 15 秒。
- App 进入后台时尝试 flush，但不阻塞生命周期。
- 成功后只删除服务端确认的当前批次。
- 网络失败、超时和 5xx 保留事件，使用有限指数退避。
- 4xx 合同错误记录简洁 DEBUG 日志并丢弃对应无效批次，避免永久死循环。
- 队列持久化到 Application Support，使用原子写入。
- 最大保留 500 条；超限时淘汰最旧事件。
- `event_id` 在首次入队时生成，重试和重启后保持不变，依赖后端幂等去重。
- Reporter 失败不得改变搜索请求、导航、加载态或错误态。

## 搜索事件语义

### `search_submit`

只在用户明确提交搜索时产生：

- 键盘 Search。
- 点击 Recent Searches。
- 点击 Trending Searches。

输入框防抖请求、分页加载、页面重建和 Retry 不产生 `search_submit`。

上报字段：

```text
event_type       = search_submit
search_term      = trim、折叠空格后的查询词
content_language = 当前内容语言
country_code     = 当前国家
source_scene     = search
occurred_at      = 用户明确提交时刻
```

### `search_result_click`

只在搜索结果页点击短剧卡片时产生，并在导航前入队：

```text
event_type       = search_result_click
series_id        = 被点击短剧 ID
search_term      = 当前已经提交的规范化查询词
content_language = 当前内容语言
country_code     = 当前国家
source_scene     = search
occurred_at      = 点击时刻
```

默认搜索页的榜单卡片没有查询词，因此不得伪造 `search_result_click`。该场景的曝光和点击事件留到后续统一发现事件任务。

## 并发与生命周期

- ViewModel 只调用 Reporter 的异步入队接口，不等待网络结果。
- Reporter 内部只维护一个 flush 任务，禁止每次 track 创建长期独立 Task。
- 同一时刻只允许一个网络批次在发送。
- flush 成功前新进入的事件不能被当前响应误删。
- App 启动后恢复持久化队列；进入 active 且网络可用时允许再次 flush。
- Release 日志不输出搜索词、安装 ID、请求 body 或用户身份。

## 错误处理

- 榜单 DTO 解码失败：Repository 抛出明确网络/解码错误，ViewModel 使用现有错误态。
- 安装 ID 读取失败：使用本进程稳定内存 UUID，不阻断 API。
- 队列文件损坏：隔离损坏文件并从空队列恢复，记录一次 DEBUG 日志。
- 上报失败：保留事件并重试，不向用户弹窗。
- 服务端部分重复：按 `accepted_count + duplicate_count` 视为当前批次已确认。
- 响应数量与发送数量不一致：保留未确认事件并记录 DEBUG 诊断。

## 测试策略

最小测试 Target 覆盖：

1. Rankings 实际 JSON 能解码，`Int64 metric_value` 和嵌套卡片映射正确。
2. Repository 不使用本地排序覆盖 `rank_position`。
3. 安装 UUID 在同一安装内稳定，Keychain 失败时进程内稳定。
4. Reporter 达到 20 条自动 flush，15 秒触发可使用可控时钟测试。
5. Reporter 失败保留、成功删除、重启恢复、event ID 稳定。
6. 防抖搜索不产生日志事件，三种明确提交入口各产生一次 `search_submit`。
7. 搜索结果点击产生一次带 query 和 series ID 的 `search_result_click`。
8. 上报失败不阻塞搜索和导航。

构建至少覆盖小屏、标准屏和大屏设备；本任务不改布局，但必须防止新增状态或错误提示破坏现有页面。

## 联调验收

- Search 三个榜单顺序、排名和热度值与后端 API 一致。
- 空榜保持空态，不使用 Mock 或旧快照。
- 明确提交一次搜索后，`rs_discovery_events` 增加一个 `search_submit`。
- 点击一个搜索结果后，增加一个合法 `search_result_click`。
- 重复发送同一 `event_id` 时后端只保留一条。
- Worker 运行后 `rs_search_term_hourly` 或 `rs_series_metric_hourly` 发生对应变化。
- 后续榜单发布可观察到指标或顺序变化。
- 搜索和导航体验不受上报网络成功或失败影响。

## R4B-2 接口预留

R4B-1 只保留 Reporter 接收通用 `DiscoveryEvent` 的能力。R4B-2 将新增独立 `PlaybackAnalyticsTracker`，由播放器状态和有效观看时长生成 `qualified_play`、`play_complete`；Tracker 不进入 `ShortVideoPlayerEngine` 内部。
