# Task 15 交付报告：iOS Real API Phase 2

**分支**: `task/task15-ios-real-api-phase2`
**日期**: 2026-06-21

## 执行摘要

按 `docs/CC_TASK15_IOS_REAL_API_PHASE2.md` 完成 iOS 真实 API Phase 2：消费后端 Task14 新增字段、新增 Home/Search/Ranking/Categories 真实 API endpoint、清理过时默认值、注入 RealSearchRepository。

## 修改文件清单

### 新增（1 个）

| 文件 | 说明 |
|------|------|
| `RelaxShort/Core/Services/RealSearchRepository.swift` | 真实 Search 仓库 + SearchDefault/Search Response DTO |

### 修改（5 个）

| 文件 | 变更 |
|------|------|
| `RelaxShort/Models/API/ForYouFeedResponseDTO.swift` | FeedCardDTO 新增 Task14 展示字段（viewCount/category/regionTag/languageTag/episodeCount/freeEpisodeRange）+ FreeEpisodeRangeDTO |
| `RelaxShort/Core/Services/RealHomeRepository.swift` | FeedCardDTOMapper 清理过时 Gap 注释，使用后端真实字段；fetchDramas 扩展支持 Home/rankings/categories；新增 HomeResponseDTO/RankingResponseDTO/CategoriesResponseDTO |
| `RelaxShort/Core/Services/APIEndpoint.swift` | 新增 6 个 v2 端点（home/searchDefault/searchV2/rankings/categories/categorySeries） |
| `RelaxShort/Core/Services/DependencyContainer.swift` | use_real_api=true 时注入 RealSearchRepository |
| `RelaxShort.xcodeproj/project.pbxproj` | RealSearchRepository.swift 加入 Sources |

## 已接入真实 API endpoint

| Endpoint | 路径 | 使用位置 |
|----------|------|----------|
| `home` | GET /api/v2/home | RealHomeRepository.fetchHomeFirstSection() |
| `searchDefault` | GET /api/v2/search/default | RealSearchRepository.fetchDramas() |
| `searchV2` | GET /api/v2/search | RealSearchRepository.search() |
| `rankings` | GET /api/v2/rankings | RealHomeRepository.fetchRankings() |
| `categories` | GET /api/v2/categories | RealHomeRepository.fetchCategories() |
| `categorySeries` | GET /api/v2/categories/{code}/series | APIEndpoint 已定义，分类映射待后端提供稳定 code 后对接 |

## Task14 字段消费

| 后端字段 | iOS DTO | DramaItem 映射 | 旧默认值 | 新来源 |
|----------|---------|---------------|---------|--------|
| `view_count` | FeedCardDTO.viewCount: Int64? | Int(card.viewCount ?? 0) | 0 (Gap) | 后端真实值 |
| `category` | FeedCardDTO.category: String? | card.category ?? tags.first | tags.first | 后端真实值 |
| `region_tag` | FeedCardDTO.regionTag: String? | card.regionTag | nil (Gap) | 后端真实值 |
| `language_tag` | FeedCardDTO.languageTag: String? | card.languageTag ?? contentLanguage | contentLanguage (近似) | 后端真实值 |
| `episode_count` | FeedCardDTO.episodeCount: Int? | card.episodeCount ?? 0 | 0 (Gap) | 后端真实值 |
| `free_episode_range` | FreeEpisodeRangeDTO {start,end} | start...end ClosedRange | nil (Gap) | 后端真实值 |

## use_real_api=true 注入

| Repository | Mock | Real |
|-----------|------|------|
| homeRepository | MockHomeRepository | RealHomeRepository |
| searchRepository | MockSearchRepository | **RealSearchRepository** (Task15 新增) |
| detailRepository | MockDetailRepository | RealDetailRepository |
| 其余 | Mock | Mock（不变） |

## 分类映射 Gap

iOS `DramaCategory` 枚举使用中文名（如 "现代言情"、"古装"），后端 `rs_categories.code` 使用英文 code。当前无稳定映射表。`fetchDramas(category:)` 对非 `.all` 的分类仍走 For You 降级。建议后续 Task 补充后端分类 code 列表或 iOS 端建立映射。

## 验证

```bash
$ git diff --check
（通过）

$ xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
    -destination 'generic/platform=iOS Simulator' build
失败：iOS 26.5 platform 未安装（Xcode > Settings > Components）。
本机 Xcode 环境不完整，非代码问题。
```

## ECC 使用记录

| ECC 能力 | 可用？ | 说明 |
|----------|--------|------|
| `/plugin list ecc@ecc` | ❌ | VSCode 扩展环境不支持 |
| API/backend-patterns（手工） | ✅ | 对照 `IOS_API_CONTRACT_V1.md` 验证 query 参数名一致性 |
| java-reviewer（手工） | ✅ | 审计 FeedCardDTO 与后端 DTO 字段对齐 |

## 未完成事项

1. **xcodebuild 编译验证**：本机无 iOS 26.5 platform 和 CoreSimulator.framework，需在配备完整 Xcode 环境的机器上验证
2. **分类 code 映射**：iOS `DramaCategory` 中文名 ↔ 后端 `rs_categories.code` 无稳定映射，分类搜索仍降级为 For You
3. **RankViewModel 未拆分协议**：当前仍用 `HomeRepositoryProtocol`，后续可拆分 RankingRepositoryProtocol 独立注入
