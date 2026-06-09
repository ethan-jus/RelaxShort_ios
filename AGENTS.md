# RelaxShort Codex Rules

本文件约束 Codex。给 Claude Code 的长期规范写在 `CLAUDE.md`；临时执行计划写在 `docs/plans/`。

要求 Claude Code 干活时，必须明确告诉它读取：

1. `CLAUDE.md`
2. 本次任务对应的 `docs/plans/*.md`

`docs/plans/` 是执行计划目录，计划完成后不一定需要提交；如果计划只是临时协作材料，可以留在本地或删除。

## 工作量与 token 使用

1. 小改动优先由 Codex 直接完成、验证和提交，不要为了交给 Claude Code 再写长计划。
2. 只有改动范围大、风险高、跨多个模块、需要长时间执行或需要交接时，才写 `docs/plans/*.md` 给 Claude Code 执行。
3. 如果写计划消耗的 token 已经接近直接修复的成本，优先直接修复。
4. 发现 Claude Code 的修改不完整时，先判断能否小范围补齐；能补齐就直接补齐，不能补齐再输出明确的返工计划。
5. 不要反复纠结未跟踪的临时协作文档；通过 `.gitignore` 管理不提交的计划文件，真正有长期价值的规范文件再提交。

## 播放器任务

处理 For You、Series、PlayerKit、AVPlayer、缓存、字幕、弱网恢复相关任务时，必须遵守以下规则。

1. PlayerKit 必须是独立组件，核心类型放在 `RelaxShort/PlayerKit/`，不得塞进业务 View 文件。
2. For You 和 Series 的主播放路径必须使用同一个 `ShortVideoPlayerEngine`。
3. 不得用“属性已就绪但业务未调用”“代码合并到旧文件里”“pbxproj 不稳定所以未加入 target”作为完成理由。
4. 首帧状态必须来自真实播放器/layer 状态，例如 `AVPlayerLayer.isReadyForDisplay`。禁止用固定延迟模拟首帧。
5. MP4 边播边存必须保证 `AVAssetResourceLoaderDelegate` 生命周期被 engine 或 slot 强持有。
6. 弱网恢复必须支持 observer 清理、failed item 重建、断点 seek、按播放意图续播。
7. 快速滑动必须取消旧任务，generation token 只用于防止旧结果落地。
8. 完成播放器任务前，必须运行计划文档中的 grep 验收命令和 xcodebuild。

当前播放器返工计划：

- `docs/plans/2026-06-09-playerkit-rework-execution-plan.md`
