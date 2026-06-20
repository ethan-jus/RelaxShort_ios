# RelaxShort iOS Agent Instructions

本文件记录 iOS `ios/v1.0.0` 新会话必须知道、且不能靠代码一眼发现的事实。

## 当前目标

- 将 iOS 从纯 Mock Repository 切换到真实后端 `/api/v2/**`。
- Phase 1 闭环：app init → For You 推荐流 → 剧集列表 → 播放地址。
- 后端合同见 `app-server/v2/docs/IOS_API_CONTRACT_V1.md`。

## 架构边界

- UI Model 与 API DTO 分离。Repository 负责 DTO → UI Model 映射。
- ViewModel 不直接解析后端 DTO。
- 网络错误不要吞掉；ViewModel 可降级为空态或 Mock fallback，但必须记录日志。
- Mock/Real 切换通过 `DependencyContainer` + `UserDefaults.standard.bool("use_real_api")` 控制。

## 禁止事项

- 不把服务器凭据、token、生产 URL 写进仓库。
- 不删除 Mock 数据。
- 不改 UI 大布局。
