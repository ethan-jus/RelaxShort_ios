# Task27 R5 Codex 复审结论

日期：2026-06-24
结论：部分通过，不能直接提交；Codex 已补一个后端 P0 根因修复，Categories 进入 R6 小范围返工。

## 已确认可接受

1. Home 搜索栏顶部位置相比 R4 已修正。
   - R5 删除了重复叠加 `geo.safeAreaInsets.top` 的写法。
   - 当前为 `HomeMetrics.chromeTopGap = 8`，用户模拟器观感也确认“好像可以”。
2. `MockData.homePopular` 对 Categories/Popular 的显式兜底已删除。
3. V7 当前本地库已经进入 Flyway：

```sql
SELECT version, success FROM flyway_schema_history ORDER BY installed_rank;
-- 当前已有 version=7 success=1
```

## P0：Rankings 500 根因和修复

R5 交付后，用户在 Xcode 仍看到：

```text
GET http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL
RankViewModel.loadData failed: badStatus(500)
```

Codex 在 18080 临时后端实例复现并抓到异常栈：

```text
BadSqlGrammarException
SQL: SELECT id,ranking_type,language_code,country_code,rank_position AS rank,...
Cause: MySQL syntax error near 'rank,series_id...'
```

根因：

- `RankingSnapshot` Java 字段叫 `rank`。
- MyBatis-Plus 自动生成 `rank_position AS rank`。
- `rank` 在 MySQL 8 是敏感关键字，导致 SQL 语法错误。

Codex 已在后端补修：

- `RankingSnapshot.rank` 改为 `rankPosition`。
- `RankingService.orderByAsc(RankingSnapshot::getRank)` 改为 `getRankPosition`。

验证结果：

```bash
mvn test
# 240 tests, 0 failures, 0 errors
```

临时端口 18080 验证：

```text
popular  HTTP 200  items 12
trending HTTP 200  items 12
new      HTTP 200  items 12
```

注意：

- 用户当前 App 打的是 8080。
- 8080 上的 IDEA 后端需要重启到最新代码后，模拟器 Rankings 才会有数据。

## P1：Categories 需要 R6 小范围增强

R5 把 Categories 简化成一行分类，这比 R4 的硬编码矩阵干净，但还不满足当前产品要求。

用户最新确认的方向：

1. 不追求完整 DramaBox 复杂筛选。
2. 保留简单、清楚的多行筛选。
3. 第一行：语言/地区内容筛选。
   - `All`
   - `Local`
   - `Chinese`
   - `Korean`
   - `Japanese`
   - `Spanish`
   - `Others`
   - `English`
4. 第二行：分类，来自后端 `/api/v2/categories`。
5. 第三行可做：付费筛选。
   - `All`
   - `Paid`
   - `Members Only`
   - `Free`

后端现状：

- 已有 `rs_languages`、`rs_countries`、`rs_locale_rules` 基础表。
- 当前没有专门的 Home filter config API。
- iOS 现有 `/api/v2/categories` 只负责分类，不负责语言/地区/付费筛选组。

建议 R6：

- 不再大改 Home 总体结构。
- 抽一个轻量 `CategoryFilterRowView`。
- 第一行语言/地区先用后端已支持语言映射到 `content_language` 请求参数。
- 第二行分类继续用 `/api/v2/categories` 和 `/api/v2/categories/{code}/series`。
- 第三行付费筛选如果后端接口暂不支持，不要本地假过滤；先做 UI 状态和 API contract 记录，或者只在真实字段足够时过滤。

## 结论

R5 不能按原样提交，因为交付报告里还写 rankings 500。但 Codex 已定位并修复后端 500 根因。下一步：

1. 重启 IDEA 后端 8080，验证 Rankings 是否变 200。
2. 让 CC 执行 R6：只做 Categories 三行筛选和报告更新。
3. R6 通过后，再统一提交 Task27。
