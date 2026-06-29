# Task31 My List 与观看进度真实联调设计

## 目标

Task31 将 My List 从演示页面改成可上线的真实用户功能，并建立播放器、收藏、
观看历史之间唯一且一致的数据链路：

- 用户在 For You 或 Series 页面点击书签后，真实写入后端。
- My List 的 Following 展示真实收藏，History 展示真实观看历史。
- 播放器周期保存进度，退出、暂停、切集和播放完成时立即补报。
- 再次进入同一集时使用后端 `resume_time` 续播。
- My List 不再读取 `MockData`，推荐区使用真实动态榜单。

## 产品决策

### 收藏是唯一的 My List 状态

iOS UI 保留用户熟悉的 `Following` 文案，但其业务含义统一为 bookmark：

- 写入：`POST /api/v2/series/{seriesId}/bookmark`
- 删除：`DELETE /api/v2/series/{seriesId}/bookmark`
- 列表：`GET /api/v2/users/me/bookmarks`

本任务不使用 `/follow` 和 `rs_user_follows`。后端暂时保留这些旧接口和表，避免
破坏其他客户端兼容性，但 iOS 不同时维护 follow/bookmark 两套重复状态。

### 页面范围

只实现两个页签：

- Following：真实收藏列表。
- History：真实观看历史。

不实现 DramaBox 的 Reminder Set。右上角编辑按钮支持多选移除收藏；History 本轮
只浏览和续播，不提供批量删除。

### 推荐区

底部标题为 `Most Trending`，数据来自动态榜单
`GET /api/v2/rankings?type=trending`，不复制静态测试卡片。

## 后端合同

### 收藏状态批量查询

新增：

`GET /api/v2/users/me/bookmark-status?series_ids=1,2,3`

限制一次 50 个 ID，返回：

```json
{
  "bookmarked_series_ids": [1, 3]
}
```

For You 每次加载一页后批量查询，Series 页面查询当前一部。禁止逐卡片 N+1 请求，
禁止把用户状态写进可共享缓存的 Feed 快照。

### 观看进度

沿用 `POST /api/v2/watch-progress`，补充：

```json
{
  "series_id": 20250312000001,
  "episode_id": 202503120000011,
  "progress_seconds": 18,
  "total_duration": 107,
  "completed": false,
  "play_session_id": "UUID",
  "final_report": false,
  "source_type": "mp4",
  "quality": "auto",
  "content_language": "en"
}
```

规则：

- 普通 heartbeat 只 upsert `rs_watch_histories`。
- `final_report=true` 或 `completed=true` 时，额外形成一条
  `rs_episode_watch_records` 会话记录。
- `play_session_id` 在单次播放会话内稳定，服务端唯一键保证最终补报幂等。
- 服务端验证 episode 存在且属于 series，拒绝污染历史的数据。
- `progress_seconds` 截断到 `[0, total_duration]`。
- 客户端同一会话串行发送，避免旧进度覆盖新进度。

### 历史响应

`GET /api/v2/watch-history` 的 item 增加 `episode_number`，继续返回
`episode_id`、`resume_time`、`progress_percent`、`completed`、`card`。
页面由真实字段显示 `EP.current / EP.total`，不通过数组下标猜集数。

## iOS 架构

### Repository

新增 `RealFavoritesRepository`，负责：

- 收藏列表、观看历史游标分页。
- 批量查询收藏状态。
- 收藏和取消收藏。
- 上报观看进度。

`FavoritesRepositoryProtocol` 使用领域分页结果，不再使用 `page: Int` 和裸数组。
真实 API 模式由 `DependencyContainer` 注入真实仓库；Mock 只允许 Preview 和显式
测试使用。

### 收藏状态

新增 `BookmarkStore`（`@MainActor ObservableObject`）作为当前 App 会话的收藏状态
单一来源：

- 内部保存 `Set<String>`。
- 后端查询后合并状态。
- 用户点击时先进行乐观更新，失败则回滚并显示错误。
- For You、Series、My List 共享同一个 Store，避免页面间状态不一致。

Analytics 的 bookmark 事件只在后端操作成功后发送。

### 进度上报

新增 `WatchProgressReporter` actor：

- 每 15 秒最多发送一次 heartbeat。
- 进度增长不足 3 秒不重复发送。
- 暂停、切集、页面退出、App 进入后台时发送 final report。
- 播放完成强制发送 completed final report。
- Reporter 串行化同一会话请求；退出任务可取消，但最终补报使用独立短任务。

播放器 View 只提供当前 series、episode、progress 和生命周期信号，不自行拼接
网络请求。

### My List 页面

`FavoritesViewModel` 分别维护收藏、历史和推荐的加载/分页/错误状态。页面结构：

- 顶部 Following / History，选中态使用 `DB.logoRed`。
- Following 行：2:3 封面、标题、动态标签、`EP.current / EP.total`、细进度线。
- History 行：同一尺寸合同，点击从 `episode_id + resume_time` 进入 Series。
- 编辑态：左侧选择圆圈、顶部 Choose/Cancel、底部 Remove；移除逐项调用幂等
  DELETE，部分失败保留失败项并显示错误。
- Most Trending：三列真实榜单卡片。

所有海报圆角统一使用 `DB.posterRadius`，布局验证 iPhone SE、iPhone 17、
iPhone 17 Pro Max。不得通过设备型号分支或堆叠偏移修布局。

## 明确禁止

- Real API 模式回退 `MockData`。
- 把 Following 同时写入 follow 和 bookmark。
- 每张 Feed 卡片单独请求收藏状态。
- 每个播放器进度 tick 写一条 episode watch record。
- 在共享 Feed/Ranking 缓存响应里混入用户收藏状态。
- 为本任务删除后端旧 follow 表或接口。

## 验收

- 任意入口收藏后，My List 立即可见；取消后所有已打开页面状态同步。
- 播放 20 秒退出，`rs_watch_histories` 有准确进度且退出后无播放声音。
- 重进同一集自动播放并从后端续播位置开始。
- 完播仅产生一条同 session 的最终观看记录。
- Following、History、Most Trending 均来自真实接口，关闭网络有明确错误和 Retry。
- 收藏和历史分页无重复、无丢项，空态不展示 Mock 内容。
- 后端测试、Flyway 空库迁移、iOS 单测和三类屏幕构建通过。
