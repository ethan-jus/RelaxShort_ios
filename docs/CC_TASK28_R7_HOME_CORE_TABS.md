# Task28 R7 中文任务书：Home 核心四个 Tab 收口（Popular / New / Rankings / Categories）

> 执行者：CC  
> 总控/验收：Codex  
> 仓库：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`  
> 分支：`main`  
> 基线提交：`8607354 feat: polish home popular rankings categories`

## 0. 任务背景

Task27 已经把 Home 的基础结构、ShareSheet、Categories 三行筛选和 sticky 摘要推进到可用状态。用户已确认 Categories sticky 摘要这轮 OK。

R7 不进入 Anime / VIP / Original+。本轮只把 Home 前四个核心 tab 做到可验收：

1. Popular
2. New
3. Rankings
4. Categories

这四个页面必须同时满足：

- UI 对标 DramaBox 参考图，不能继续出现临时拼装感。
- 接口联调使用真实后端数据，不能用 MockData 假装页面有内容。
- 修改范围小步、集中，不把后面 tab 或播放器一起带进来。

## 1. 参考图说明

CC 不要自行识图。Codex 已经看过这些图，下面是需要按文字执行的视觉要求。

参考目录：

`/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/`

关键截图：

- `tab_Popular.JPG`
- `tab_new(不要子tab，和预约功能).PNG`
- `tab_Rankings.PNG`
- `tab_Categories.PNG`

## 2. 全局 UI 规则

### 2.1 品牌色

- 所有 DramaBox 参考图里的粉色选中态，在 RelaxShort 内统一使用 `DB.logoRed` / `DT.logoRed`。
- 不要新增高饱和粉色、紫色、随机渐变色作为主选中态。

### 2.2 Poster 圆角

- 所有短剧封面统一使用 `DB.posterRadius`。
- 当前 `DB.posterRadius = 2`，不要在页面里写 `cornerRadius: 6/8/10` 之类的局部封面圆角。
- 如果发现某些卡片一张锐利、一张圆角很大，优先检查是否有外层背景或 `CoverImageView` 参数不一致，不要靠叠 `clipShape` 乱补。

### 2.3 Home 顶部 chrome

- 搜索栏、皇冠、礼物、顶部 tab 栏的位置保持 Task27 当前可接受状态。
- 不要再把搜索栏往下挪。
- 不要改底部导航栏。

### 2.4 真实数据

- Home / Rankings / Categories 在真实模式下不能使用 `MockData.homePopular`、`MockData.homeVipRecommendations`、`MockData.memberOnlyDramas` 兜底。
- 如果后端某接口返回空，要在交付报告写清楚接口返回情况，不允许用 mock 数据遮盖。
- VIP tab 当前仍有 MockData 遗留，本轮不处理，因为 R7 不进入 VIP tab。

## 3. Popular Tab 修复范围

当前 Popular 已基本可用，但仍需复查：

### UI 要求

- 顶部 3 列海报网格保持 DramaBox 风格：黑底、紧凑 3 列、海报锐利小圆角、标题 1-2 行。
- 下方 `You Might Like` 保持瀑布流/专题块，但不能出现明显圆角不一致。
- 所有卡片点击进入播放页。
- 文字不能溢出，不要遮挡底部 tab bar。

### 数据要求

- Popular 继续从 `HomeViewModel.featuredDramas/fixedDramas` 读取。
- `HomeViewModel.loadData()` 当前通过 `repository.fetchDramas(category: .all)` 拉取真实数据；真实 repository 优先 `/api/v2/home` 第一个有 items 的 section，空时 fallback 到 `/api/v2/feed/for-you`。R7 必须在报告中写清楚实际 smoke 时命中了哪个路径。

### 禁止事项

- 不要新增本地假数据。
- 不要重写 Popular 整体布局，只做清理和一致性修复。

## 4. New Tab 重做范围

参考 `tab_new(不要子tab，和预约功能).PNG`，但用户明确说：

- 不要做预约功能。
- 不要做复杂 Coming Soon 业务。

### UI 目标

New tab 做成 DramaBox 的 `Live Now` 列表风格：

- 顶部有一行轻量子 tab：
  - `Live Now`：选中，红色文字 + 深红半透明胶囊背景。
  - `Coming Soon`：非选中灰色，仅展示为禁用/占位，不实现预约列表。
- 列表项为横向大卡：
  - 左侧大封面，约 34%-38% 屏宽，2:3 比例。
  - 封面右上角可展示 `Today` 或日期标签。没有真实上线日期字段时，先用稳定派生：前两条 `Today`，后续按 `06/21` 这类静态 UI 文案显示即可，但必须集中封装在 view helper，不能散落魔法字符串。
  - 右侧标题 1-2 行，字号比当前更大。
  - 右侧简介 2-3 行，灰色。
  - 底部一行：分类/标签 + episode 数。
- 行间距参考图，保持大气但不松散。

### 数据目标

- 暂时使用 `HomeViewModel.dramasForNewTab`，它来自真实 Home/feed 数据排序派生。
- 不新增后端接口。
- 在代码注释或报告里说明：R7 New 是真实数据派生版，后续如果需要严格按上新时间排序，需要后端提供 release/schedule 字段。

### 质量要求

- 提取一个小的 `NewDramaRow` 私有 View，避免把 New 列表堆在 `HomeView` 主体里。
- 小屏宽度下右侧标题/简介不能挤出屏幕。

## 5. Rankings Tab 修复范围

参考 `tab_Rankings.PNG`。

### UI 目标

Rankings 不是纯黑底普通列表，顶部区域需要有一层棕黑渐变氛围：

- 背景从顶部的暖棕/深褐渐变到黑色，约覆盖子 tab + 前几张卡片区域。
- 三个子 tab 均匀分布：
  - `Most Trending`
  - `Top Searched`
  - `New Releases`
- 选中子 tab：
  - 使用低饱和棕色/灰棕胶囊背景，不用亮粉。
  - 文字白色。
- 非选中子 tab：
  - 灰色文字，细边框胶囊。
- 点击不同子 tab 时：
  - 调用对应真实 rankings API。
  - 页面背景渐变可以有非常轻微的色相差异，但必须克制，不要花。

### 排名卡片

- 每一行是独立深色圆角块，卡片之间有明确间距。
- 左侧排名数字大、固定宽度。
- 海报 3:4 或接近 DramaBox 的方正竖封面，圆角 `DB.posterRadius`。
- 中间标题最多 2 行，分类/标签灰色。
- 右侧是火焰 icon + 播放/热度数值。
- 卡片点击进入播放页。

### 数据/API

- `RankViewModel` 必须继续通过 `repository.fetchRankings(type:)`。
- 三个类型映射保持：
  - `Most Trending` -> `popular`
  - `Top Searched` -> `trending`
  - `New Releases` -> `new`
- smoke 时验证：
  - `/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL`
  - `/api/v2/rankings?type=trending&content_language=en&country_code=GLOBAL`
  - `/api/v2/rankings?type=new&content_language=en&country_code=GLOBAL`
- 如果某个 type 数据少或相同，先如实报告，不要本地假造不同榜单。

## 6. Categories Tab 复查范围

用户已确认 sticky 摘要这轮 OK，R7 只做复查，不主动重构。

### 必查点

- 三行筛选默认展示。
- 上滑筛选区完全隐藏后，显示 sticky 摘要。
- sticky 摘要不显示默认 `All`。
- 下滑筛选区重新出现后，sticky 摘要消失。
- 摘要里的箭头使用 `▼`。
- 点击 sticky 摘要可以展开筛选，展开后有收起入口。
- 语言、分类、付费三行间距保持紧凑，不要带 `Language / Genre / Payment` 标题。

### 数据/API

- Genre 行必须来自 `viewModel.categories`，也就是真实 `/api/v2/categories`。
- 选择后端分类时调用 `/api/v2/categories/{code}/series`。
- Language / Payment 当前可以是前端筛选状态，但报告要写清楚：语言/付费完整后端筛选仍需后端接口字段支持。

## 7. 建议修改文件

优先限制在这些文件：

- `RelaxShort/Views/Home/HomeView.swift`
- `RelaxShort/Views/Home/ContentGridView.swift`
- `RelaxShort/Views/Rank/RankView.swift`
- `RelaxShort/Views/Rank/RankCardView.swift`
- `RelaxShort/ViewModels/HomeViewModel.swift`
- `RelaxShort/ViewModels/RankViewModel.swift`
- `RelaxShort/Models/RankDrama.swift`
- `RelaxShort/Core/DesignToken.swift`
- `docs/TASK28_DELIVERY_REPORT.md`

必要时可以新增一个小组件文件，例如：

- `RelaxShort/Views/Home/NewDramaRow.swift`

但不要新建一堆抽象层。R7 的目标是收口前四个 tab，不是重构整个 Home。

## 8. 禁止修改

本轮不要改：

- 播放器内核。
- For You 页面。
- Series 全屏播放器。
- Anime / VIP / Original+ 的业务实现。
- 登录/Profile/My List/支付/广告。
- 后端 Flyway/SQL，除非真实 rankings/categories API 直接坏掉，且必须先停下来说明。

## 9. 验证命令

### iOS 构建

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

预期：`BUILD SUCCEEDED`

### Diff 检查

```bash
git diff --check
rg -n "MockData\\.homePopular|MockData\\.homeVipRecommendations|MockData\\.memberOnlyDramas|cat off|DEBUG HUD|print\\(" RelaxShort/Views/Home RelaxShort/Views/Rank RelaxShort/ViewModels
```

预期：

- 前四个 tab 真实路径不新增 MockData 兜底。
- 无临时调试 HUD。
- 不新增随手 `print`。

### 后端接口 smoke

后端由用户在 IDEA 显式启动，CC 不要自动启动后端进程。用户确认后端已在 `127.0.0.1:8080` 运行时，执行：

```bash
curl -sS 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL' | head -c 500
curl -sS 'http://127.0.0.1:8080/api/v2/feed/for-you?limit=20&content_language=en&country_code=GLOBAL' | head -c 500
curl -sS 'http://127.0.0.1:8080/api/v2/categories?content_language=en&country_code=GLOBAL' | head -c 500
curl -sS 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL' | head -c 500
curl -sS 'http://127.0.0.1:8080/api/v2/rankings?type=trending&content_language=en&country_code=GLOBAL' | head -c 500
curl -sS 'http://127.0.0.1:8080/api/v2/rankings?type=new&content_language=en&country_code=GLOBAL' | head -c 500
```

交付报告必须写出每个接口是否 200、是否有 items。

## 10. 交付报告

写：

`docs/TASK28_DELIVERY_REPORT.md`

报告必须包含：

1. 修改文件列表。
2. Popular / New / Rankings / Categories 每个 tab 的实际改动。
3. 真实 API 联调结果。
4. xcodebuild 结果。
5. 已知遗留：
   - Anime / VIP / Original+ 未进入 R7。
   - New 仍是从真实 Home/feed 数据派生，不是后端严格 release 数据。
   - VIP tab 当前还可能有 MockData，后续单独任务清理。

## 11. 验收标准

R7 通过条件：

- Popular/New/Rankings/Categories 在模拟器视觉上不再像临时拼装页面。
- New tab 明显接近参考图的 `Live Now` 横向列表。
- Rankings tab 有参考图里的暖棕渐变氛围、三子 tab、独立排名卡片。
- Categories sticky 摘要保持用户刚确认的正确行为。
- 四个 tab 数据来自真实 API 路径，不新增 mock 兜底。
- iOS build 通过。
- 交付报告真实，不夸大未完成的 tab。
