# RelaxShort iOS CC Guide

CC 在本仓库执行任务时，先遵守根目录 `CLAUDE.md` 的通用规则。本文件只记录 iOS 工程差异约束，避免重复维护和浪费 token。

## 执行流程

1. 先读根目录 `AGENTS.md`。
2. 只读取用户当前明确提供的任务说明；不自动读取历史任务文档、计划、交付报告或设计文档。
3. 按任务边界实现，不自行扩大范围。
4. 交付时只写修改文件、一次编译结果、commit 和真实遗留风险。

## iOS 实现规范

- UI Model 与 API DTO 分离。Repository 负责 DTO → UI Model 映射。
- ViewModel 不直接解析后端 DTO。
- 网络错误不要吞掉；ViewModel 可降级为空态或 Mock fallback，但必须记录日志。
- 页面入口必须通过 `DependencyContainer` 或上层显式注入 Repository，禁止在真实 API 已接入的 Home、For You、Search、Search Default、Rankings、Series Player 入口继续硬编码 Mock Repository。
- 不要在日志里输出 token、支付凭据、用户隐私信息。
- 不创建交付报告、计划、设计文档或 Notion 记录，除非用户明确要求。
- 当前本机 `xcodebuild` 已可用；普通 Swift/Xcode 改动完成后只跑一次 `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build`。用户未要求时，不跑测试、模拟器交互、网络 smoke 或截图。
