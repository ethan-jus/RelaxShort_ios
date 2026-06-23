# CC Task26 R3 UI Fixes — User Smoke + Codex Review

> 执行项目：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`
>
> 任务性质：Task26 R2 后的小范围 UI 返工
>
> 重要：这轮只修 UI 和状态回退，不改播放器内核，不做新功能，不碰 Home/Search/My List/Profile/VIP/支付/广告。

## 0. 必读

先读：

- `docs/CC_TASK26_FOR_YOU_PLAYER_POLISH.md`
- `docs/CC_TASK26_R2_FIXES.md`
- `docs/TASK26_DELIVERY_REPORT.md`

当前 R2 已经 `xcodebuild` 通过，R3 不要重写 R2 的切集架构，只补下面的问题。

## 1. 修 For You 暂停播放按钮双重外圈

### 问题

用户看到暂停态播放按钮有两个背景/阴影圈，显得很脏。大概率是：

- `RecommendView` 自己加了中央 play button；
- `ShortVideoPlayerView` 在 `pausedByUser` 时也会显示内置 play button。

### 修复要求

修改 `RelaxShort/Views/RecommendPage/RecommendView.swift`。

二选一，推荐方案 A：

方案 A：

- 删除或禁用 `RecommendView` 里 Task26 新增的中央播放按钮。
- 复用 `ShortVideoPlayerView` 内置的暂停播放按钮。
- 确认暂停态只出现一个半透明圆形播放按钮。

方案 B：

- 保留 `RecommendView` 的按钮，但必须让 `ShortVideoPlayerView` 不再同时显示内置按钮。这个方案涉及 PlayerKit 公共组件，风险更高，不推荐。

验收：

- 暂停时只看到一个 play 圆按钮。
- 没有大的外圈/双层黑影。
- 点击按钮或视频区域能恢复播放。

## 2. 修简介 `... more` 逻辑

### 问题

当前 `synopsisView` 对未展开状态无条件加 `... more`，即使简介两行内能完整显示，也会多出很奇怪的 `... more`。

### 修复要求

修改 `RelaxShort/Views/RecommendPage/RecommendView.swift`：

- 只有简介文本确实被截断时，才显示 `... more`。
- 如果简介两行内已经完整显示，不显示省略号和 `more`。
- 不要用非常短的固定阈值导致正常短简介也被误判。

可接受实现：

```swift
private func shouldShowMore(for text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).count > 90
}
```

然后：

```swift
if isExpanded {
    fullSynopsis
} else if shouldShowMore(for: text) {
    truncatedSynopsis + Text("... more")
} else {
    fullSynopsisWithoutMore
}
```

更好的实现可以基于实际宽度估算，但不要引入复杂测量系统。

验收：

- 短简介不显示 `... more`。
- 长简介仍显示 `... more`，点击可展开，展开后显示 `less` 或可收起逻辑保持可用。

## 3. 收紧 For You 文案区和 Watch Full Series 宽度

### 问题

标题/简介/`Watch Full Series` 按钮太靠近右侧操作栏，视觉上拥挤。

### 修复要求

修改 `RecommendView.pageBottomOverlay`：

- 增加文案区和右侧栏之间的间距。
- 文案区和 `Watch Full Series` 按钮宽度一起收紧。
- 不要让按钮贴到右侧栏。
- 在不同宽度屏幕上使用响应式计算，不要写死只适配 iPhone 17。

推荐计算方式：

```swift
let horizontalPadding: CGFloat = 16
let actionRailWidth: CGFloat = 50
let actionRailGap = max(18, geo.size.width * 0.055)
let maxContentWidth = geo.size.width - horizontalPadding * 2 - actionRailWidth - actionRailGap
let contentWidth = min(maxContentWidth, geo.size.width * 0.74)
```

注意：

- iPhone mini 上 `contentWidth` 不能太小导致标题/按钮难看。
- iPhone 17 Pro Max 上按钮不要无限变宽，可加上限比例。

验收：

- 标题、简介、按钮和右侧栏之间有明显呼吸空间。
- `Watch Full Series` 按钮宽度和文字区一致。
- iPhone mini / iPhone 17 / Pro Max 都不遮挡、不溢出。

## 4. 全屏 UI 必须响应不同屏幕

### 要求

这轮涉及的所有数值都要考虑：

- iPhone mini / 小屏宽度。
- iPhone 17。
- iPhone 17 Pro Max / 大屏宽度。
- safe area bottom。

不要写死只在一个模拟器好看的值。

具体要求：

- For You 底部信息区使用 `GeometryProxy` 和 safe area 计算。
- 文案区宽度用比例 + min/max 约束。
- CTA 按钮高度可以固定，但宽度必须响应。
- 底部 tab bar 高度和 bottom inset 要参与整体避让。
- 文字行数必须限制，不能盖住进度条或 tab bar。

## 5. 调整底部导航栏高度

### 问题

用户感觉底部 tab bar 高度太低、收得太紧。

### 当前位置

`RelaxShort/Views/Components/DramaBoxBottomTabBar.swift`

当前：

- `.padding(.top, 8)`
- 每个 tab `.frame(height: 35)`
- `bottomInset` 参数未真正用于布局。

### 修复要求

调整底部导航栏：

- 使用 `bottomInset`。
- 增加整体高度，让图标/文字有更合理的垂直空间。
- For You 透明模式和普通黑底模式都要正常。
- 不能让底部 tab bar 挡住 For You 进度条和 CTA。

推荐实现方向：

```swift
.padding(.top, 10)
.padding(.bottom, max(8, bottomInset))
```

单个 tab：

```swift
VStack(spacing: 4) { ... }
    .frame(maxWidth: .infinity)
    .frame(height: 44)
```

可根据实测微调：

- icon 18-20pt
- title 11-12pt
- tab content height 42-46pt
- bottom padding `max(8, bottomInset)`

同时回到 `RecommendView.pageBottomOverlay`，把 `tabBarAvoidance` 改成和 tab bar 新高度匹配的响应式值，例如：

```swift
let tabBarAvoidance = geo.safeAreaInsets.bottom + 70
```

不要让 CTA 和进度条压进 tab bar。

## 6. 修 Series Player 切集失败/锁定时状态回退

### 问题

Codex R2 review 发现：竖向拖动切集时，代码先改 `currentEpisode`，再触发 `switchToEpisode(newValue)`。如果目标集锁定或 play asset 失败，UI 可能显示 EP2，但播放器还在 EP1。

### 修复要求

修改 `SeriesPlayerView.swift`：

- 不要在拖动结束时直接提交 `currentEpisode = target`。
- 改为计算 `targetEpisode`，调用安全切集方法。
- 只有 `ensurePlayAsset` 成功并 `engine.prepare/play` 后，才更新 `currentEpisode`。
- 如果目标集锁定，保持当前集不变，只弹 unlock sheet。
- 如果目标集 play asset 失败，保持当前集不变，只记录日志。

推荐改法：

```swift
private func requestEpisodeSwitch(_ target: Int) {
    guard target != currentEpisode else { return }
    switchToEpisode(target)
}
```

拖动结束：

```swift
let oldEpisode = currentEpisode
var targetEpisode = oldEpisode
if value.translation.height < -80 || velocity < -300 {
    targetEpisode = min(oldEpisode + 1, totalEpisodes)
} else if value.translation.height > 80 || velocity > 300 {
    targetEpisode = max(oldEpisode - 1, 1)
}
dragOffset = 0
if targetEpisode != oldEpisode {
    requestEpisodeSwitch(targetEpisode)
}
```

并移除或谨慎处理 `.onChange(of: currentEpisode) { switchToEpisode(newValue) }`，避免 `switchToEpisode` 内部设置 `currentEpisode` 后再次触发自己。

验收：

- 锁定集：当前 EP 文案不跳错，弹 unlock。
- 拉源失败：当前 EP 不变。
- 成功切集：当前 EP 更新，engine item id 对应目标集。

## 7. 清理 project.pbxproj 缩进

R2 还有一处 `project.pbxproj` 缩进被破坏，虽然 build 通过，但提交前要修正。只修新增 `PlayerOptionSheets.swift` 附近的缩进，不要重排整个工程文件。

## 8. 更新交付报告

更新 `docs/TASK26_DELIVERY_REPORT.md`，增加 R3 段落：

- 播放按钮双外圈修复。
- `... more` 条件显示。
- For You 文案区宽度/右侧栏间距响应式调整。
- 底部 tab bar 高度和 safe area 调整。
- Series 切集失败/锁定回退。
- `xcodebuild` 结果。

## 9. 验证

必须运行：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
git diff --check
```

建议补跑不同模拟器构建，至少不要求安装运行：

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

如果本机没有该模拟器，交付报告里如实写“未安装该 destination”，不要写已验证。

## 10. 不要做

- 不要修播放器底层问题。
- 不要改 PlayerKit 内核。
- 不要处理支付/下载/广告真实逻辑。
- 不要重做整页设计。
- 不要改后端。
