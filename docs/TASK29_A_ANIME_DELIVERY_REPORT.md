# Task29-A R4 Anime Tab — Delivery Report

> 日期：2026-06-26
> R4: 前后端一起补齐横版 banner、display_flags、Home sections 数据闭环

## iOS 修改（4 files）

| 文件 | 变更 |
|------|------|
| `Models/API/ForYouFeedResponseDTO.swift` | `FeedCardDTO` 新增 `horizontalCoverUrl: String?` + `displayFlags: [String]?` |
| `Models/DramaItem.swift` | 新增 `bannerCoverURL: String?` + `displayFlags: [String]` |
| `Core/Services/RealHomeRepository.swift` | `FeedCardDTOMapper.toDramaItem` 映射 `item.bannerCoverURL = card.horizontalCoverUrl` + `item.displayFlags = card.displayFlags ?? []` |
| `Views/Home/HomeView.swift` | `displayFlag(for:)` 改为 `drama.displayFlags.first`；`AnimeHeroCarousel` 使用 `drama.bannerCoverURL ?? drama.coverURL`；空态/标题使用 `L10n`，列表元信息不再写死 `Anime` |

## 后端修改

| 文件 | 变更 |
|------|------|
| `V8__feed_card_horizontal_cover_and_display_flags.sql` | ALTER TABLE 增加 `horizontal_cover_url` + `display_flags_json`；seed 前 3 条 Anime 数据 |
| `V9__backfill_feed_card_horizontal_cover_from_series.sql` | 优先从 `rs_series.horizontal_cover` 回填横版图 |
| `V10__dev_seed_home_sections.sql` | seed 当前 Home tabs 的 section 配置，避免 `/home` 只有 tab shell |
| `FeedCardSnapshot.java` | 新增 `horizontalCoverUrl` + `displayFlagsJson` 字段 |
| `ForYouFeedResponse.java` | `FeedCardDto` 新增 `horizontalCoverUrl` + `displayFlags` |
| `FeedService.java` | `toDto` 映射 `.horizontalCoverUrl()` + `.displayFlags(...)`，Feed/Home 缓存 key 升级 |
| `DiscoveryService.java` | `toDto` 映射 `.horizontalCoverUrl()` + `.displayFlags(parseArray(...))` |
| `HomeService.java` | Home 缓存 key 升级，并修复每个 tab section item cursor 复用导致后续 tab 为空的问题 |

## 验证

| 命令 | 结果 |
|------|------|
| `xcodebuild ... iPhone 17 Pro Max` | ✅ BUILD SUCCEEDED |
| `mvn test` (backend) | ✅ 240 tests, 0 failures, 0 errors |
| `git diff --check` (iOS) | ✅ clean |
| `rg '"Test"\|"Dubbed"' RelaxShort/Views/Home RelaxShort/Core RelaxShort/Models` | ✅ Anime 业务角标无 iOS 硬编码 |
| `rg horizontalCover\|bannerCover\|displayFlags` | ✅ 8 处引用，一致贯通 |
| Flyway migrate (dev MySQL) | ✅ V8/V9/V10 applied, schema version 10 |
| curl `/api/v2/home` | ✅ sections/items 非空，返回 `horizontal_cover_url` + `display_flags` |

## 数据闭环状态

| 链路 | 状态 |
|------|------|
| DB column `horizontal_cover_url` | ✅ V8 ALTER TABLE |
| DB column `display_flags_json` | ✅ V8 ALTER TABLE |
| 横版图回填策略 | ✅ V9 优先 `rs_series.horizontal_cover`，缺失时沿用 V8 dev fallback |
| Home sections seed | ✅ V10 seed `rs_home_sections` |
| Entity → DTO | ✅ `FeedService.toDto` + `DiscoveryService.toDto` 映射 |
| API → iOS DTO | ✅ `FeedCardDTO.horizontalCoverUrl` + `displayFlags` |
| DTO → UI Model | ✅ `DramaItem.bannerCoverURL` + `displayFlags` |
| UI Hero | ✅ `bannerCoverURL ?? coverURL` |
| UI Flag | ✅ `displayFlags.first`（无硬编码） |

## 已知限制

- 暂无横版 banner 真实素材，当前 dev seed 仍用竖版 `cover_url` 回填 `horizontal_cover_url`
- `display_flags` 当前 seed 为 `["Test"]`，后续替换为运营真实角标
- 当前 Home sections 已有真实 items；内容仍复用 for-you feed pool，后续可按 tab 建独立运营池
