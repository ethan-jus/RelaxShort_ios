# Task27 R6 中文任务书：Categories 三行筛选与交付报告修正

日期：2026-06-24
执行人：CC
复审人：Codex

## 背景

R5 后 Home 搜索栏位置基本可接受。Rankings 500 的根因已由 Codex 在后端修复：

- `RankingSnapshot.rank` 改为 `rankPosition`
- `RankingService` 改用 `RankingSnapshot::getRankPosition`

CC 不要重复改这个后端修复。R6 只做 Categories 小范围增强和交付报告修正。

## 范围

只允许改：

- `ios/v1.0.0/RelaxShort/Views/Home/HomeView.swift`
- 必要时新增一个轻量 Categories filter 组件文件
- 必要时改 `HomeViewModel.swift` / `HomeCategory.swift` / `RealHomeRepository.swift`
- `docs/TASK27_DELIVERY_REPORT.md`

不要改：

- PlayerKit
- For You 播放器
- Series 播放页
- ShareSheet
- Ranking 卡片 UI
- 后端 Rankings 已修好的 Java 代码

## 目标 UI

Categories tab 不再追求一次完全复刻 DramaBox。按用户确认，做简单、清楚的三行筛选。

参考图仍是：

`/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Categories.PNG`

CC 不需要看图，按下面文字实现。

### 第一行：语言/地区内容筛选

展示项：

```text
All, Local, Chinese, Korean, Japanese, Spanish, Others, English
```

行为：

- 每行第一个都是 `All`。
- 选中项为粉色圆角 pill。
- 未选中项为灰色文字。
- 不要给每个未选中项都加边框胶囊。
- 横向滚动即可，小屏不能挤压换行。

请求参数映射建议：

- `All`：不覆盖当前 `content_language`
- `Local`：使用当前 app/user 的 `content_language`
- `Chinese`：`zh-Hans`
- `Korean`：`ko`
- `Japanese`：`ja`
- `Spanish`：`es`
- `English`：`en`
- `Others`：如果后端暂无聚合语义，不要假过滤；可以先作为 UI disabled 或记录待后端支持

数据来源要求：

- 后端已有 `rs_languages`，长期应由后端 filter config 下发。
- R6 如果不新增后端接口，可以在交付报告中明确：语言行当前使用后端已支持语言码的 iOS 显示映射，后续需要 `/api/v2/home/filters` 或等价接口统一下发。

### 第二行：分类筛选

数据来源：

- 必须继续来自后端 `/api/v2/categories`。
- 选择分类后调用 `/api/v2/categories/{code}/series`。

展示：

- 第一个 `All`。
- 后面展示后端返回分类名称。
- 样式和第一行一致。

行为：

- `All`：显示当前语言/地区下的默认列表，优先走真实接口，不要使用 MockData。
- 具体分类：调用 `categorySeries`。

### 第三行：付费筛选

展示项：

```text
All, Paid, Members Only, Free
```

行为：

- 样式和前两行一致。
- 如果后端 category series 接口暂不支持付费筛选参数，不要假装已后端联动。
- 可先用现有 card 的 `monetization` / `freeEpisodeRange` 字段做前端展示过滤，但交付报告必须写清楚这是临时前端过滤，正式应补 API 参数。

## 代码质量要求

1. 不要把三行筛选都写成散乱的 `@State String` 和硬编码 HStack。
2. 至少抽出轻量模型：

```swift
struct CategoryFilterOption: Identifiable, Equatable {
    let id: String
    let title: String
}
```

3. 至少抽出可复用行组件，例如：

```swift
CategoryFilterRowView(options:selected:)
```

4. `HomeView.swift` 可以保留组装逻辑，但不要塞大量重复 Button 样式。
5. 小屏、标准屏、大屏都要横向滚动，不要换行，不要文字挤压。

## 验证

iOS：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

后端当前由 Codex 已验证修复后：

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn test
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
```

注意：如果 8080 还是 500，先确认 IDEA 后端是否已重启到最新代码。

## 交付报告

更新：

`docs/TASK27_DELIVERY_REPORT.md`

必须写清楚：

- Home 搜索栏状态。
- Rankings 500 根因是 `rank_position AS rank`，已由 Codex 后端修复。
- Categories 当前三行筛选实现方式。
- 哪些筛选是真实后端参数，哪些是临时前端过滤或待后端 filter config API。
