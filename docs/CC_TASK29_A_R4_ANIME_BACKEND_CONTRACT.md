# Task29-A R4：Anime 横幅媒资与 Home 接口联调闭环

## 背景

当前 Anime tab 的 UI 基本完成，但还没有做到真正的前后端数据契约闭环：

- iOS Anime Hero 现在使用 `DramaItem.coverURL` 裁成横幅，实际是竖版海报，不是横版 banner。
- 后端表 `rs_series` 已有 `horizontal_cover` 字段，但 Feed/Home/Ranking/Category 复用的卡片 DTO 只返回 `cover_url`。
- iOS `DramaItem` 只有 `coverURL`，没有 `bannerCoverURL` / `horizontalCoverURL`。
- Anime 卡片角标现在由 iOS 写死 `"Test"`，这不符合真实运营配置，应该由后端数据下发。
- `/api/v2/home` 之前 smoke 显示 sections items 为空，Popular/New/Anime 不能只依赖前端 fallback，需要明确接口数据是否完整。

本轮目标不是继续单纯微调 UI，而是把 Anime 所需的后端字段、dev seed、接口返回、iOS 解码、UI 展示和验证一次性补齐。

## 工作范围

### 后端：`/Users/ethan/myspance/relaxshort/app-server/v2`

1. 补齐卡片接口字段
   - 在 `ForYouFeedResponse.FeedCardDto` 增加：
     - `horizontalCoverUrl` 或 `bannerCoverUrl`，字段名下发为 `horizontal_cover_url` 或 `banner_cover_url`，二选一后保持 iOS 一致。
     - `displayFlags`，下发为 `display_flags`，类型为字符串数组。
   - 推荐使用 `horizontal_cover_url`，因为数据库已有 `rs_series.horizontal_cover`。
   - 推荐使用 `display_flags`，不要做成单个硬编码 `Test` 字段，后续可以配置 `AI`、`Hot`、`Exclusive` 等运营标识。

2. 补齐快照表和实体
   - 当前 `rs_feed_card_snapshots` 没有横版封面和展示 flags。
   - 新增 Flyway 迁移，版本使用当前最大版本之后的下一个版本。当前已存在到 `V7__dev_seed_ranking_snapshots_from_real_media.sql`，如无新增版本冲突，使用 `V8__feed_card_horizontal_cover_and_display_flags.sql`。
   - 给 `rs_feed_card_snapshots` 增加：
     - `horizontal_cover_url VARCHAR(512) NULL COMMENT '横版Banner图URL'`
     - `display_flags_json JSON NULL COMMENT '运营展示标识，如 ["Test","AI"]'`
   - 更新 `FeedCardSnapshot` 实体。
   - 更新 `FeedService.toDto` 和 `DiscoveryService.toDto`，确保 Feed、Home、Ranking、Category、Search 等复用卡片 DTO 的接口都能返回新字段。

3. 补齐 dev seed 真实数据
   - 不要提交 `old-sql/relax_db_v5.sql` 大文件。
   - 从现有旧 SQL 或当前真实媒资中查找可用横版 banner 图片 URL：
     - 优先使用旧 SQL 中已有 banner/horizontal/image_url 类字段。
     - 如果旧 SQL 没有横版图，只能临时用真实 CDN 竖版图作为 fallback，但必须在交付报告里明确说明“没有横版源素材，暂用竖版图回退”。
   - 至少给 Anime Hero 的 3 条数据写入 `horizontal_cover_url`。
   - 至少给 Anime tab 的部分测试数据写入 `display_flags_json = JSON_ARRAY('Test')`，由后端下发，不允许 iOS 写死。

4. 检查 `/api/v2/home` sections 数据
   - 启动后端后，用 curl 验证：
     - `/api/v2/home?content_language=en&country_code=GLOBAL`
     - `/api/v2/feed/for-you?limit=20&content_language=en&country_code=GLOBAL`
     - `/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL`
     - `/api/v2/categories/{categoryId}/series?content_language=en&country_code=GLOBAL`
   - `/api/v2/home` 的 tabs/sections 不能只返回空 items。如果当前设计就是 Home 只返回 tab shell，必须在交付报告里说明原因，并给出下一步后端设计；否则本轮要修 seed 或 HomeService，让 Popular/New/Anime 可拿到真实 section items。

### iOS：`/Users/ethan/myspance/relaxshort/ios/v1.0.0`

1. 扩展模型和 DTO
   - `FeedCardDTO` 解码新增：
     - `horizontalCoverUrl` / `bannerCoverUrl`
     - `displayFlags`
   - `DramaItem` 新增：
     - `bannerCoverURL: String?` 或 `horizontalCoverURL: String?`
     - `displayFlags: [String]`
   - `FeedCardDTOMapper.toDramaItem` 负责映射。
   - 保持兼容旧接口：没有横版图时 UI 使用 `coverURL` fallback。

2. Anime Hero 使用横版图
   - `AnimeHeroCarousel` 优先使用 `drama.bannerCoverURL ?? drama.coverURL`。
   - Hero 数据限制为 3 条，5 秒自动轮播，点击仍进入播放。
   - 指示器保持当前 R3 方案，但要避免低质感：短线/胶囊宽度、间距、透明度要接近 DramaBox 风格，不要做太大的圆点。

3. Anime 角标改为后端动态
   - 删除 `displayFlag(for:) -> "Test"` 这种 iOS 硬编码。
   - `displayFlag(for:)` 只从 `drama.displayFlags.first` 读取。
   - 如果后端没有 flags，不显示角标。

4. 前面 tab 的联调检查
   - Popular/New/Rankings/Categories/Anime 当前都必须基于真实接口数据。
   - 不新增 Mock 数据绕过接口。
   - 如果某个 tab 仍然使用 fallback，要在交付报告里写明 fallback 来源、原因、后续应该补哪个后端接口或字段。

## 禁止事项

- 不要提交 `src/main/resources/db/old-sql/relax_db_v5.sql`。
- 不要在 iOS 写死 `"Test"`、`"Dubbed"`、`"AI"` 作为业务数据。
- 不要为了 UI 好看新增无来源的假字段或假数据。
- 不要跨仓库混合提交；iOS 和后端如需提交，分别提交。
- 不要改生产凭据、不要改真实线上配置。
- 不要只跑 build 就说联调完成，必须给 curl 输出摘要。

## 验证要求

后端：

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn test
mvn package -DskipTests
```

后端启动后验证：

```bash
curl 'http://127.0.0.1:8080/api/v2/feed/for-you?limit=3&content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
```

curl 结果至少确认：

- 卡片里有 `cover_url`。
- 有横版字段：`horizontal_cover_url` 或 `banner_cover_url`。
- Anime 测试数据里有 `display_flags`，例如 `["Test"]`。
- `/api/v2/home` 的 section items 是否为空必须写进报告。

iOS：

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

代码检查：

```bash
rg '"Test"|"Dubbed"' RelaxShort
rg 'horizontalCover|bannerCover|displayFlags' RelaxShort
git diff --check
```

预期：

- iOS 代码里不能再有业务角标硬编码 `"Test"`。
- Anime Hero 使用横版字段优先，缺失时才 fallback 到竖版封面。
- `displayFlags` 从接口映射到 UI。

## 交付报告

分别更新：

- iOS：`/Users/ethan/myspance/relaxshort/ios/v1.0.0/docs/TASK29_A_ANIME_DELIVERY_REPORT.md`
- 后端：`/Users/ethan/myspance/relaxshort/app-server/v2/docs/TASK29_A_R4_BACKEND_CONTRACT_REPORT.md`

报告必须包含：

- 修改文件列表。
- 新增/修改的后端字段。
- Flyway 版本号。
- curl 验证摘要。
- iOS build 结果。
- 仍然缺少横版真实素材时的 fallback 说明。
- 是否还有 tab 依赖 fallback。
