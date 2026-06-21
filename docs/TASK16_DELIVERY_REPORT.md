# Task 16 Delivery Report: iOS Real API Phase 3

**Branch**: `task/task16-ios-real-api-phase3`
**Commits**: R1 `06a05fb`, R2 `2f42c00`, R3 `baec6cf`, R4 `65473d2`
**Date**: 2026-06-21

## Summary

Task16 completes the iOS real API Phase 3 scope:

- Search supports real cursor pagination, load-more UI, error state, and mock pagination parity.
- Search Default can use the real search default endpoint while preserving mock behavior.
- Ranking uses repository protocol routing for `popular` / `trending` / `new`.
- Home Categories UI now consumes backend category data through `HomeCategory`, not hard-coded `DramaCategory.allCases`.
- Category fallback is safe: local fallback categories never send Chinese enum raw values as backend category codes.

## Final File Scope

| Area | Files |
|------|-------|
| Search | `SearchViewModel.swift`, `SearchView.swift`, `SearchDefaultViewModel.swift`, `SearchDefaultView.swift`, `MockAPIRepository.swift` |
| Ranking | `RankViewModel.swift`, `RepositoryProtocols.swift`, `RealHomeRepository.swift` |
| Categories | `HomeCategory.swift`, `HomeViewModel.swift`, `HomeView.swift`, `RealHomeRepository.swift`, `RepositoryProtocols.swift` |
| Project/docs | `RelaxShort.xcodeproj/project.pbxproj`, `AGENTS.md`, `docs/TASK16_DELIVERY_REPORT.md` |

## Search Behavior

| State | Behavior |
|------|----------|
| New query | Resets pagination, requests first page with `cursor=nil` |
| Scroll bottom | `loadMoreIfNeeded(currentItem:)` triggers next page when `hasMore=true` |
| Query change | Resets pagination before the new request |
| Network failure | Keeps existing results and exposes `errorMessage` |
| Mock mode | Uses cursor-as-page pagination with `hasMore` parity |

## Ranking Behavior

| iOS category | Backend type | Path |
|--------------|--------------|------|
| Hot | `popular` | `fetchRankings(type: "popular")` |
| Trending | `trending` | `fetchRankings(type: "trending")` |
| New | `new` | `fetchRankings(type: "new")` |

Mock mode uses the protocol default implementation for local sorting. Real mode uses `RealHomeRepository.fetchRankings(type:)`.

## Categories Behavior

| Mode | Behavior |
|------|----------|
| Real categories load succeeds | `fetchHomeCategories()` calls `/api/v2/categories`; UI displays backend `localizedName`; taps call `/api/v2/categories/{code}/series` with backend `code` |
| Real categories load fails | Falls back to local `DramaCategory` values; taps use local filtering only |
| Mock mode | Uses local `DramaCategory` fallback through protocol defaults |
| Initial load | After categories load, index `0` is selected and `loadCategoryDramas(for: categories[0])` is called, so highlight and content stay aligned |

The final R4 behavior does not rely on localized name matching to discover backend category codes. Backend category code is carried by `HomeCategory.code`.

## R4 Fixes

| Issue | Fix |
|------|-----|
| Default highlighted category and content could diverge | `loadData()` now loads `categories[0]` after category list setup |
| Fallback category code could be treated as a backend code | `loadCategoryDramas` checks `localCategory` before real repository routing |
| Delivery report contained stale R2/R3 facts | Report was rewritten around final R4 behavior |
| ViewModel still casts to `RealHomeRepository` | Accepted as a P2 follow-up; no behavior regression |

## Verification

```bash
git diff --check
# PASS

xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
# ** BUILD SUCCEEDED **
```

Static checks were also used to verify that preview/mock hits are not production entry regressions.

## Remaining Follow-ups

1. Move `fetchDramasByCategoryCode(code:)` into `HomeRepositoryProtocol` to remove `HomeViewModel`'s concrete `RealHomeRepository` cast.
2. Run a real backend smoke test with `use_real_api=true` and the configured API base URL.
3. If backend later exposes separate Search Default榜单, split the current real Search Default single-source mapping.
