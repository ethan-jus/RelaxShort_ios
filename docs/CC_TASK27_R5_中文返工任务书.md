# Task27 R5 中文返工任务书

日期：2026-06-24
执行人：CC
复审人：Codex

## 先读

必须先读：

- `docs/CODEX_REVIEW_TASK27_R4.md`
- `docs/CC_TASK27_R4_BLOCKERS.md`
- 当前 iOS diff
- 当前后端 diff

R5 不是继续大改视觉，也不是扩大范围。R5 只修 R4 没完成的阻塞问题。

## 总原则

1. App 当前 Home / Rankings / Categories 联调必须使用真实后端接口数据。
2. 不允许用 `MockData` 或本地假数据掩盖真实 API 空数据、500 或字段问题。
3. 后端测试数据必须通过 Flyway migration 管理，不能手动导入后交付。
4. SwiftUI 不要靠堆魔法值碰运气。要先明确布局归属：顶部安全区、搜索栏、tab、内容区分别由谁负责。
5. 交付报告必须真实。只要 API 500、Flyway 没记录、页面没数据，就不能写“完成”。

## 一、后端 Rankings 必须修到 API 可用

当前问题：

- `/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL` 仍然 500。
- `rs_ranking_snapshots` 有数据不等于接口完成。

要求：

1. 查看后端运行日志，找出 500 的真实异常栈。
2. 修复真实原因，不允许只改 iOS 空态。
3. 重新验证：

```bash
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/rankings?type=trending&content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/rankings?type=new&content_language=en&country_code=GLOBAL'
```

验收：

- HTTP 200。
- `data.items` 数量大于 1。
- items 是真实旧数据/V5 媒资卡片，不是 mock。

## 二、V7 必须由 Flyway 正常管理

当前问题：

- 本地 `flyway_schema_history` 只有 V1-V6。
- R4 报告写 V7 是手动应用，这不合格。

要求：

1. 修复 `app-server/v2/src/main/resources/db/migration/V7__dev_seed_ranking_snapshots_from_real_media.sql`。
2. 所有同组 ranking seed 使用同一个固定 `snapshot_at`。
3. 用 `DELETE + INSERT` 保证本地 dev seed 幂等。
4. 不能依赖手动 docker exec 导入。
5. 如果当前本地库已经污染，给出清理命令并重新通过 Flyway 执行。

验收 SQL：

```sql
SELECT version, success FROM flyway_schema_history ORDER BY installed_rank;
SELECT ranking_type, language_code, country_code,
       COUNT(*) cnt, COUNT(DISTINCT snapshot_at) snapshots
FROM rs_ranking_snapshots
GROUP BY ranking_type, language_code, country_code;
```

验收：

- `flyway_schema_history` 有 version 7 且 success=1。
- 每个 ranking group 的 `snapshots = 1`。

## 三、Home 搜索栏顶部位置修正

当前错误代码方向：

```swift
.padding(.top, geo.safeAreaInsets.top + HomeMetrics.searchTopGap)
```

这会把搜索栏往下推。用户已经在模拟器看到搜索栏更低。

要求：

1. 不要在已经处于安全区布局的 VStack 内重复叠加 `geo.safeAreaInsets.top`。
2. 建立一个清楚的 Home 顶部 chrome 布局：
   - 背景可以忽略安全区。
   - 内容 chrome 不能压状态栏。
   - 搜索栏距离状态栏下沿是紧凑间距，参考 DramaBox 截图。
3. 搜索栏高度和 Search 页面搜索栏视觉高度一致。
4. 搜索栏、皇冠按钮、礼物按钮要垂直居中对齐。
5. 小屏、标准屏、大屏不能靠单一设备魔法值适配。

建议方向：

- 优先使用 `.safeAreaInset(edge: .top)` 或者让顶层 VStack 保持系统安全区布局，再只加一个小的 `topGap`。
- 如果保留 `GeometryReader`，变量名必须表达清楚含义，例如 `chromeTopGap`，不要再出现 `safeAreaInsets.top - 34` 或 `safeAreaInsets.top + 8` 这种无解释公式。

验收：

- 搜索栏不能比 R4 更低。
- 与 Search 页搜索栏高度一致。
- iPhone mini/标准机/Pro Max 顶部不压状态栏、不显得空。

## 四、Categories UI 按 DramaBox 参考重做

参考图：

`/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Categories.PNG`

注意：CC 不要自己“看图想象”。按下面文字要求实现。

要求：

1. 删除 Audio 分类行。
2. 筛选区风格：
   - 每一行是横向文字筛选。
   - 选中的 `All` 或当前项是粉色圆角 pill。
   - 未选中项是灰色文字，不要每个都画边框胶囊。
   - 行间距要有呼吸感。
   - 内容网格从筛选区下面自然开始，不要挤在一起。
3. 不要继续在 `HomeView.swift` 里硬编码所有筛选数组。
4. 至少抽出：
   - `CategoryFilterGroup`
   - `CategoryFilterOption`
   - `CategoryFilterBarView` 或类似独立组件
5. Genre/分类必须来自后端 `/api/v2/categories`。
6. Region / Language / Country 选项应来自后端数据库或配置接口。如果当前后端没有接口，R5 要写清楚缺口，并保留最小 UI，不要假装已经真实联动。
7. 选择已支持的筛选项时，要真正影响请求参数，例如：
   - `content_language`
   - `country_code`
   - `category_code`

验收：

- UI 观感明显接近 DramaBox Categories 截图。
- 没有 Audio。
- 不再是密集小胶囊 + 左侧 label 的丑陋矩阵。
- 分类数据来自后端接口。

## 五、移除 Task27 真实路径 MockData 兜底

当前不合格代码：

```swift
private var featuredOrEmpty: [DramaItem] {
    viewModel.featuredDramas.isEmpty ? MockData.homePopular : viewModel.featuredDramas
}
```

要求：

1. Home / Rankings / Categories 的真实联调路径不能用 MockData 兜底。
2. 如果接口没数据，显示真实空态或修后端 seed。
3. Mock 模式可以保留给全局开发开关，但不能影响 `use_real_api=1` 的验收。

## 六、验证命令

iOS：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

后端：

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
git diff --check
mvn test
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/rankings?type=trending&content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/rankings?type=new&content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/categories?content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/categories/romance/series?content_language=en&country_code=GLOBAL&limit=20'
```

数据库：

```sql
SELECT version, success FROM flyway_schema_history ORDER BY installed_rank;
SELECT ranking_type, language_code, country_code,
       COUNT(*) cnt, COUNT(DISTINCT snapshot_at) snapshots
FROM rs_ranking_snapshots
GROUP BY ranking_type, language_code, country_code;
```

## 七、交付报告

更新：

`docs/TASK27_DELIVERY_REPORT.md`

报告必须包含：

- 实际修改文件。
- 每条验证命令的真实结果。
- 如果仍有 500、空数据、Flyway 未记录，必须写失败，不能写完成。
- 截止 R5，哪些是已完成，哪些需要后续 Task28。
