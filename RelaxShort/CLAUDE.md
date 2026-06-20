# RelaxShort iOS CC Guide

CC 在本仓库执行任务时遵守以下规则。

## 执行流程

1. 先读根目录总控记忆：`/Users/ethan/myspance/relaxshort/AGENTS.md`。
2. 再读本仓库 `AGENTS.md`。
3. 再读任务文档，例如 `docs/CC_TASK13_IOS_REAL_API_PHASE1.md`。
4. 按任务边界实现，不自行扩大范围。
5. 交付时写明修改文件、验证命令、测试结果、未完成事项。

## ECC 使用

如果 ECC 在当前 CC 环境可用，优先使用。如果 ECC 不可用，需要在交付报告里说明不可用原因，并用手工审计替代。

## iOS 实现规范

- UI Model 与 API DTO 分离。
- Repository 负责 DTO → UI Model 映射。
- ViewModel 不直接解析后端 DTO。
- 网络错误不要吞掉；ViewModel 可降级为空态或 Mock fallback，但必须记录日志。
- 不要在主线程执行重型 JSON 或图片处理。
- 不要在日志里输出 token、支付凭据、用户隐私信息。
