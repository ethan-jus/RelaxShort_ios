# RelaxShort iOS CC Guide

CC 在本仓库执行任务时遵守以下规则。

## 执行流程

1. 先读根目录 `AGENTS.md`。
2. 再读当前任务文档；历史 Task13 文档只作为已完成背景。
3. 按任务边界实现，不自行扩大范围。
4. 交付时写明修改文件、验证命令、结果、未完成事项。

## iOS 实现规范

- UI Model 与 API DTO 分离。Repository 负责 DTO → UI Model 映射。
- ViewModel 不直接解析后端 DTO。
- 网络错误不要吞掉；ViewModel 可降级为空态或 Mock fallback，但必须记录日志。
- 页面入口必须通过 `DependencyContainer` 或上层显式注入 Repository，禁止在真实 API 已接入的 Home、For You、Search、Search Default、Rankings、Series Player 入口继续硬编码 Mock Repository。
- 不要在日志里输出 token、支付凭据、用户隐私信息。
- 交付报告不能保留已修复问题作为未完成项；未完成项只写真实剩余风险。
- 当前本机 `xcodebuild` 已可用；涉及 Swift/Xcode 工程改动必须跑 `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build` 或说明无法运行的真实原因。
