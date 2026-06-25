# CC Task27 R3 - Fix R2 Review Issues

Date: 2026-06-24
Owner: CC
Reviewer: Codex

## Read First

- `docs/CC_TASK27_R2_HOME_SHARE_FIXES.md`
- `docs/CODEX_REVIEW_TASK27_R2.md`
- Current `git diff`

R2 builds but is not accepted. R3 should be a cleanup/fix pass, not a new feature pass.

## Updated User Feedback

User simulator screenshots on 2026-06-24 showed additional R3 requirements:

- Home search header is now too low and too far from the top.
- Rankings tab has no real test data.
- Rankings filter pills wrap to two lines; reference keeps each pill single-line.
- Rankings filter pills should be three evenly distributed controls.
- Do not spread work across every Home tab in one pass. For R3, focus on Popular and Rankings only, plus the cleanup defects already found in R2.

Reference files:

- `design-reference/dramabox/02_home/tab_Popular.JPG`
- `design-reference/dramabox/02_home/tab_Rankings.PNG`

## Scope

Fix:

1. Categories duplicated row and local filter model cleanup.
2. ShareSheet detent/background/responsive layout.
3. RankCategory display/API separation.
4. Shared presentation/style constants.
5. Home top search/header vertical position.
6. Popular tab UI and API smoke.
7. Rankings tab UI and API smoke, including dev test data if backend ranking snapshots are missing.
8. Delivery report accuracy.

Do not modify:

- PlayerKit
- Playback behavior
- API DTO fields unless backend smoke proves an existing DTO cannot decode the current response
- New / Anime / VIP / Original+ implementation beyond report wording

Backend change allowance:

- R3 may touch `app-server/v2` only to add a dev seed migration for ranking snapshots if `/api/v2/rankings` is empty because local MySQL lacks `rs_ranking_snapshots`.
- Do not modify existing applied migrations. Add a new migration such as `V7__dev_seed_ranking_snapshots_from_real_media.sql`.
- Do not edit `old-sql/relax_db_v5.sql`; it is local reference only.

## A. Categories Cleanup

Current bug: `HomeView.swift` renders `catGenreRow` and then still renders the old `viewModel.categories` row.

Required:

- Remove the old duplicated genre row.
- Keep exactly one Genre row.
- Genre row must continue to use `viewModel.categories` from `/api/v2/categories` in real mode.
- Genre selection must continue to call `viewModel.selectCategory(at:)`.
- Category loading/error/empty states must continue to work.

Local filter rows:

- Region / Audio / Access / Theme / Sort may remain local UI-only for now.
- Do not keep raw string state and option arrays scattered directly in `HomeView`.
- Create a small local typed model, for example:

```swift
private struct HomeFilterOption: Identifiable, Equatable {
    let id: String
    let title: String
}

private struct HomeFilterGroup: Identifiable {
    let id: String
    let title: String
    let options: [HomeFilterOption]
}
```

- Store selected option by group id or a small dictionary, not five unrelated string properties.
- Add one concise comment that these non-Genre rows are a UI prototype and should become backend-driven after the Home/filter API contract is finalized.

Do not over-engineer this into a global module yet.

## B. Home Top Chrome Position

Current issue from simulator screenshot:

- Search header is too low, with too much empty black space between status bar and search row.
- Likely cause: `GeometryReader` layout plus `.padding(.top, geo.safeAreaInsets.top)` double-counts top safe area on this screen.

Required:

- Replace direct `.padding(.top, geo.safeAreaInsets.top)` with one explicit Home chrome spacing metric.
- Search row should sit comfortably below status bar / Dynamic Island, not glued to it and not far below it.
- Use a small bounded top gap, not the full safe-area inset twice.
- Avoid negative padding.
- Keep search row, VIP crown, and gift aligned on one row.
- Validate visually against the user screenshot and the DramaBox Popular reference:
  - status bar
  - compact gap
  - search/reward row
  - main Home tab row
  - content grid

## C. Popular Tab Focus

R3 should polish Popular before expanding to every Home tab.

Required:

- Keep Popular backed by real Home/feed data. Do not use hard-coded poster data.
- Make the top poster grid match the DramaBox direction:
  - 3 columns.
  - Poster images dominant.
  - Title below each poster.
  - Text should not overlap or spill on small screens.
  - Consistent horizontal gutters and vertical spacing.
- Confirm Popular content comes from current repository/API path:
  - iOS `HomeViewModel.loadData()`
  - real mode `RealHomeRepository`
  - backend `/api/v2/home` or documented fallback `/api/v2/feed/for-you`
- Delivery report must state which endpoint actually supplied Popular during smoke.

Do not redesign Coming Soon / You Might Like in R3 unless it is already present and trivially affected by spacing.

## D. Rankings UI and API Focus

Current issues from simulator screenshot:

- Rankings is empty.
- Three ranking filter pills wrap to two lines.
- Reference has three pill controls laid out evenly across the width.
- Unselected pills should not be cramped or multi-line.

Required UI:

- Three ranking pills are evenly distributed across the available width.
- Text stays single-line:
  - `Most Trending`
  - `Top Searched`
  - `New Releases`
- Use `.lineLimit(1)` and a minimum or equal-width layout instead of allowing wrap.
- Selected pill is filled pink.
- Unselected pills are outlined/muted.
- Ranking rows match the reference dark rounded blocks after data exists.

Required API/data smoke:

- Check `/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL`.
- If empty because local dev has no `rs_ranking_snapshots`, add a backend dev migration in `app-server/v2` to seed ranking snapshots from the V5 real media series.
- Seed all three ranking types needed by iOS:
  - `popular`
  - `trending`
  - `new`
- Use existing real media series ids from V5 seed.
- Use `language_code` values that local feed cards support, at minimum `en` and/or `zh-Hans` if available.
- Use `country_code = GLOBAL`.
- Do not fake ranking data in iOS to hide an empty backend.
- After seed, curl the rankings endpoint and record item count in the delivery report.

## E. ShareSheet Must Fill the Detent

Current issue: the sheet uses a fixed height presentation but the root content does not fill the height.

Required:

- In `ShareSheet`, root layout must use:

```swift
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
```

- The dark background must cover the full detent.
- No large transparent blank area inside the sheet.
- Keep the bottom sheet compact and dark.

## F. ShareSheet Responsive Platform Row

Current issue: fixed 5-item `HStack` can exceed small iPhone width.

Required:

- Either:
  - Use a horizontal `ScrollView` so five actions remain reachable on small screens, or
  - Use `GeometryReader` to compute adaptive item width and icon size.
- iPhone mini/SE width must not clip the first/last action.
- Copy Link must be reachable.
- Keep five actions:
  - Instagram
  - Snapchat
  - Facebook Messenger
  - WhatsApp
  - Copy Link
- Use label `Facebook Messenger`, not only `Messenger`, unless width forces two-line wrapping.

## G. Centralize ShareSheet Presentation Style

Current issue: `RecommendView` and `SeriesPlayerView` duplicate presentation modifiers.

Required:

- Add a small shared helper or `View` extension near `ShareSheet.swift`, for example:

```swift
extension View {
    func shareSheetPresentationStyle() -> some View { ... }
}
```

- Both presenters must use the same helper.
- Avoid hard-coded `420` and `26` in two files.

## H. RankCategory Display/API Separation

Current issue: enum raw values are display text.

Required:

- Make `RankCategory` store stable identity/API mapping separately from display title.
- Suggested shape:

```swift
enum RankCategory: CaseIterable, Identifiable {
    case hot
    case trending
    case new

    var id: String { apiType }
    var apiType: String { ... }       // popular / trending / new
    var title: String { ... }         // display string
}
```

- Update `RankViewModel.mapToRankingType` to use `category.apiType` or equivalent.
- Do not use localized display labels as API identifiers.
- Keep English display strings for now if full localization is not part of R3, but structure it so localization can be added cleanly.

## I. Magic Values

R3 does not need to remove every number, but do not scatter important layout values inline.

Required:

- Group ShareSheet sizes into a private metrics enum/struct:
  - detent height
  - corner radius
  - reward pill height
  - icon size
  - row spacing
- Group Categories filter row label width/chip spacing into private metrics or use existing tokens.
- Keep names readable; no excessive abstraction.

## J. Delivery Report

Update `docs/TASK27_DELIVERY_REPORT.md`.

It must say clearly:

- R3 fixes duplicated category row.
- R3 fixes Home search/header vertical position.
- R3 focuses Home work on Popular and Rankings only.
- Popular endpoint/data path verified.
- Rankings endpoint/data path verified, including backend seed migration if added.
- R3 improves ShareSheet full-height background and small-screen row behavior.
- R3 separates ranking API type from display title.
- New/Anime/VIP/Original+ remain existing implementations and are not API-complete.
- Home full tab API contract is a next-task item after UI direction is confirmed.

Do not claim simulator visual QA unless actually performed.

## Verification

Run from `/Users/ethan/myspance/relaxshort/ios/v1.0.0`:

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

If backend ranking seed is added, also run from `/Users/ethan/myspance/relaxshort/app-server/v2`:

```bash
mvn test
curl 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL'
curl 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL'
```

If you can run simulator manually, smoke:

- Home search row is not too high and not too low.
- Popular grid has real cards and good spacing.
- Rankings shows data.
- Rankings pills are single-line and evenly distributed.
- Home Categories shows one Genre row only.
- Genre selection loads data.
- Share sheet has no transparent blank region.
- Share actions are reachable on small and large widths.

## Acceptance

R3 passes when the diff is focused and cleaner than R2, Home top chrome is correctly positioned, Popular and Rankings are polished against the reference, Rankings has real API data, the duplicated Categories row is gone, the ShareSheet is responsive, and the report matches the actual diff.
