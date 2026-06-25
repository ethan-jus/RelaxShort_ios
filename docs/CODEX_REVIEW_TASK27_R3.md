# Codex Review - Task27 R3

Date: 2026-06-24

Reviewed projects:

- iOS: `/Users/ethan/myspance/relaxshort/ios/v1.0.0`
- Backend: `/Users/ethan/myspance/relaxshort/app-server/v2`

## Verdict

Task27 R3 is not accepted.

The iOS build and backend tests pass, but the real Home/Rankings API smoke does not pass. The delivery report is also stale and does not describe the actual R3 diff.

## Findings

### P0 - Delivery report is still the R2 report

`docs/TASK27_DELIVERY_REPORT.md` still says:

- R2
- 7 files
- no backend changes
- no V7 migration

Actual current state is:

- iOS: 8 modified Swift files
- backend: `V7__dev_seed_ranking_snapshots_from_real_media.sql`

This report cannot be used as acceptance evidence.

### P0 - `/api/v2/rankings` returns 500 in local dev

Command:

```bash
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
```

Result:

```json
{
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "Internal server error"
  }
}
```

R3 required Rankings API smoke to return real data. This is not complete.

### P0 - V7 ranking seed creates one timestamp per row, not one snapshot batch

`V7__dev_seed_ranking_snapshots_from_real_media.sql` inserts each ranking row with a separate `NOW(3)`.

Backend `RankingService.fetchLatest` first selects the newest `snapshot_at`, then loads rows matching that exact timestamp. Local DB confirms this breaks the intended batch:

```sql
SELECT ranking_type, language_code, country_code,
       COUNT(*) cnt, COUNT(DISTINCT snapshot_at) snapshots
FROM rs_ranking_snapshots
GROUP BY ranking_type, language_code, country_code;
```

Observed:

- `popular/en/GLOBAL`: `cnt=12`, `snapshots=12`
- latest snapshot rows for `popular/en/GLOBAL`: `1`

All rows for the same `ranking_type + language_code + country_code` batch must share the same `snapshot_at`, otherwise Rankings can return only one row or fail downstream.

### P0 - V7 is not recorded in Flyway history, but ranking rows exist

Local DB:

```sql
SELECT version, success FROM flyway_schema_history ORDER BY installed_rank;
```

Observed: V1-V6 only. V7 is not recorded.

However, `rs_ranking_snapshots` contains V7-like rows. That means data appears to have been manually imported or applied outside Flyway. This is not acceptable for a migration-delivered seed.

### P1 - `/api/v2/home` returns empty sections

Command:

```bash
curl 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL'
```

Result: 200, but every tab has empty `sections`.

This means Popular is still not API-smoked against real Home data. The iOS may be displaying data through fallback behavior, but Task27 R3 required documenting the actual source path and confirming the endpoint.

### P1 - Popular tab UI was not materially changed

`HomeView.popularContent` still renders the existing:

- `MarketingGrid`
- `YouMightLikeSection`

There is no clear R3 diff showing Popular-specific polish against the DramaBox Popular reference. This may still be visually acceptable after user simulator review, but the code diff does not demonstrate the requested targeted Popular work.

### P1 - Categories cleanup is incomplete

The duplicated Genre row is removed, which is good.

But the filter state is still five raw `@State String` properties plus inline option arrays in `HomeView`:

- `catRegion`
- `catAudio`
- `catAccess`
- `catTheme`
- `catSort`

R3 asked for a small typed local model and a comment that non-Genre rows are a temporary UI prototype pending backend-driven filter config.

### P1 - Home top spacing still uses a derived magic formula

`HomeView` now uses:

```swift
.padding(.top, max(8, geo.safeAreaInsets.top - 34))
```

This may visually improve the screenshot, but it is still a magic formula tied to one simulator. R3 asked for an explicit Home chrome spacing metric/contract. At minimum, this should be named and bounded in a private metrics block so the intent is clear.

### P2 - ShareSheet is improved but still has dense one-line code

The shared presentation helper and full-height background direction are correct.

However, several view expressions were compressed into long single lines. This is harder to maintain in SwiftUI and should be cleaned if the file is touched again.

## Verification Performed

iOS:

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

Result:

- `git diff --check`: clean
- `xcodebuild`: `BUILD SUCCEEDED`

Backend:

```bash
git diff --check
mvn test
```

Result:

- `git diff --check`: clean
- `mvn test`: `240 tests, 0 failures, 0 errors`

API smoke:

```bash
curl 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
```

Result:

- Home: 200 but empty sections
- Rankings: 500 `INTERNAL_ERROR`

## Required R4 Fixes

1. Rewrite `docs/TASK27_DELIVERY_REPORT.md` for the actual R3/R4 state.
2. Fix V7 so Flyway applies it normally.
3. Use one fixed `snapshot_at` per ranking batch.
4. Make `/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL` return 200 with multiple items.
5. Make `/api/v2/home?content_language=en&country_code=GLOBAL` either return real Popular sections or document and fix the iOS fallback path honestly.
6. Clean `HomeView` Categories filter state into a typed local model.
7. Replace Home top spacing magic formula with a named metric/contract.
