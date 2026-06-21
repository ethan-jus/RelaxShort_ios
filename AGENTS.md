# RelaxShort iOS Agent Instructions

本文件记录 iOS `ios/v1.0.0` 新会话必须知道、且不能靠代码一眼发现的事实。

## 当前进度

- Task13、Task15 已合并到 `main`，iOS 不再是纯 Mock 项目。
- 已完成 Phase 1/2 真实 API 闭环：app init → For You 推荐流 → Home/Search/Ranking/Categories → 剧集列表 → 播放地址。
- Task15 后已修正主要页面入口注入：Home、For You、Search、Search Default、Rankings、Series Player 必须按 `use_real_api` 走 Mock/Real 对应 Repository。
- Mock/Real 切换通过 `UserDefaults.standard.bool("use_real_api")` 控制，默认仍是 Mock。
- 后端合同见 `app-server/v2/docs/IOS_API_CONTRACT_V1.md`。

## 当前目标

- 补齐真实 API 模式下的 cursor 分页、错误态、播放页清晰度/字幕能力。
- 补齐 iOS 分类中文名与后端分类 code 的稳定映射。
- VIP、My List、Profile、金币福利、广告奖励仍主要为 Mock/本地实现，后续任务再接真实 API。

## 架构边界

- UI Model 与 API DTO 分离。Repository 负责 DTO → UI Model 映射。
- ViewModel 不直接解析后端 DTO。
- 网络错误不要吞掉；ViewModel 可降级为空态或 Mock fallback，但必须记录日志。
- Mock/Real 切换通过 `DependencyContainer` + `UserDefaults.standard.bool("use_real_api")` 控制。
- 当前本机 `xcodebuild` 已可用；涉及 Swift/Xcode 工程改动必须跑 `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build` 或说明无法运行的真实原因。

## 禁止事项

- 不把服务器凭据、token、生产 URL 写进仓库。
- 不删除 Mock 数据。
- 不改 UI 大布局。
