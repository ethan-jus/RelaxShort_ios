# Task29 中文计划书：Home 剩余 Tab（Anime / VIP / Original+）开发前置计划

> 状态：候选计划，等待用户确认 Task28 前四个 tab 后再执行。  
> 执行者：CC  
> 总控/验收：Codex  
> 仓库：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`

## 0. 启动条件

不要现在执行。本计划只有在以下条件满足后才启动：

1. 用户在模拟器确认 `Popular / New / Rankings / Categories` 基本通过。
2. Codex 完成 Task28 diff review。
3. Codex 明确让 CC 执行 Task29。

## 1. 总原则

- CC 不要自行识图。Dramabox 截图由 Codex 先看，再转成文字要求。
- 一轮只做一个 tab，避免 Anime / VIP / Original+ 互相污染。
- 所有页面优先使用真实后端数据；真实接口缺字段时记录 gap，不用 MockData 假装完成。
- 保持 `DB.posterRadius = 2`，所有封面圆角统一。
- 不改 For You、播放器、Profile、My List、支付、广告。
- 不启动后端后台进程；后端由用户在 IDEA 显式运行，CC 只做 curl smoke。

## 2. 推荐执行顺序

### Task29-A：Anime tab

参考图：

`/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Anime.JPG`

Codex 识图后的文字要求：

- 顶部有一张横向 banner，大概 16:9 到 2.2:1 之间，左右贴近页面边距，标题压在图底部。
- `Weekly Featured` 是横向海报列表，三列半可横滑，海报下方标题和分类。
- `More Recommended` 是纵向图文列表：
  - 左侧竖封面。
  - 右侧标题、简介、分类/标签、集数。
  - 可显示 `Dubbed` 角标，但没有后端字段时不要硬造太多状态。
- 数据先从真实 Home/feed 数据中筛选：
  - 优先 tag/category/language 中包含 `Anime`。
  - 如果后端没有 anime 数据，展示空态并在报告说明，不用 MockData。
- 如果当前旧实现只是瀑布流，改成上述结构。

### Task29-B：VIP tab

参考图：

`/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_VIP.JPG`

Codex 识图后的文字要求：

- VIP tab 不是购买页，而是会员内容频道。
- 顶部直接显示 `Weekly Featured` 横向会员海报列表。
- 中间 `Exclusive on Dramabox` 风格横向会员海报列表。
- 下方 `VIP Classics` 是纵向图文列表。
- 会员内容角标使用金色 `Members Only`，不要使用粉色。
- 本轮必须清理 HomeView 里 VIP tab 对 `MockData.homeVipRecommendations` 和 `MockData.memberOnlyDramas` 的依赖。
- 如果真实接口缺少 VIP-only 内容：
  - 可以用真实 feed 中 `vipRequired == true` / `isVIPOnly == true` 的数据。
  - 如果没有，显示空态并报告后端缺 VIP 内容种子，不允许 mock。

### Task29-C：Original+ tab

参考图：

`/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Original+.JPG`

Codex 识图后的文字要求：

- 顶部有一张横向大 banner，标题压图底。
- 下方按 section 分组：
  - `Exclusive Originals`
  - `New Releases`
  - `NextGen Stories`
  - `Hidden Identity`
  - `Sweet Love`
  - `Werewolf & Mafia`
  - `Top Charts`
- 多数 section 是横向三列海报列表，最后 Top Charts 是纵向图文榜单。
- 本轮只实现可复用的 section 结构，不需要一次把所有后端分类字段做完整。
- 数据先来自真实 feed/home，按 tags/category 做轻量分组；如果后端没有对应分组字段，报告 gap。

## 3. 需要优先抽出的组件

为了避免重复开发，CC 可以在 Task29-A 先抽出这些小组件，后续复用：

- `HomePosterRailSection`
  - 标题 + 横向海报列表。
  - 用于 Anime Weekly Featured、VIP Weekly Featured、Original+ 多个 section。

- `HomeDramaListRow`
  - 左封面 + 右标题/简介/标签/集数。
  - 用于 Anime More Recommended、VIP Classics、Original+ Top Charts。

- `HomeHeroBanner`
  - 横向 banner + 底部标题遮罩。
  - 用于 Anime 和 Original+。

约束：

- 组件只放 Home 相关目录，不要改全局组件太多。
- 组件参数要基于 `DramaItem`，不要引入新的 mock model。
- 不要为了复用牺牲页面差异，必要时通过少量参数控制样式。

## 4. 后端/API gap 记录

Task29 每个 tab 交付报告必须写：

- 实际数据来源是 `/api/v2/home`、`/api/v2/feed/for-you` 还是其他接口。
- 是否有对应 tab 的专用 section 数据。
- 是否存在用 tag/category 进行前端轻量分组的临时逻辑。
- 哪些字段应该后端补：
  - `section_code`
  - `release_date`
  - `is_vip_only`
  - `is_original`
  - `is_anime`
  - `localized_section_title`

## 5. 验证

每个子任务必须执行：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

后端由用户在 IDEA 显式启动后，再执行必要 curl。CC 不要启动后台 Java 进程。

## 6. 交付报告

每个子任务交付一个文档：

- `docs/TASK29_A_ANIME_DELIVERY_REPORT.md`
- `docs/TASK29_B_VIP_DELIVERY_REPORT.md`
- `docs/TASK29_C_ORIGINAL_PLUS_DELIVERY_REPORT.md`

报告必须真实写明完成和未完成，不要说“完全对标”。
