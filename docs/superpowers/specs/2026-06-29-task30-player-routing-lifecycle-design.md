# Task30 播放路由与生命周期稳定性设计

## 目标

保证 Home、Search、Rankings、For You 任一入口点击某部短剧后：

- 播放的是所点击短剧，而不是共享引擎残留的上一部视频。
- 有卡片预览媒体时立即自动播放；没有预览媒体时加载成功后自动播放。
- 页面退出后 Series 播放所有权立即释放，不再产生延迟漏音。
- 本地 dev 登录桥能访问 VIP 测试媒资；未授权时保留准确业务错误。
- 推荐流、全屏播放器只能通过 `PlayerCoordinator` 操作共享 Engine。

## 已确认根因

日志证明导航参数正确：点击不同卡片时请求了不同的 series ID，例如
`20250312000005`、`20250312000002`、`20250312000006`。问题不在卡片选择。

真正根因：

1. `/episodes/{id}/play` 未携带 `X-User-Id`，VIP 测试剧第 1 集返回
   `EPISODE_LOCKED` HTTP 400。
2. `SeriesPlayerView` 只有拿到播放源后才调用 `claimSeries`。请求失败时共享 Engine
   仍属于 For You 或保留上一部剧，手动点击播放就会播放旧视频。
3. `onDisappear` 用 Series owner 释放，但失败路径从未建立 Series owner，因此
   `release` guard 不成立，旧视频继续发声。
4. `RecommendView` 直接调用 `engine.playFromSystemResume/pause`，绕过 Coordinator，
   无法确认当前 owner，可能在 Series 页面期间恢复错误播放器。
5. 卡片响应已有 `play_asset`，但 Series 页没有利用它作为首帧播放源，导致额外等待。

## 架构决策

### 播放所有权

`PlayerCoordinator` 是共享 Engine 唯一控制入口。

- `beginSeries(dramaID:)`：进入页面立即取消旧 handoff、设置 Series owner、调用
  `engine.deactivate()`。无论网络成功与否，旧媒体都不能继续播放。
- `claimSeries(...)`：只负责把当前 Series owner 绑定到具体媒体列表并自动播放。
- `pauseForYou()` / `resumeForYou()`：只有 owner 为 `.forYou` 时生效。
- `release(.series)`：取消异步任务、撤销播放意图、暂停并清空 owner。

View 不再直接对共享 Engine 做跨页面生命周期操作。

### 首屏秒开

入口卡片的 `DramaItem.videoURL` 来自后端 `play_asset`，作为可信的预览播放源：

1. Series 页面 task 开始时先 `beginSeries`。
2. 若卡片有合法 http/https URL，立即构造稳定 media ID 并 `claimSeries` 自动播放。
3. 并行加载 episodes 和正式 play asset。
4. 正式媒体与预览媒体相同则保持当前 AVPlayer，不重建。
5. 正式媒体不同才安全替换；请求失败但预览媒体可播时，不回退旧剧、不停止当前预览。

### 权益与错误合同

- iOS `.episodePlay` 与用户/Profile 接口一样，在 real API dev 模式携带本地
  `X-User-Id`；生产仍优先使用 Authorization。
- 后端 `EPISODE_LOCKED` 映射 HTTP 403，不再误报 400 参数错误。
- iOS 网络层解析非 2xx 的 `ApiResponse.error`，保留 `code/message`，供页面区分
  未登录、未解锁、网络失败。
- 真实 API 失败不再回退 Mock episodes。

### 预加载

- 当前集开始后，异步获取下一集播放源并存入 `episodeMediaSources`。
- 使用 `AVURLAsset.load(.isPlayable)` 预热下一集媒体元数据，不切换当前 player。
- 切集优先命中内存播放源，避免再次等待 API。
- 继续复用 PlayerKit 已有 slot/cache，不创建第二套 Engine。

### 排行榜事件

本轮只补足动态排行榜所需的客户端真实事件：

- 卡片可见：`content_impression`，同页面会话对同 series 去重。
- 有效播放达到阈值：`qualified_play`，每次播放会话只报一次。
- 播放完成：`play_complete`。
- 收藏/分享成功：`bookmark` / `share`。

事件继续使用现有持久化队列、批量上报和后端防刷聚合，不由客户端计算排名。

## 验收

- 四类入口均播放所点击 series。
- 进入自动播放，快速进出无旧视频和漏音。
- 同一 Series 重进自动播放，可保留合理断点。
- 预览媒体存在时不等待 play API 才出画面。
- VIP dev 用户 play API 返回 200；无用户返回 403 + `EPISODE_LOCKED`。
- 排行榜事件进入 `rs_discovery_events`，Worker 聚合后 API 排名可变化。
- iPhone SE、iPhone 17、Pro Max 构建通过。
- iOS 单元测试、后端测试、API 并发 smoke 全部通过。
