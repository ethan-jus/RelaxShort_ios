# RelaxShort Claude Code Rules

本文件是 Claude Code 在本仓库执行任务时必须读取的长期规范。

## 基本执行规则

1. 开始任何播放器任务前，先读取本文件，再读取用户指定的 `docs/plans/*.md`。
2. 不要只追求 build 通过；必须满足计划文档里的 grep 验收命令。
3. 不要用“已准备属性但业务未调用”“保留 hook”“后续专项”“pbxproj 不稳定”作为完成理由。
4. 执行结束必须说明：
   - 改了哪些文件。
   - 哪些验收命令已运行。
   - 哪些命令仍有命中以及原因。
   - 是否还有未跟踪文件。
5. 如果某项做不到，直接说明阻塞点和文件位置，不要标记完成。

## 播放器任务规则

1. `RelaxShort/PlayerKit/` 是播放器组件目录。播放器核心类型只能放在这里。
2. For You 和 Series 的主播放路径必须使用 `ShortVideoPlayerEngine`。
3. 业务层只做数据映射和调用 engine API，不直接创建 `AVPlayer(url:)`。
4. `VideoPlayerView.swift` 不得承载播放器核心逻辑。
5. `ShortVideoPlayerView` 不得在 body 内部创建新的 `ShortVideoPlayerEngine()`。
6. 首帧 ready 必须来自 `AVPlayerLayer.isReadyForDisplay` 或等价真实播放器状态，禁止用固定延迟模拟。
7. MP4 缓存必须保证 `AVAssetResourceLoaderDelegate` 被 slot 或 engine 强持有。
8. 弱网恢复必须支持 observer detach、failed item 重建、断点 seek、按播放意图续播。
9. 快速滑动必须取消旧 prepare/preload/subtitle/cache warming 任务，generation token 不能代替取消。

## 推荐使用的能力

播放器相关任务优先按这个顺序执行：

1. SwiftUI/AVFoundation 审查：检查 `@StateObject`、`@ObservedObject`、UIViewRepresentable、AVPlayerLayer 生命周期。
2. 系统化调试：先用 grep 找真实调用路径，再改代码。
3. xcodebuild 验证：每轮提交前必须跑 iPhone 15 simulator build。
4. 手动验收说明：For You 首屏、滑动、暂停、Series 进入播放、弱网恢复、缓存命中。

## 提交前硬验收

播放器任务完成前至少运行：

```bash
git status --short
git ls-files | rg '^RelaxShort/PlayerKit/'
rg -n 'session\\.pool|session\\.controller|VideoPlayerView\\(' RelaxShort/Views/RecommendPage/RecommendView.swift
rg -n 'PlayerPool|PlayerController|VideoPlayerView\\(' RelaxShort/Views/RecommendPage/SeriesPlayerView.swift
rg -n 'ShortVideoPlayerEngine\\(\\)' RelaxShort/Views/RecommendPage
rg -n 'logTTFF\\(0\\)|logRecovery\\(ms: 0\\)' RelaxShort/PlayerKit RelaxShort/Views/RecommendPage
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' build
```

期望：

- 主业务路径不出现旧播放器。
- 不出现 body 内部乱建 engine。
- 不出现固定 0 指标。
- 构建通过。
