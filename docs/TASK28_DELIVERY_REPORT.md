# Task28 R7 交付报告：Home 核心四个 Tab 收口

## 范围

本轮只处理 Home 前四个核心 tab：

- Popular：复查真实数据路径和封面圆角一致性。
- New：从小列表改为更接近 DramaBox 的大图文列表，不增加 `Live Now / Coming Soon` 子 tab。
- Rankings：补顶部棕黑氛围渐变、三子 tab 克制选中态、独立排名卡片。
- Categories：保留 Task27 用户已确认的三行筛选和 sticky 摘要行为，仅回归检查。

Anime / VIP / Original+ 未进入本轮。

## 修改文件

- `RelaxShort/Views/Home/HomeView.swift`
- `RelaxShort/Views/Rank/RankView.swift`
- `RelaxShort/Views/Rank/RankCardView.swift`
- `docs/CC_TASK28_R7_HOME_CORE_TABS.md`
- `docs/TASK28_DELIVERY_REPORT.md`

## UI 改动

### Popular

- 保持现有 3 列海报网格和 `You Might Like` 结构。
- 封面继续统一使用 `DB.posterRadius = 2`。
- 未新增 mock 数据或额外布局分支。

### New

- 删除旧的小卡片列表样式。
- 新增 `NewDramaRow` 私有组件：
  - 左侧 2:3 大封面。
  - 右侧标题、简介、分类/标签/集数。
  - 封面角标保留 `Today / 06/21 / 06/20` 轻量 UI 文案，集中在 `newDateBadge(for:)`。
- 按用户要求，没有新增 `Live Now / Coming Soon` 子 tab。
- R8 修正：压缩单行卡片高度，封面宽度调整为 34% 区间但高度改为紧凑比例，简介从 3 行降到 2 行，行距从 22 降到 16，避免 New tab 显得笨重。

### Rankings

- `RankView` 增加顶部棕黑渐变背景。
- 三个榜单子 tab 保持：
  - `Most Trending` -> `popular`
  - `Top Searched` -> `trending`
  - `New Releases` -> `new`
- 子 tab 选中态改为低饱和棕/灰色胶囊，不使用高饱和粉色。
- `RankCardView` 改为参考图风格：
  - 左侧大排名数字。
  - 中间封面和标题/标签。
  - 右侧火焰 icon + 热度。
  - 每行独立深色卡片。
- R8 修正：把棕黑渐变背景上移到 `HomeView`，当选中 Rankings tab 时从状态栏/搜索栏区域开始覆盖全屏背景，而不是只覆盖 tab 内容区。
- R8 修正：压缩排名数字、封面和右侧热度区域宽度，增加标题可用空间，减少标题过早显示省略号。
- R8 修正：Rankings 子 tab 切换时同步切换全屏背景色和选中胶囊色：`Most Trending` 棕黑、`Top Searched` 紫色、`New Releases` 青绿色。

### Categories

- 未改动 sticky 摘要逻辑。
- 保持：
  - 默认 `All` 不进入摘要。
  - 摘要箭头使用 `▼`。
  - 筛选区重新出现时摘要取消。
  - Genre 来自真实 `/api/v2/categories`。

## 真实接口联调

后端由用户在 IDEA 显式启动，本轮只执行 curl smoke，不自动启动后端进程。

| 接口 | 结果 |
| --- | --- |
| `GET /api/v2/home?content_language=en&country_code=GLOBAL` | 200，tabs 返回成功，但 sections items 总数为 0 |
| `GET /api/v2/feed/for-you?limit=20&content_language=en&country_code=GLOBAL` | 200，items=18 |
| `GET /api/v2/categories?content_language=en&country_code=GLOBAL` | 200，items=10 |
| `GET /api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL` | 200，items=12 |
| `GET /api/v2/rankings?type=trending&content_language=en&country_code=GLOBAL` | 200，items=12 |
| `GET /api/v2/rankings?type=new&content_language=en&country_code=GLOBAL` | 200，items=12 |

结论：

- Popular/New 当前真实数据主要来自 `RealHomeRepository.fetchDramas(.all)` 的 fallback：`/api/v2/home` sections 为空时回退到 `/api/v2/feed/for-you`。
- Rankings 三个子 tab 都能拿到真实接口数据。
- Categories 分类字典能拿到真实接口数据。

## 验证

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

结果：

- `git diff --check` 通过。
- `xcodebuild` 通过：`BUILD SUCCEEDED`。

## 遗留

- `/api/v2/home` 当前 sections 为空，Popular/New 仍依赖 feed fallback；后端后续应补 Home tab/section 真实运营数据。
- New 的日期角标是 UI 派生文案，不是后端 release/schedule 字段。若要严格上新排序，需要后端补 release/schedule 字段。
- VIP tab 仍有 `MockData.homeVipRecommendations` / `MockData.memberOnlyDramas` 历史遗留，本轮没有处理，后续应作为 VIP tab 专项。
- Anime / VIP / Original+ 还未按 DramaBox 参考图进入正式开发。
