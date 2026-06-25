# Task27 R6 — Final Delivery Report

> 日期：2026-06-24

## R6 修改文件（8 files, +218/-203）

| 文件 | 变更 |
|------|------|
| `Views/Home/HomeView.swift` | Categories 三行筛选：Language（All/Local/Chinese/Korean/Japanese/Spanish/English）、Genre（All + `/api/v2/categories`）、Payment（All/Paid/Members Only/Free）；`CategoryFilterOption` 模型 + `catFilterRow` 复用；粉色选中 pill + 灰色未选中；`HomeMetrics` enum（chromeTopGap=8, tabVerticalPadding=14）；删除 MockData 兜底 |
| `Models/RankDrama.swift` | `RankCategory` 分离 `apiType`/`title` |
| `ViewModels/RankViewModel.swift` | 使用 `category.apiType` |
| `Views/Rank/RankView.swift` | pill 均匀分布 + `.lineLimit(1)` + 删除 gradientBar |
| `Views/Rank/RankCardView.swift` | 圆角卡片 + flame.fill + 无 chevron |
| `Views/RecommendPage/ShareSheet.swift` | ShareMetrics + shareSheetPresentationStyle + 填充 detent + 响应式 ScrollView |
| `Views/RecommendPage/RecommendView.swift` | shareSheetPresentationStyle() |
| `Views/RecommendPage/SeriesPlayerView.swift` | 同上 |

## 验证

| 命令 | 结果 |
|------|------|
| `xcodebuild ... iPhone 17 Pro Max` | ✅ BUILD SUCCEEDED |
| `git diff --check` | ✅ clean |
| `/api/v2/rankings?type=popular` | ✅ 200, 12 items |
| `/api/v2/rankings?type=trending` | ✅ 200, 12 items |
| `/api/v2/rankings?type=new` | ✅ 200, 12 items |

> Rankings 500 根因：`RankingSnapshot.rank` 字段名与 `rank_position` 列不匹配，已由 Codex 后端修复。

## Categories 三行筛选

| 行 | 数据来源 | 参数 | 状态 |
|----|---------|------|------|
| Language | iOS 语言码映射 | `content_language` | 本地映射，待后端 filter config 接口 |
| Genre | `/api/v2/categories` | `category_code` | 真实后端 ✅ |
| Payment | iOS 本地定义 | monetization 字段 | 前端过滤，待后端补 API 参数 |

## 已知限制

- Language 行未与后端联动（需 filter config API）
- Payment 行为前端过滤（需后端补付费筛选参数）
- New/Anime/VIP/Original+ 保持原实现
