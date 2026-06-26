# Task29-A R2 中文返工任务书：Anime tab 轮播、圆角、推荐列表对标修复

> 执行者：CC  
> 总控/验收：Codex  
> 仓库：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`  
> 前置：Task29-A 已完成首版，但用户反馈轮播图尺寸、封面圆角、More Recommended UI 与 Dramabox 参考图不一致。

## 0. 本轮目标

只修 Home 的 Anime tab。

不要改：

- Popular / New / Rankings / Categories
- VIP / Original+
- For You / 播放器 / Profile / My List
- 后端代码
- 底部导航

## 1. 参考图

参考图路径：

`/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Anime.JPG`

CC 不要自行识图，按下面文字要求实现。

## 2. 当前首版问题

当前 `HomeView.swift` 里的 Anime 实现存在这些偏差：

1. Hero 只有单张图，不是轮播。
2. Hero 显示了标题和集数，参考图只需要底部标题。
3. Hero 尺寸不对，当前过扁/不够像参考图。
4. Hero 没有参考图右下角的轮播指示器。
5. 多处封面圆角写死 `6`，绕过了全局 `DB.posterRadius = 2`。
6. `More Recommended` 每行用了深色圆角卡片背景和右侧 chevron，参考图没有这种卡片壳。
7. `More Recommended` 左侧封面太小，文字区和封面比例不像参考图。
8. `More Recommended` 缺少参考图同类的动态 flag 角标和封面底部播放量叠层。

## 3. Hero 轮播修复要求

### 3.1 数据

- Hero 使用 3 条数据：
  - `Array(dramas.prefix(3))`
  - 如果不足 3 条，就用已有数据循环补足到最多 3 个展示位。
- 不要使用 MockData。

### 3.2 自动轮播

- 每 5 秒自动切换一次。
- 只在 Anime tab 页面生命周期内运行。
- 使用 SwiftUI `Timer.publish(every: 5, on: .main, in: .common).autoconnect()` 或等价方式。
- 组件消失时不要保留后台任务。

### 3.3 UI 尺寸

参考图中 Hero 是页面顶部的横向大图：

- 左右边距：`DT.Space.pageH` 或 16。
- 宽度：`containerW - 32`。
- 高度：建议 `min(max(width * 0.54, 168), 214)`。
  - 不要用太扁的 2.2:1。
  - 大概接近 16:9 但略高，贴近参考图。
- 圆角：使用 `DB.posterRadius`，不要写死 6。

### 3.4 内容

- Hero 只显示底部标题。
- 不显示集数、不显示分类、不显示简介。
- 标题位于左下，白色，18pt semibold/bold，1 行，超长截断。
- 底部加轻微黑色渐变遮罩，保证标题可读。

### 3.5 指示器

参考图右下角是很小的横向点/短条指示器。

实现要求：

- 放在 Hero 右下角。
- 3 个指示器。
- 当前项：白色/浅灰短胶囊，宽 14，高 3。
- 非当前项：白色 35% 透明度小点或短条，宽 5，高 3。
- 间距 4。
- 不要使用系统 PageTabView 的默认大圆点。

建议组件名：

- `AnimeHeroCarousel`
- `AnimeHeroIndicator`

## 4. Weekly Featured 修复要求

当前结构基本对，但细节要修：

- Section title `Weekly Featured` 字号可以 18 semibold，左边距 16。
- 横滑海报宽度按屏幕自适应：
  - `cardW = min(max(containerW * 0.29, 112), 132)`
  - 高度 `cardW * 1.5`
- 海报圆角统一 `DB.posterRadius`。
- 不要再 `.clipShape(RoundedRectangle(cornerRadius: 6))`。
- 标题 13pt，1 行。
- 分类/标签 12pt 灰色，1 行。
- 如果有播放量，可以在封面右下角叠加小播放量；没有则不硬造。

## 5. More Recommended 修复要求

参考图不是“深色卡片列表”，而是黑底上的无壳图文行。

### 5.1 行布局

- 删除每行的 `.background(DB.panel).cornerRadius(8)`。
- 删除右侧 `chevron.right`。
- 行间距：16-18。
- 横向边距：16。
- 左侧封面更大：
  - 宽度：`min(max(containerW * 0.28, 104), 122)`
  - 高度：`coverW * 1.42`
  - 圆角：`DB.posterRadius`
- 右侧文字区：
  - 标题 16pt semibold，2 行。
  - 简介 13pt regular，灰色，2-3 行。
  - 底部 meta 行：分类/标签、`Anime`、集数。
  - meta 行字体 12pt，灰色。

### 5.2 封面叠层

参考图左侧封面有两个典型叠层。RelaxShort 不照搬 `Dubbed` 文案，但要保留同类动态 flag 能力：

- 顶部右侧动态 flag 角标。
- 底部右侧播放量，例如 `4.3M`。

实现要求：

- 不要静态写死 `Dubbed`。RelaxShort 当前不会有 Dubbed 类型剧。
- 当前后端/iOS 模型还没有通用运营 flag 字段，本轮先集中封装一个 helper，例如 `displayFlag(for:) -> String?`。
- `displayFlag(for:)` 当前只返回测试占位 `Test`，用于验证 UI 位置和样式。
- `Test` 只能在这个 helper 内出现一次，不能散落到多个 View。
- 后续后端补真实字段后，iOS 应从剧集配置动态展示，例如 `AI`、`New`、`Exclusive` 或后台自定义 flag。
- 播放量使用 `drama.formattedViewCount`。
- 播放量前用小三角播放 icon 或 SF Symbol `play.fill`，白色，底部右侧。
- 角标颜色使用低饱和紫色：
  - `Color(red: 0.52, green: 0.38, blue: 0.82)`
- 角标圆角使用 2，不要大胶囊。

建议组件名：

- `AnimeRecommendedRow`
- `AnimePosterOverlay`

## 6. 圆角统一要求

必须修掉 Anime tab 内所有写死的封面圆角：

```bash
rg -n "cornerRadius: 6|cornerRadius\\(6\\)|RoundedRectangle\\(cornerRadius: 6" RelaxShort/Views/Home/HomeView.swift
```

预期：Anime 相关代码无结果。

所有短剧封面统一使用：

```swift
DB.posterRadius
```

如果某些非封面容器需要圆角，必须说明为什么，不要混到封面圆角里。

## 7. 建议实现边界

优先仍改：

- `RelaxShort/Views/Home/HomeView.swift`
- `docs/TASK29_A_ANIME_DELIVERY_REPORT.md`

如果 `HomeView.swift` 继续变大，可以新增一个文件：

- `RelaxShort/Views/Home/AnimeTabView.swift`

建议：本轮可以把 Anime 专用小组件移到 `AnimeTabView.swift`，减少 `HomeView.swift` 继续膨胀。但不要做大规模重构。

## 8. 验证

必须执行：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
rg -n "cornerRadius: 6|cornerRadius\\(6\\)|RoundedRectangle\\(cornerRadius: 6" RelaxShort/Views/Home
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

预期：

- `git diff --check` 通过。
- grep 不命中 Anime 封面圆角 6。
- `BUILD SUCCEEDED`。

## 9. 交付报告更新

更新：

`docs/TASK29_A_ANIME_DELIVERY_REPORT.md`

必须写：

- Hero 轮播：3 条数据、5 秒切换、指示器样式。
- Weekly Featured：尺寸和圆角修复。
- More Recommended：无壳列表、封面叠层、播放量、动态 flag 角标。
- 验证命令和结果。
- 未完成/gap：动态 flag 当前用 `Test` 占位，后端暂无真实运营 flag 字段；后续应接入后台配置字段。
