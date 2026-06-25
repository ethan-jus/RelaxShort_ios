# CC Task27 R4 - Fix R3 Blockers Only

Date: 2026-06-24
Owner: CC
Reviewer: Codex

## Read First

- `docs/CODEX_REVIEW_TASK27_R3.md`
- Current iOS diff
- Current backend diff

R4 is a blocker fix pass. Do not expand UI scope.

## Scope

Fix only:

1. Delivery report mismatch.
2. Backend V7 ranking seed and Flyway application.
3. Rankings API 500 / empty data.
4. Home API empty sections or clearly documented fallback.
5. Home search header height/position alignment with Search page.
6. Home Categories tab UI and backend-driven filter config.
7. HomeView Categories filter state cleanup.
8. Home top spacing magic formula naming/cleanup.

Do not modify:

- PlayerKit
- playback behavior
- Series player UI
- New / Anime / VIP / Original+ tabs
- backend production schema beyond the dev seed migration

Important product constraint:

- Current Home/Rankings/Categories testing must use real backend API data.
- Do not add new iOS mock fallback to hide backend/API defects.
- Old mock data/code should not be used by Home/Rankings/Categories real-mode smoke. Full deletion of all legacy mock infrastructure is broader than R4 and should be handled as a separate cleanup task after these screens pass real API smoke.

## A. Delivery Report

Rewrite `docs/TASK27_DELIVERY_REPORT.md`.

The report must match actual files changed:

- iOS files changed
- backend files changed
- verification commands
- exact API smoke results
- known limitations

Do not leave the R2 report in place.

## B. Backend V7 Ranking Seed

Current V7 problem:

- Uses one `INSERT` per row.
- Uses `NOW(3)` per row.
- Local DB has 12 rows per ranking group but 12 distinct `snapshot_at` values.
- `RankingService.fetchLatest` loads only rows matching the newest exact `snapshot_at`.

Required:

- Fix `app-server/v2/src/main/resources/db/migration/V7__dev_seed_ranking_snapshots_from_real_media.sql`.
- All rows in the same logical seed batch should share one fixed timestamp.
- Prefer a deterministic literal timestamp, for example:

```sql
'2026-06-24 00:00:00.000'
```

- Seed `popular`, `trending`, and `new`.
- Seed both `en` and `zh-Hans` only if matching feed card snapshots exist.
- Use `country_code = 'GLOBAL'`.
- Do not use `NOW(3)` separately for each row.
- Because `rs_ranking_snapshots` has no unique key, do not rely on `ON DUPLICATE KEY UPDATE` for idempotency. Use one of:
  - `DELETE FROM rs_ranking_snapshots WHERE ...` for the seed dimensions, then `INSERT`.
  - Or add a safe unique key in a separate deliberate migration only if Codex/user approves. For R4, prefer delete+insert.

Important local cleanup:

- Current local DB may already contain manually applied V7-like rows while Flyway only records V1-V6.
- R4 delivery must explain how to repair local dev DB cleanly:
  - either restart/recreate dev DB volume if acceptable, or
  - manually delete bad rows and run Flyway with V7, then verify `flyway_schema_history` includes `7`.

Do not silently rely on manual import outside Flyway.

## C. Rankings API Smoke

Required command:

```bash
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
```

Acceptance:

- HTTP 200.
- `data.items` count is greater than 1.
- Items contain real V5 media card data.

Also smoke:

```bash
curl 'http://127.0.0.1:8080/api/v2/rankings?type=trending&content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/rankings?type=new&content_language=en&country_code=GLOBAL'
```

If the endpoint still returns 500, inspect backend logs and fix the real cause.

Ranking test data source:

- Use real legacy/V5 media series that already exist in the dev database.
- If needed, extract additional usable series ids/metrics from `old-sql/relax_db_v5.sql`, but do not commit the old SQL dump itself.
- Seed through Flyway/dev migration only, not by hand-editing the local DB.
- The iOS Rankings tab must show real `/api/v2/rankings` response data, not local mock ranking data.

## D. Home API / Popular Data Path

Current smoke:

```bash
curl 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL'
```

returns 200 but empty sections.

Required:

- Decide and document one truthful R4 behavior:
  - Prefer: fix backend Home seed/logic so Popular has real section items.
  - Acceptable short-term: iOS Popular documents and uses existing fallback path from `/api/v2/home` to `/api/v2/feed/for-you`, but report must say Home endpoint sections are empty and fallback supplies cards.
- Do not claim `/api/v2/home` is fully integrated if sections are empty.

## E. HomeView Cleanup

Search header:

- Home search bar height must match the Search page search bar visual height.
- Current Search page bar lives in `RelaxShort/Views/Search/SearchView.swift` as the toolbar `searchBar`.
- Current Home bar lives in `DramaBoxSearchHeaderView` inside `HomeView.swift` and uses `btnH = 34`.
- R4 should establish one shared search chrome metric/component or, at minimum, use the same height, font, horizontal padding, icon sizing, background, and corner radius values for both.
- Home search row is still too far from the screen top in simulator. Fix the vertical position with a clear safe-area contract:
  - no negative padding
  - no unexplained `safeAreaInsets.top - 34` formula
  - compact gap between status bar and search row, matching the DramaBox Home reference
  - search row, crown, and gift stay vertically aligned

Popular/Home real data:

- Do not use `MockData.homePopular`, `MockData.homeVipRecommendations`, or other local mock arrays for Home real-mode smoke.
- If real API data is missing, fix or document the backend endpoint/data seed instead of hiding it in iOS.

Categories:

- Keep one Genre row only.
- Delete the Audio row from the Categories filter UI. The user does not need it.
- Match the DramaBox Categories reference more closely:
  - rows are text-first filter rows, not heavy capsule chips for every option
  - the selected/default item is a pink rounded pill
  - unselected items are muted text with generous horizontal spacing
  - grid begins after the filter block with clear spacing
  - no cramped labels or duplicated rows
- Replace raw `@State String` properties with a small typed model or selected option dictionary.
- Do not keep hard-coded Region/Language/Genre options buried in `HomeView`.
- Region and language/content options should come from backend database/config:
  - countries/regions from backend country/locale data such as `rs_countries` or an explicit config endpoint
  - supported content languages from backend language/config data such as `rs_languages`, locale rules, or content availability
  - genres/themes from backend categories/tags where available, not hard-coded iOS literals
- If the backend endpoint does not yet expose the needed filter groups, R4 must document the required API contract and avoid pretending the current hard-coded UI is production-ready.
- Genre row must continue to use `/api/v2/categories` and `/api/v2/categories/{code}/series`.
- Region/language selection must be wired to real request parameters where currently supported, such as `country_code` and `content_language`; unsupported filters must be marked as pending API contract, not fake filtered locally.

Top spacing:

- Replace:

```swift
.padding(.top, max(8, geo.safeAreaInsets.top - 34))
```

with named metrics/intent.

Example direction:

```swift
private enum HomeChromeMetrics {
    static let topGap: CGFloat = 8
    static let tabVerticalPadding: CGFloat = 14
}
```

If using a safe-area derived formula, explain it in the name/comment and bound it clearly. Avoid unexplained constants.

Mock removal boundary:

- Remove mock fallback usage from Task27 Home/Rankings/Categories paths where it affects real API testing.
- Do not attempt a repo-wide mock deletion inside R4 unless all affected screens/tests are updated and verified. Create a follow-up cleanup task for global mock removal after Home/Rankings/Categories real API smoke passes.

## F. Verification

iOS:

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

Backend:

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

DB verification:

```sql
SELECT version, success FROM flyway_schema_history ORDER BY installed_rank;
SELECT ranking_type, language_code, country_code,
       COUNT(*) cnt, COUNT(DISTINCT snapshot_at) snapshots
FROM rs_ranking_snapshots
GROUP BY ranking_type, language_code, country_code;
```

Acceptance:

- Flyway records V7 success.
- Each seeded ranking group has `snapshots = 1`.
- Rankings API returns 200 with multiple items.
- Home search bar height matches Search page search bar height/spec and is not too far from top.
- Categories removes Audio, uses real backend category data, and documents/wires region/language backend config instead of hard-coded-only UI.
- Home/Rankings/Categories real-mode smoke does not rely on local mock data.
- Delivery report matches real commands and diff.
