# CC Task27 - Home UI/API Polish

## Context

Repo: `/Users/ethan/myspance/relaxshort/ios/v1.0.0`

Current branch: `main`

Baseline commit before this task:

- `02e9d8a feat: polish series player controls`

Task26 For You and Series Player are already accepted by the user. Do not modify For You, Series Player, or PlayerKit unless a build error directly forces a tiny compatibility fix.

Codex inspected the DramaBox screenshots. CC cannot visually inspect screenshots reliably, so use the written requirements below instead of doing your own image comparison.

Reference screenshot paths:

- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Popular.JPG`
- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_new(不要子tab，和预约功能).PNG`
- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Rankings.PNG`
- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Categories.PNG`
- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Anime.JPG`
- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_VIP.JPG`
- `/Users/ethan/myspance/relaxshort/design-reference/dramabox/02_home/tab_Original+.JPG`

## Goal

Polish the Home tab UI and API wiring so the main Home tabs feel close to DramaBox while keeping the current RelaxShort architecture: SwiftUI views, `HomeViewModel`, `HomeRepositoryProtocol`, and `DependencyContainer` real/mock switching.

## Scope

Allowed files:

- `RelaxShort/Views/Home/HomeView.swift`
- `RelaxShort/Views/Home/ContentGridView.swift`
- `RelaxShort/Views/Rank/RankView.swift`
- `RelaxShort/ViewModels/HomeViewModel.swift`
- `RelaxShort/ViewModels/RankViewModel.swift`
- `RelaxShort/Core/Services/RepositoryProtocols.swift`
- `RelaxShort/Core/Services/RealHomeRepository.swift`
- `RelaxShort/Core/Services/MockAPIRepository.swift`
- Small shared UI helpers only if necessary under `RelaxShort/Views/Home/` or `RelaxShort/Views/Components/`.

Forbidden:

- Do not modify `RelaxShort/Views/RecommendPage/RecommendView.swift`.
- Do not modify `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`.
- Do not modify `RelaxShort/PlayerKit/*`.
- Do not add notification permission popups, reservation/remind features, payment flows, or new backend endpoints.
- Do not hardcode production secrets, tokens, or private URLs.
- Do not remove Mock mode.
- Do not create broad refactors unrelated to Home.

## Product Requirements From Screenshots

### 1. Shared Home Shell

The top area should match DramaBox structure:

- Search bar on the left, crown/VIP promo icon and gift/reward icon on the right.
- Horizontal top tabs: `Popular`, `New`, `Rankings`, `Categories`, `Anime`, `VIP`, `Original+`.
- Active tab text is bright white and bold, inactive text is gray, active underline is short white capsule.
- Layout must work on iPhone mini width and Pro Max width. Text must not overlap icons.
- Keep black/dark background. Avoid decorative gradient orbs.

Current `HomeView.swift` already has `DramaBoxSearchHeaderView` and top tabs. Polish spacing and safe area only if needed; do not rewrite navigation.

### 2. Popular Tab

Reference: `tab_Popular.JPG`

Expected structure:

- First section: dense 3-column poster grid, 9 items visible/near-visible at top.
- Poster card:
  - Image aspect close to vertical poster, 3 columns.
  - Top-right badge when available: `Hot`, `New`, `Following`, etc.
  - Bottom overlay can show play/view count if available.
  - Title below image, max 2 lines.
  - Subtitle/category below title, max 1 line, muted gray.
- Do not implement the `Coming Soon` reservation/remind feature from DramaBox. If current code has a Coming Soon block, remove or hide it for this task.
- Second section: `You Might Like`.
  - Two-column waterfall.
  - Keep category aggregation cards inside waterfall, but make them look intentional: dark brown/red block, header title + chevron, four compact rows with small thumbnails and truncated titles.
  - Normal waterfall cards should include poster, title, small tags/rank chips, and view count where available.

### 3. New Tab

Reference: `tab_new(不要子tab，和预约功能).PNG`

Important user instruction from filename: do not implement the sub tabs and do not implement reservation/remind functionality.

Expected structure:

- One vertical list, no `Live Now` / `Coming Soon` sub-tab.
- Each row:
  - Left poster around 120-140 px wide on Pro Max, scaled down on mini.
  - Small date label at top-right of poster (`Today` or date). It can be derived locally from list order; do not add API dependency.
  - Bottom-right view/play count overlay if available.
  - Right side: title, synopsis, category/tags, episode count.
  - Row height should be stable and dense enough to show multiple items on screen.
- Use real API `featuredDramas` / `dramasForNewTab`; do not use mock-only arrays when `use_real_api=true`.

### 4. Rankings Tab

Reference: `tab_Rankings.PNG`

Expected structure:

- Three pill filters: `Most Trending`, `Top Searched`, `New Releases`.
- Use `RankViewModel` and `HomeRepositoryProtocol.fetchRankings(type:)`.
- List row:
  - Dark rectangular background, radius around 6-8.
  - Large ranking number on the left.
  - Poster thumbnail around 56x80.
  - Title in white, up to 2 lines.
  - Category/tags line in gray.
  - Right side has flame icon and formatted view count.
- Avoid the older orange gradient header mentioned in comments if it does not match the screenshot.
- Tapping a row must navigate to `SeriesPlayerView` through existing `playerDrama` binding.

### 5. Categories Tab

Reference: `tab_Categories.PNG`

Expected structure:

- Multi-row filter matrix above grid.
- Rows:
  - Region: `All`, `Local`, `Chinese`, `Korean`, `Japanese`
  - Audio/Text: `All`, `Dubbed`, `Subtitles Only`
  - Access: `All`, `Paid`, `Members Only`, `Free`
  - Genre row: `All`, `Romance`, `Strong Heroine`, `Powerful Male`
  - Theme row: `All`, `Werewolf`, `Hidden Identity`, `Billionaire`
  - Sort row: `Trending`, `Latest`, `Unwatched`
- Selected option is pink text on dark-pink capsule. Unselected options are gray text without a heavy border.
- Only the genre/category selection must call backend category API through existing `HomeViewModel.selectCategory(at:)` / `fetchCategorySeries`.
- Other filter rows can be UI-only local state in this task. Do not invent backend params.
- Below filters: 3-column poster grid like screenshot.
- Grid card:
  - Poster image.
  - Optional top-right badge.
  - Bottom overlay play/view count.
  - Title below, max 2 lines.
  - Category/tag below, muted gray.

### 6. Anime / VIP / Original+

These tabs should look like finished content tabs:

- Reuse polished poster grid/list components from Popular/Categories where possible.
- Anime can use the existing anime fallback list but should look like a real content tab.
- VIP should have a subdued membership header and poster sections, but avoid a marketing landing page.
- Original+ should use a content-first grid/list with a modest header, not oversized decorative panels.

If time is tight, prioritize in order:

1. Popular
2. Rankings
3. Categories
4. New
5. Anime/VIP/Original+

## API Requirements

Real mode must continue to use:

- `GET /api/v2/home`
- `GET /api/v2/rankings?type=...`
- `GET /api/v2/categories`
- `GET /api/v2/categories/{code}/series`

Do not bypass repositories from views.

Rules:

- `HomeViewModel` may expose additional local state for selected filter chips.
- `HomeView` should not parse DTOs.
- `RankView` should not parse DTOs.
- `RealHomeRepository` stays responsible for DTO to `DramaItem` mapping.
- Empty/error/loading states must remain usable.

Run smoke curl if backend is running:

```bash
curl -fsS 'http://127.0.0.1:8080/api/v2/home?content_language=en&country_code=GLOBAL' | head -c 300
curl -fsS 'http://127.0.0.1:8080/api/v2/rankings?type=popular&content_language=en&country_code=GLOBAL' | head -c 300
curl -fsS 'http://127.0.0.1:8080/api/v2/categories?content_language=en&country_code=GLOBAL' | head -c 300
```

If backend is not running, say so in the delivery report. Do not start backend invisibly.

## Code Quality Requirements

- Prefer small, named SwiftUI components instead of adding more huge inline blocks to `HomeView.swift`.
- `ContentGridView.swift` currently has compressed one-line Swift. You may reformat touched components into readable Swift, but do not rewrite unrelated components wholesale.
- Avoid nested cards inside cards.
- Use stable dimensions based on available width. No viewport-width font scaling.
- Ensure iPhone mini / regular / Pro Max compatibility.
- Do not leave `print()` debug logs.
- Do not leave stale comments like `Task16 R3`, `R4`, or process notes in final UI code unless they explain a still-current behavior.

## Validation

Required:

```bash
cd /Users/ethan/myspance/relaxshort/ios/v1.0.0
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

Recommended if available:

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Manual smoke in simulator:

- Home opens with no crash.
- Popular tab scrolls and card tap opens Series player.
- New tab row tap opens Series player.
- Rankings filters switch data/state and row tap opens Series player.
- Categories filter chips do not overlap on small screens; selecting a real category loads data.
- Anime/VIP/Original+ look like finished content tabs, not temporary empty shells.

## Delivery Report

Create:

- `docs/TASK27_DELIVERY_REPORT.md`

Must include:

- Files changed.
- What was implemented per tab.
- API endpoints verified or reason not verified.
- Exact validation commands and results.
- Known limitations.
- Explicit statement that For You / Series / PlayerKit were not modified.
