# Task29-B：Home VIP / Original+ 页面 UI 与真实接口联调

## 背景

Task29-A 已完成 Popular / New / Rankings / Categories / Anime 的主要收口，并补齐了 Home 卡片所需的 `horizontal_cover_url` 与 `display_flags`。

当前剩余问题集中在 Home 的 VIP 与 Original+ 两个 tab：

- iOS `HomeView.homeVIPTabContent` 仍使用 `MockData.homeVipRecommendations` / `MockData.memberOnlyDramas`。
- iOS `originalPlusTabContent` 仍用 `featuredDramas.filter` 兜底，页面结构和 DramaBox 参考图差距较大。
- 后端 `/api/v2/home` 虽然已有 sections，但当前所有 tab 基本复用同一批 For You cards，VIP / Original+ 没有独立 section 内容语义。
- 本轮目标是把 VIP / Original+ 做成真实接口驱动的页面，不再靠 Mock 或硬编码业务数据支撑。

参考截图由 Codex 已人工核对，CC 不需要识图。关键参考文件：

- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_VIP.JPG`
- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Original+.JPG`

## 总目标

在不改播放器核心的前提下，完成 Home VIP / Original+ 两个 tab 的 UI 与后端数据闭环：

- VIP tab：接近 DramaBox 的会员剧频道结构。
- Original+ tab：接近 DramaBox 的原创剧频道结构。
- 数据全部来自真实后端 `/api/v2/home` section items 或明确的后端 seed，不允许新增 iOS Mock 绕过接口。
- iOS 与后端分别提交，不要跨仓库混合提交。

## 工作边界

### 必须做

1. iOS 读取 `/api/v2/home` 中指定 tab 的 sections，而不是只取第一个有 items 的 section。
2. 后端为 `vip` 和 `original_plus` 提供可区分的 Home sections 与 items。
3. iOS VIP / Original+ 删除 MockData 依赖。
4. UI 结构按本文描述实现，使用现有 `DramaItem`、`CoverImageView`、`DB.posterRadius`、`displayFlags` 等已有模型和组件。
5. 所有封面圆角继续统一使用 `DB.posterRadius`，不要重新写 `cornerRadius: 6`、`8` 等散落魔法值。
6. 多屏兼容：小屏、标准屏、Pro Max 宽度都不能文字溢出、卡片遮挡、横向列表断裂。

### 不做

- 不做 Search / Profile / Member 页面。
- 不改播放器核心。
- 不新增 Live Now / Coming Soon / 预约功能。
- 不提交 `old-sql/relax_db_v5.sql`。
- 不接入真实支付。
- 不新增静态的 `Dubbed`、`AI`、`Hot`、`Members Only` 业务字段到 iOS 代码。角标必须来自后端 `display_flags` 或变现信息。

## 后端要求：`/Users/ethan/myspance/relaxshort/app-server/v2`

### 1. Home section 数据结构

当前 `HomeService` 用所有 tab 复用 `feedService.getForYou(...).getItems()`，这只能当临时烟测，不足以支撑 VIP / Original+。

本轮允许用最小可维护方案，不要求重做完整运营后台：

- 新增 Flyway：`V11__dev_seed_home_vip_original_sections.sql`
- 在 `rs_home_sections` 中为两个 tab seed 明确 section：
  - VIP:
    - `vip_weekly_featured`
    - `vip_exclusive`
    - `vip_classics`
  - Original+:
    - `original_hero`
    - `original_exclusive`
    - `original_new_releases`
    - `original_nextgen`
    - `original_hidden_identity`
    - `original_sweet_love`
    - `original_werewolf_mafia`
    - `original_top_charts`

如果现有 `rs_home_section_items` 设计可用，优先用它给 section 绑定 series/card，并让 `HomeService` 真正按 section 返回 items。

如果现有 mapper 不完整，可以本轮新增最小 mapper/entity：

- `HomeSectionItem` entity
- `HomeSectionItemMapper`
- `HomeService` 中先查 section items，再根据 `rs_feed_card_snapshots.series_id` 组装对应 cards。

注意：不要为了省事继续所有 section 复制同一批 For You cards。至少 VIP 和 Original+ 的 section item 顺序要可区分。

### 2. VIP 数据规则

dev seed 里给 VIP section 选 12-18 条真实可播放 series：

- 优先使用现有 V5 真实媒体 series。
- 将部分 cards 的 `monetization_json.vip_required` 设置为 1，或使用 `display_flags_json = JSON_ARRAY('Members Only')` 表示会员角标。
- 如果字段已经由 `vip_required` 表示，iOS 可显示 `Members Only`，但文案映射应集中在一个 helper，不能在多个 View 里散落。

VIP section 最少数据量：

- `vip_weekly_featured`: 6 条，横向 3 列半海报。
- `vip_exclusive`: 6 条，横向 3 列半海报。
- `vip_classics`: 6 条，纵向图文列表。

### 3. Original+ 数据规则

dev seed 里给 Original+ section 选 20-30 条真实可播放 series：

- `original_hero`: 1-3 条，优先使用 `horizontal_cover_url`。
- 其他横向 section 每组至少 6 条。
- `original_top_charts`: 至少 6 条，纵向图文榜单。

可以使用现有真实 series 做 dev 占位，但必须通过后端 section 配置下发，不允许 iOS 自行 filter 假装有频道数据。

### 4. API 验证

后端启动后验证：

```bash
curl 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL'
```

需要确认：

- `vip` tab 下有 3 个 sections，且每个 section items 非空。
- `original_plus` tab 下有 8 个 sections，且关键 sections items 非空。
- items 中保留：
  - `cover_url`
  - `horizontal_cover_url`
  - `display_flags`
  - `monetization.vip_required`
  - `view_count`
  - `category`
  - `language_tag`
  - `episode_count`
  - `play_asset`

后端验证命令：

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn test
mvn package -DskipTests
```

## iOS 要求：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`

### 1. HomeResponseDTO 保留 section 语义

当前 `RealHomeRepository.fetchHomeFirstSection` 只取第一个有 items 的 section，这会让 iOS 丢失 tab/section 结构。

本轮需要新增一个轻量结构承接 Home sections：

建议新增：

```swift
struct HomeTabContent {
    let code: String
    let sections: [HomeSectionContent]
}

struct HomeSectionContent: Identifiable {
    let id: String
    let code: String
    let sectionType: String?
    let titleKey: String?
    let items: [DramaItem]
}
```

`RealHomeRepository` 增加方法：

```swift
func fetchHomeTabs(contentLang: String?, country: String?) async throws -> [HomeTabContent]
```

`HomeViewModel` 增加：

```swift
@Published var homeTabsByCode: [String: HomeTabContent] = [:]
func sections(for tabCode: String) -> [HomeSectionContent]
```

`loadData()` 里从 `/api/v2/home` 加载后填充 `homeTabsByCode`。原有 `featuredDramas` 可以继续用于 Popular / 兼容旧逻辑，但 VIP / Original+ 必须优先使用 `sections(for:)`。

### 2. VIP UI 结构

参考 `tab_VIP.JPG`，实现三块：

1. `Weekly Featured`
   - 顶部不做额外金色大 banner。
   - 标题左对齐，18-20 semibold，白色。
   - 横向 ScrollView，海报卡片宽度约屏宽 30%，一屏显示 3 张左右并露出下一张边缘。
   - 海报右上角显示会员/运营角标，来自 `display_flags` 或 `isVIPOnly`。
   - 海报底部显示播放量叠层。
   - 海报下方两行：标题、分类。

2. `Exclusive on Dramabox` 的 RelaxShort 版本
   - 文案建议：`Exclusive on RelaxShort`。
   - 同样横向海报列表。

3. `VIP Classics`
   - 纵向图文列表。
   - 左侧海报，右侧标题、简介、分类/标签、集数。
   - 不要加卡片壳，不要大圆角背景。

如果需要本地化，优先走现有 `L10n`；没有 key 时先集中在一个 helper，不要多处散落英文。

### 3. Original+ UI 结构

参考 `tab_Original+.JPG`，实现：

1. 顶部 Hero
   - 使用 `original_hero` section 第一条或前三条。
   - 横版图优先 `bannerCoverURL ?? coverURL`。
   - 只显示底部标题和低调指示器；不做大块渐变卡片替代真实图片。

2. 横向内容 sections
   - `Exclusive Originals`
   - `New Releases`
   - `NextGen Stories`
   - `Hidden Identity`
   - `Sweet Love`
   - `Werewolf & Mafia`
   - 每组横向海报列表，标题左对齐，封面比例和 Anime/VIP 一致。
   - 角标由 `display_flags` 下发。

3. `Top Charts`
   - 纵向图文列表，样式可复用 VIP Classics。

### 4. 组件复用

不要继续在 `HomeView.swift` 里复制三套卡片代码。允许本轮做小范围拆分：

建议新增或提取到 `RelaxShort/Views/Home/HomeSectionViews.swift`：

- `HomePosterRail`
- `HomePosterCard`
- `HomeMediaList`
- `HomeMediaListRow`
- `HomeHeroCarousel`（可由 Anime 原 `AnimeHeroCarousel` 泛化）

要求：

- 组件只接收 `[DramaItem]`、标题、点击回调。
- 组件内部统一使用 `DB.posterRadius`。
- 组件内部处理 `displayFlags.first`、播放量、标题行数。
- 不要让组件直接访问 `MockData`。

### 5. 清理 Mock 依赖

完成后检查：

```bash
rg -n 'MockData.homeVip|MockData.memberOnly|Original\\+|Exclusive original series|VIP Picks|Member-only Dramas' RelaxShort/Views/Home
```

预期：

- `MockData.homeVipRecommendations` 无命中。
- `MockData.memberOnlyDramas` 无命中。
- 旧的 `VIP Picks` 大 banner 文案无命中。
- 旧的 `Exclusive original series` 无命中。

### 6. iOS 验证

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

额外检查：

```bash
rg -n 'cornerRadius: 6|cornerRadius\\(6\\)|RoundedRectangle\\(cornerRadius: 6' RelaxShort/Views/Home
rg -n 'MockData.homeVip|MockData.memberOnly' RelaxShort/Views/Home
rg -n 'displayFlags|bannerCoverURL|horizontalCoverUrl' RelaxShort/Views/Home RelaxShort/Core RelaxShort/Models
```

## UI 质量要求

- 黑色背景保持 Home 频道整体风格。
- 不要用大面积金色渐变 banner 替代内容图，参考图 VIP 是直接内容列表，不是营销卡片。
- 不要出现卡片套卡片。
- 不要让标题、分类、集数挤压重叠。
- 小屏上横向 card 宽度要用 `containerW` 推导，不要写死只能适配 iPhone 17 Pro Max 的尺寸。
- Original+ 的顶部 Hero 要用真实图，不要用纯渐变 + icon。
- 频道标题、section 标题、tab 间距要和已经修过的 Popular/New/Anime 风格一致。

## 交付要求

### iOS 交付报告

更新或新增：

`/Users/ethan/myspance/relaxshort/ios/v1.0.0/docs/TASK29_B_HOME_VIP_ORIGINAL_PLUS_REPORT.md`

必须包含：

- 修改文件列表。
- 哪些 Mock 依赖已删除。
- VIP / Original+ 分别使用哪些 section code。
- iOS build 结果。
- 仍未完成或需要 Codex 决策的问题。

### 后端交付报告

新增：

`/Users/ethan/myspance/relaxshort/app-server/v2/docs/TASK29_B_HOME_VIP_ORIGINAL_PLUS_BACKEND_REPORT.md`

必须包含：

- 新增 Flyway 版本。
- 新增/使用的表、mapper、section code。
- curl `/api/v2/home` 摘要。
- `mvn test` / `mvn package -DskipTests` 结果。

## 提交要求

不要自动 push。

如果需要提交，必须分仓库提交：

后端：

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
git add <backend files>
git commit -m "feat: seed home vip original sections"
```

iOS：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git add <ios files>
git commit -m "feat: polish home vip original tabs"
```

## 禁止事项复述

- 不要跨仓库混合提交。
- 不要提交旧 SQL 大文件。
- 不要引入新的 Mock 数据绕过真实接口。
- 不要新增播放器改动。
- 不要新增预约 / Coming Soon / Live Now。
- 不要把截图理解工作交给 CC；本文已经把截图要求转成文字，按文字执行。
