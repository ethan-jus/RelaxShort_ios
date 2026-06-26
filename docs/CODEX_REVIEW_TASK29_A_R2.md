# Codex Review — Task29-A R2 Anime tab

结论：不通过，进入 R3 小范围返工。

## P1：`AnimeTabView.swift` 已创建但未接入 target，实际 App 仍使用 `HomeView.swift` 内联实现

证据：

- `RelaxShort/Views/Home/AnimeTabView.swift` 是未跟踪新文件。
- `RelaxShort.xcodeproj/project.pbxproj` 没有 `AnimeTabView.swift` source entry。
- `HomeView.swift` 内仍有完整 Anime 实现。
- 交付报告写“AnimeTabView.swift 已创建但未加入 Xcode target（内联在 HomeView）”，这不是可接受交付状态。

要求：

- 二选一：
  - A. 删除 `AnimeTabView.swift`，保留 `HomeView.swift` 内联实现。
  - B. 正式接入 `AnimeTabView.swift` 到 Xcode target，并让 `HomeView.animeTabContent` 调用 `AnimeTabView`，删除 `HomeView.swift` 里的重复 Anime 子组件。
- 推荐 B，因为 `HomeView.swift` 已经偏大，Anime 专用组件应该拆出去。

## P1：轮播指示器还不像参考图

当前实现：

- `HomeView.swift` 里 `.overlay(alignment: .bottomTrailing)` 放了 3 个高亮很明显的白色 capsule。
- 指示器在图片右下角独立浮着，和参考图的底部标题/指示器同一底栏感觉不一致。

参考图要求：

- 指示器应非常低调，位于底部标题同一条视觉区域的右侧。
- 当前项是短横线，非当前项更短且透明度更低。
- 整组指示器不要太亮，避免比标题更抢眼。

建议实现：

- Hero 底部 overlay 改为 `HStack`：
  - 左侧标题 `Text`
  - `Spacer`
  - 右侧 `AnimeHeroIndicator`
- indicator 样式：
  - 当前项：宽 14，高 3，`Color.white.opacity(0.72)`
  - 非当前项：宽 5，高 3，`Color.white.opacity(0.18)`
  - spacing 4
- 整个底部 HStack padding：left/right 12，bottom 10。
- 不要把 indicator 作为单独 `.overlay(alignment: .bottomTrailing)` 再额外 padding。

## P1：`Test` 动态 flag 占位出现重复风险

任务书要求 `Test` 只在集中 helper 中出现一次。

当前因为有两个实现文件：

- `HomeView.swift` 有 `displayFlag(for:) -> "Test"`
- `AnimeTabView.swift` 也有 `displayFlag(for:) -> "Test"`

要求：

- 完成 P1 文件收口后，确保 `rg -n '"Test"|displayFlag' RelaxShort/Views/Home` 只命中一个真实 helper。
- helper 后续要改为读取后端/后台配置字段，不允许在多个 View 中散落静态 flag。

## P2：Hero timer 生命周期需要随组件收口一起处理

当前 timer 挂在 `HomeView.swift` 内部轮播 view 上。由于 Home 的 `TabView` 可能缓存多个 page，后续最好让 timer 属于 `AnimeHeroCarousel` 子组件，而不是 Home 主视图状态。

要求：

- 若采用推荐 B，把 `@State private var idx` 和 timer 留在 `AnimeHeroCarousel` 内。
- `HomeView` 不保存 Anime hero index。

## P2：报告需要与实际文件一致

当前报告承认 `AnimeTabView.swift` 未加入 target。R3 后必须更新：

- 若删除文件，报告不要再提 `AnimeTabView.swift`。
- 若接入文件，报告写清楚它已加入 target，`HomeView` 只负责调用。

## R3 验证命令

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
rg -n "cornerRadius: 6|cornerRadius\\(6\\)|RoundedRectangle\\(cornerRadius: 6" RelaxShort/Views/Home
rg -n '"Test"|displayFlag' RelaxShort/Views/Home
rg -n "AnimeTabView.swift|AnimeTabView" RelaxShort.xcodeproj/project.pbxproj RelaxShort/Views/Home
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

预期：

- `cornerRadius: 6` 无命中。
- `Test` 只在一个 helper 中出现。
- `AnimeTabView.swift` 状态明确：要么已接入 target，要么文件不存在。
- `BUILD SUCCEEDED`。
