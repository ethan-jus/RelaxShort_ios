# Codex Review - Task27 Home UI/API Polish

Date: 2026-06-24

Reviewed state:

- Base task brief: `docs/CC_TASK27_HOME_UI_API_POLISH.md`
- Current uncommitted files:
  - `RelaxShort/Models/RankDrama.swift`
  - `RelaxShort/Views/Rank/RankCardView.swift`
  - `RelaxShort/Views/Rank/RankView.swift`
  - `docs/TASK27_DELIVERY_REPORT.md`

## Verdict

Task27 is not accepted. It needs R2 rework.

The actual diff only modifies Rankings text/icon/header. It does not implement the required Home shell spacing, Popular, New, Categories, Anime, VIP, or Original+ polish from the task brief.

## Findings

### P0 - Delivery report claims work that is not in the diff

`docs/TASK27_DELIVERY_REPORT.md` states Popular, New, Categories, Anime, VIP, Original+ were completed. The actual git diff only touches:

- `RelaxShort/Models/RankDrama.swift`
- `RelaxShort/Views/Rank/RankCardView.swift`
- `RelaxShort/Views/Rank/RankView.swift`

No `HomeView.swift`, `ContentGridView.swift`, or `HomeViewModel.swift` changes are present. The report is therefore inaccurate and cannot be used as acceptance evidence.

### P0 - Home shell spacing was not fixed

`RelaxShort/Views/Home/HomeView.swift` still uses:

```swift
let topLift = min(max(geo.safeAreaInsets.top - 34, 0), 18)
...
.padding(.top, -topLift)
```

This intentionally pulls the search/header area upward. The user observed that the search bar is too close to the screen top, the search-to-tab spacing is poor, and tab-to-content spacing has no breathing room. This code remains unchanged.

### P0 - Categories still does not match the required multi-row filter matrix

`HomeView.swift` still renders one horizontal category pill row backed by `viewModel.categories`. The DramaBox reference and task brief require a multi-row filter matrix:

- Region
- Audio/Text
- Access
- Genre
- Theme
- Sort

Only the genre/category row needs backend category API integration. Other rows can be UI-only state. This was not implemented.

### P1 - Popular/New/Anime/VIP/Original+ were not visually polished

The task brief required visible Home tab UI work beyond Rankings. The current diff contains no changes to:

- `RelaxShort/Views/Home/HomeView.swift`
- `RelaxShort/Views/Home/ContentGridView.swift`
- Shared Home components

The existing implementation remains the same as before Task27.

### P1 - Rankings row still does not match reference spacing/card structure

The Ranking row changed the icon to `flame.fill`, but it still uses:

- Row background equal to page background.
- Dividers between rows.
- A right chevron.

The reference has separate dark row blocks with rounded corners, no visible chevrons, large rank number, thumbnail, title/tags, and flame count on the right.

### P1 - Share sheet is visually below target quality

This is adjacent to Task27 but user explicitly raised it now. Current `ShareSheet` issues:

- `.presentationDetents([.medium])` creates a large translucent blank area above the content.
- Content background does not fill the presented sheet.
- Platform buttons are too small.
- SF Symbols do not resemble recognizable share channels enough.
- Copy Link is pushed off to the side instead of being clearly visible as the fifth item.
- Panel height, corner radius, title/close placement, and reward pill spacing do not match the DramaBox reference.

This should be fixed in R2 alongside Home polish because it is a visible UI quality regression.

## What Can Be Kept

- The `RankCategory` English labels are directionally correct for the current English UI.
- Removing the Rankings gradient bar is directionally correct.
- Replacing the play icon with `flame.fill` is directionally correct, but row layout still needs work.

## Required R2 Direction

Use `docs/CC_TASK27_R2_HOME_SHARE_FIXES.md` for implementation. The R2 task must:

- Correct the delivery report.
- Fix Home top spacing.
- Implement the Categories multi-row filter matrix.
- Polish Popular/New and the remaining Home tabs enough that they no longer look untouched.
- Rebuild Rankings row as separate rounded dark blocks.
- Rebuild ShareSheet as a real DramaBox-style bottom sheet.

## Verification

Ran:

```bash
git diff --check
```

Result: clean.

Build was not rerun during this review because Task27 is functionally incomplete and needs rework before acceptance.

