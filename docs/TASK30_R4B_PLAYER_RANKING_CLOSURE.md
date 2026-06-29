# Task30 R4B 播放与榜单联调收口

## 核心决策

- `PlayerCoordinator` 是唯一播放所有权入口。Series 在请求接口前先接管，退出时撤销播放意图并取消异步恢复。
- 播放结束回调同样由 `PlayerCoordinator` 按当前 owner 路由，页面不能直接覆盖共享引擎回调。
- 卡片媒资用于立即播放点击的剧，后端 `/episodes/{id}/play` 负责正式鉴权和媒体合同；真实接口失败不再回落 Mock。
- For You 返回前台时重新声明自己的播放列表，不复用 Series 遗留媒体。
- 动态榜单优先使用真实行为数据；样本不足时由运营发现池补齐，并使用 `editorial_*_baseline` 标明来源。

## 完成内容

- 修复 Home、Search、Rankings 进入 Series 后不自动播放、播放错剧、退出漏音。
- `/play` 在本地 real API 模式补齐 `X-User-Id`，后端 `EPISODE_LOCKED` 改为 HTTP 403。
- 网络层保留后端业务错误码，不再只暴露通用 400。
- Series 预取下一集播放合同和媒体元数据，复用单一 AVPlayer 架构。
- Series 当前集结束后自动播放下一集；最后一集回到首帧等待用户重播，页面释放后迟到回调失效。
- 上报曝光、有效播放、完播、收藏、分享事件，并携带页面来源。
- 新增正式 iOS Test Target，覆盖身份头、播放器所有权、退出释放、For You 回切、错误合同和事件编码。
- 榜单冷启动和低流量维度稳定补齐 12 条真实内容。

## 验证结果

- iOS：9 项新增测试在 iPhone SE（iOS 17）和 iPhone 17 通过；iPhone 17 Pro Max 构建通过。
- 后端：`mvn test` 284 项通过；`mvn package -DskipTests` 通过。
- 真实接口：3 个不同剧集播放接口均返回各自媒体 URL；Home 第二部和 Rankings 第三部均自动播放正确内容。
- 真实事件：`content_impression`、`qualified_play`、`play_complete` 已按正确 series、episode、source_scene 入库。
- 新后端实例：`trending`、`top_searched`、`new_releases` 均返回 12 条。
- 重启后本地并发基线：Home P95 8ms，Rankings P95 119ms，Play P95 84ms；300 次请求无失败。

## 后续边界

- 当前 `X-User-Id: 1` 仅是 dev 联调桥梁，生产必须替换为正式登录令牌。
- 后台管理后续需要提供榜单运营补位、内容上下线和指标审计能力；本轮未提前开发管理端。
