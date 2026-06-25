# Codex Review - Task27 R2 Home UI and ShareSheet

Date: 2026-06-24

Reviewed state:

- Task brief: `docs/CC_TASK27_R2_HOME_SHARE_FIXES.md`
- Delivery report: `docs/TASK27_DELIVERY_REPORT.md`
- Current diff: 7 Swift files, `+131/-92`

## Verdict

Task27 R2 is not accepted yet. It builds, but it still has UI architecture and responsive layout issues that should be fixed before merge.

## Findings

### Addendum - User simulator screenshots after R2

User screenshots from 2026-06-24 add three concrete R3 requirements:

- Home search/header is now too low. The R2 fix likely double-counts top safe area by applying `geo.safeAreaInsets.top` directly inside this layout.
- Rankings filter pills wrap to two lines. The DramaBox reference keeps the three ranking pills single-line and evenly distributed.
- Rankings shows no data. Backend V5 real-media seed does not populate `rs_ranking_snapshots`, so `/api/v2/rankings` can be empty even when Home/For You has real cards.

R3 should focus on Popular and Rankings only, rather than widening changes across all Home tabs.

### P0 - Categories genre row is rendered twice

`RelaxShort/Views/Home/HomeView.swift` now renders `catGenreRow`, then immediately renders the old category `ScrollView` again:

- New row: lines around `catGenreRow`
- Old row: the block starting with `// Genre pill row`

Both rows use `viewModel.categories` and both call `viewModel.selectCategory(at:)`. This creates duplicated UI, duplicated interaction paths, and visual noise. R3 must remove the old row and keep one category selector.

### P0 - ShareSheet still does not guarantee filling the presented detent

`ShareSheet` is presented with `.height(420)`, but the root view only has:

```swift
.frame(maxWidth: .infinity)
.background(Color(hex: "#1C1C1E"))
```

It does not use `maxHeight: .infinity`. This can still leave unstyled sheet area inside the detent, which is exactly the visual defect R2 was supposed to fix. R3 must make the sheet content own the full detent height with a single solid background.

### P0 - Share platform row is not responsive

The platform row is a fixed `HStack`:

- 5 items
- each item uses a 72 pt icon and 72 pt label width
- spacing is 18 pt
- horizontal padding is 12 pt

That is wider than many iPhone widths and there is no `ScrollView` or adaptive sizing. On iPhone mini/SE it will clip or compress badly. R3 must either restore a horizontal `ScrollView` or compute adaptive item width/icon size from available width.

### P1 - Category filters are hard-coded strings inside `HomeView`

R2 added:

```swift
@State private var catRegion = "All"
@State private var catAudio = "All"
@State private var catAccess = "All"
@State private var catTheme = "All"
@State private var catSort = "Trending"
```

and hard-coded option arrays such as `["All","US","Korea","China"]`.

This is acceptable only as a short-lived UI prototype. It is not acceptable as the long-term data model. The backend already has `rs_categories`, `rs_category_localizations`, `rs_languages`, `rs_locale_rules`, `rs_home_tabs`, and `rs_home_sections`. R3 should at least extract these options into typed local models and document that the next API contract should make them backend-driven. Do not bury them as magic strings in the View.

### P1 - Rank category display strings are tied to enum raw values

`RankCategory.rawValue` was changed from Chinese strings to English display strings. The app already has localization files, so display text should not live in enum raw values. R3 should separate:

- stable enum case / API type
- localized display title

This avoids breaking future Chinese/Japanese/Korean/Arabic UI and keeps API mapping explicit.

### P1 - ShareSheet presentation styling is duplicated in two callers

Both `RecommendView` and `SeriesPlayerView` now repeat:

```swift
.presentationDetents([.height(420)])
.presentationDragIndicator(.hidden)
.presentationCornerRadius(26)
```

This is a small duplication today, but this sheet is shared UI. R3 should centralize it in a small helper/modifier, and avoid scattering raw presentation magic values.

### P1 - Home API integration remains incomplete for multiple tabs

R2 keeps Popular/New/Anime/VIP/Original+ on the existing front-end derived data. Current `HomeViewModel` fetches `repository.fetchDramas(category: .all)`, and in real mode `RealHomeRepository` pulls the first non-empty `/api/v2/home` section or falls back to For You. Then the client derives:

- `fixedDramas`
- `dramasForNewTab`
- `dramasForAnimeTab`
- `dramasForOriginalPlusTab`

This is not full Home tab API integration. The backend already exposes Home tabs/sections from `rs_home_tabs` and `rs_home_sections`; iOS should eventually render by tab/section code instead of treating the first section as the whole Home dataset.

This does not need to be fully solved in R3 if the UI is still being finalized, but the delivery report must not imply those tabs are API-complete.

### P2 - Too many layout constants are embedded inline

Examples:

- `tabBar.padding(.vertical, 14)`
- Share detent `420`
- share corner radius `26`
- share icon size `72`
- filter label width `52`
- filter chip padding values

Some numeric constants are normal in UI code, but Task27 should not scatter them across views. R3 should group them in private metric enums/structs inside each component, or use existing `DB` / `DT` tokens where they match.

## What Can Be Kept

- Removing the negative `topLift` direction is correct.
- The share sheet visual direction is better than R1.
- Ranking row moving toward rounded dark blocks is directionally correct.
- Categories multi-row filter matrix direction is correct, but implementation needs cleanup.

## Verification

Ran:

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

Results:

- `git diff --check`: clean
- `xcodebuild`: `BUILD SUCCEEDED`

No simulator visual smoke was performed during this review.
