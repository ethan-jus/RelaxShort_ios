# CC Task26 — For You / Series Player UI Polish + Real API Smoke

> 执行项目：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`
>
> 任务性质：iOS UI 精修 + 播放接口联调
>
> 重要限制：CC 不需要、也不要去识别参考截图。Codex 已经看过截图，下面的视觉要求就是执行标准。

## 0. 先读这些文档

必须先读：

- `AGENTS.md`（如果本仓库存在）
- `docs/superpowers/specs/2026-06-22-task26-for-you-player-design.md`
- `docs/superpowers/plans/2026-06-23-task26-for-you-player-plan.md`
- `docs/TASK24_DELIVERY_REPORT.md`

当前播放链路已经跑通。不要回滚 Task23/Task24 的真实 API 和播放修复。

## 1. 目标

把 iOS 的 `For You` 信息流和 `Series Player` 剧集播放器打磨到接近 DramaBox 的视觉和交互完成度，同时保持真实后端接口播放稳定。

最低验收：

- For You 首条真实视频能播放。
- Series Player 能进入、能切剧集、能使用真实 `/episodes/{episodeId}/play` 播放源。
- 不出现 `about:blank` 进入 AVPlayer。
- 不出现无限 `CoreMediaErrorDomain -12882` recovery。
- 主要 UI 状态完整：正常播放、暂停、长按 2x、标题详情 sheet、分享 sheet、剧集 sheet、速度 sheet、清晰度 sheet、更多 sheet。

## 2. 禁止事项

- 不要重写 `PlayerKit` 内核。
- 不要改 Home/Search/My List/Profile/VIP/StoreKit/AdMob 业务。
- 不要做真实支付、真实广告奖励、真实金币发放。
- 不要把截图文件加入 Xcode 或仓库。
- 不要用截图识别工具做判断；按本文描述实现。
- 不要把无效 URL fallback 成 `about:blank`。
- 不要把本地调试开关或真实凭据写进仓库。

## 3. 重点文件

优先修改：

- `RelaxShort/Views/RecommendPage/RecommendView.swift`
- `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- `RelaxShort/Views/Components/RightActionBar.swift`
- `RelaxShort/Views/RecommendPage/ShareSheet.swift`
- `RelaxShort/Views/RecommendPage/SpeedHUDView.swift`
- `RelaxShort/Views/RecommendPage/VideoPlayerView.swift`
- `RelaxShort/Models/API/PlayerMediaSource.swift`

可新增：

- `RelaxShort/Views/RecommendPage/PlayerOptionSheets.swift`
- 如 `RecommendView.swift` 继续膨胀，可抽 `DramaAboutSheet.swift`

新增 Swift 文件必须加入 `RelaxShort.xcodeproj` app target。

## 4. Codex 看图后的视觉标准

### 4.1 For You 正常播放

实现成这样：

- 全屏竖屏视频铺满背景，底部黑色渐变增强文字可读性。
- 顶部右侧只有白色搜索图标，不要圆形实底。
- 底部信息区在底部 tab bar 上方，不能被 tab bar 或进度条压住。
- 标题：白色粗体，约 22pt，一行省略，右侧有 chevron。
- 标签：灰色半透明圆角小 pill，白字，约 12-13pt；非第一个 tag 可带小 chevron。
- 简介：以 `EP.1 |` 开头，浅灰，两行，末尾 `... more`。
- 右侧操作栏只保留收藏和分享：
  - 收藏：大白色 bookmark 图标，下方播放/收藏数，例如 `190K`。
  - 分享：大白色转发箭头，下方 `Share`。
- `Watch Full Series`：宽按钮，半透明深灰背景，白色粗体文字，高约 52-56pt，圆角 5-8pt。
- 进度条：紧贴底部 tab bar 上方，正常态很细，拖动时变粗并显示预览。

### 4.2 For You 暂停

- 保持标题、标签、简介、右侧栏、CTA 和进度条。
- 中央显示半透明深色圆形播放按钮，直径约 80-90pt，白色 play 三角。
- 点击中央或视频区域恢复播放。

### 4.3 For You 长按 2x

- 长按时进入 2x 播放。
- 隐藏标题、标签、简介、CTA、搜索、右侧栏。
- 只显示顶部偏中位置的 `2.0x >>` 小 HUD。
- 保留底部进度条。
- 松手恢复 1x，并恢复 UI。

### 4.4 标题/简介详情 Sheet

标题或 `more` 打开底部详情 sheet：

- 高度约屏幕 78%。
- 深色面板，顶部圆角，顶部中间有短 drag handle，右上角 X。
- 头部：左侧海报约 92x124；右侧标题、views、rating/rate 行。
- 大 tab：`Synopsis` / `Episodes`，当前 tab 白色并有短下划线。
- Synopsis tab：
  - 展示完整简介。
  - 展示 tag pills。
  - 可保留 Cast 行和 More Like This 三列推荐。
- Episodes tab：
  - 6 列大集数网格。
  - range tabs：`1-30`、`31-60`、`61-67`，按实际集数生成。
  - 锁定集右上角 lock badge。
- `Watch Full Series` 从 sheet 进入 `SeriesPlayerView`，必须传 handoff context。

### 4.5 分享 Sheet

- 背景视频变暗。
- 底部深色 sheet，高约 35% 屏幕，顶部圆角。
- 标题居中 `Share`，右上角 X。
- 奖励 pill：coin icon + `first share gets 10 coins`。
- 横向图标：Instagram、Snapchat、Facebook Messenger、WhatsApp、Copy Link。
- Copy Link 只写入剪贴板，不发金币。

### 4.6 Series Player 顶部/底部控制层

UI 显示态：

- 顶部左侧：返回 chevron + `EP.1`。
- 顶部右侧：`Speed` 按钮 + vertical ellipsis。
- 右侧栏：收藏数、Episodes、Share。
- 底部左侧：标题 + 简介，不要 `Watch Full Series`。
- 底部进度条下方有黑色底栏。
- 黑色底栏左侧：金色 `Join membership` pill。
- 黑色底栏右侧：`Download`。
- 这些会员/下载在 Task26 只做 UI 或 toast，不做真实购买/下载。

UI 隐藏态：

- 点击视频隐藏顶部、底部、右侧栏，只保留视频。
- 再点恢复。

### 4.7 Series Player 剧集 Sheet

- 深色大底部 sheet，风格同详情 sheet。
- 头部有 poster/title/views/rating。
- 当前 tab 是 `Episodes`。
- range tabs 以 30 集为一组。
- 6 列网格，大数字。
- 当前集 cell 更亮，并在左下角显示小播放柱状 indicator。
- 锁定集右上角 lock badge。
- 免费范围来自 `drama.freeEpisodeRange`，为空时默认 `1...3`。

### 4.8 Speed / Quality / More

Speed sheet：

- 标题 `Speed`，右上角 X。
- 选项：`3.0x`、`2.0x`、`1.5x`、`1.25x`、`1.0x`、`0.75x`。
- 当前选中项是深灰圆角行，右侧粉色圆形 check。
- 选择后调用 `playerCoordinator.engine.setRate(value)`。

Quality sheet：

- 标题 `Current Quality`，右上角 X。
- 选项来自 `PlayerMediaSource.qualities`。
- 若没有 qualities，至少显示 `Auto`、当前 `720p` fallback、禁用的 `1080p VIP`、`540p`。
- 当前选中项同样用深灰行 + 粉色 check。
- VIP-only 只显示禁用样式，不做购买。

More sheet：

- 从 vertical ellipsis 打开。
- 至少包含 `Quality`、`Subtitles`、`Report subtitle issue`。
- 不支持的项显示 disabled 或 toast，不崩溃。

## 5. 必修技术修复

### 5.1 For You index 对齐

当前 `RecommendSession.initializePool` 使用 `compactMap` 跳过无 URL 卡片，存在 `dramas` index 和 player items index 错位风险。

必须修：

- 保持 `DramaItem` index 与 `PlayerMediaItem` index 映射。
- `engine.move(to:)` 使用 playable item index，不直接用原始 drama index。
- 无播放 URL 的卡片要打印诊断并安全跳过。

### 5.2 Series Player 切集真实播放源

当前代码主要在初始加载时 `fetchCurrentEpisodePlaybackURL()`。Task26 必须确保切集时也拉取对应 episode 的 play asset：

- `currentEpisode` 变化后，找到目标 episode id。
- 调用 `RealDetailRepository.fetchPlayAsset(episodeId:)`。
- 缓存 `episodeMediaSources[episodeId]`。
- 刷新或移动播放器时使用该集真实 source。
- 禁止 fallback 到 `about:blank`。

## 6. 验证命令

必须运行：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

如后端有任何修改，必须运行：

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn test
```

如果用户已显式启动后端，可以 smoke：

```bash
curl 'http://127.0.0.1:8080/api/v2/feed/for-you?limit=3&content_language=en&country_code=GLOBAL'
```

## 7. 交付报告

完成后新增：

- `docs/TASK26_DELIVERY_REPORT.md`

报告必须写：

- 修改文件列表。
- 每个参考状态对应的实现说明。
- 验证命令和结果。
- 是否有后端改动。
- 遗留风险。
- Xcode 手工 smoke 需要用户检查哪些点。

## 8. 提交要求

建议分小提交：

1. `fix: align for you playable item indexes`
2. `feat: polish for you player overlays`
3. `feat: polish series player controls`
4. `feat: add player option sheets`
5. `docs: add Task26 delivery report`

如果改动量较小，也可以合并成 1-2 个提交，但交付报告必须完整。
