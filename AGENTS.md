# RelaxShort iOS Agent Instructions

本文件记录 iOS `ios/v1.0.0` 新会话必须知道、且不能靠代码一眼发现的事实。

## 当前进度

- Task13、Task15 已合并到 `main`，iOS 不再是纯 Mock 项目。
- 已完成 Phase 1/2 真实 API 闭环：app init → For You 推荐流 → Home/Search/Ranking/Categories → 剧集列表 → 播放地址。
- Task15 后已修正主要页面入口注入：Home、For You、Search、Search Default、Rankings、Series Player 必须按 `use_real_api` 走 Mock/Real 对应 Repository。
- Mock/Real 切换通过 `UserDefaults.standard.bool("use_real_api")` 控制，默认仍是 Mock。
- 后端合同见 `app-server/v2/docs/IOS_API_CONTRACT_V1.md`。

## 当前进度（Task16 更新）

- Task16 R4：Search 真实搜索分页已实现（nextCursor/hasMore/isLoadingMore/loadMoreIfNeeded），Search Default 支持真实数据源，Ranking 通过协议 `fetchRankings(type:)` 调后端（popular/trending/new）。
- Categories 最终实现：Home Categories UI 使用 `HomeCategory(id/code/title/localCategory)`。真实模式通过 `/api/v2/categories` 获取后端 `code` 和 `localizedName`，点击后用后端 `code` 调 `/api/v2/categories/{code}/series`；Mock 或 categories API 失败时使用本地 `DramaCategory` fallback，只走本地过滤，不把中文 rawValue 当后端 code。
- 本机 xcodebuild 可用：`xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build` 已通过。
- Mock/Real 切换通过 `UserDefaults.standard.bool("use_real_api")` 控制，默认仍是 Mock。
- 当前 P2 follow-up：`HomeViewModel` 仍通过 `repository as? RealHomeRepository` 调真实分类剧集接口，后续应把 `fetchDramasByCategoryCode(code:)` 收进 `HomeRepositoryProtocol`。

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
