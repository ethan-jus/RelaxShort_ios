# CC Task27 R2 - Home UI and Share Sheet Rework

Date: 2026-06-24
Owner: CC
Reviewer: Codex

## Context

Task27 R1 is not accepted. Read first:

- `docs/CC_TASK27_HOME_UI_API_POLISH.md`
- `docs/CODEX_REVIEW_TASK27.md`
- Current diff in `git diff`

Important: do not claim completed work that is not present in the diff. Rewrite `docs/TASK27_DELIVERY_REPORT.md` with only verified facts.

CC cannot inspect the reference screenshots. The visual requirements below are the source of truth for R2.

Reference files used by Codex:

- `design-reference/dramabox/01_for_you/click_share_button.PNG`
- `design-reference/dramabox/02_home/tab_Popular.JPG`
- `design-reference/dramabox/02_home/tab_Categories.PNG`
- `design-reference/dramabox/02_home/tab_Rankings.PNG`

## Scope

R2 must fix two visible areas:

1. Home page shell and tab content polish.
2. Share bottom sheet quality.

Do not modify:

- `PlayerKit`
- For You playback logic
- Series player playback logic
- Backend code
- API DTO contracts unless a compile issue proves it is necessary

## A. Share Sheet Rework

Reference behavior and appearance:

- Full-screen video remains dimmed behind the sheet.
- Bottom sheet starts from the bottom and has a compact height, roughly 390-430 pt on iPhone 17 class screens.
- No large translucent empty area above the content.
- Sheet background is a solid dark panel, around `#242424`, with top corner radius around 24-28 pt.
- Bottom edge is flush with the screen bottom.
- Header:
  - Title `Share` centered.
  - Font around 22-24 pt, bold, white.
  - Close `xmark` at right, 32-40 pt hit target, light gray.
  - Header top/bottom spacing must look balanced, not cramped.
- Reward pill:
  - Nearly full width with horizontal margins around 24 pt.
  - Height around 50-56 pt.
  - Medium gray capsule background.
  - Coin icon at left, gold/yellow.
  - Text `first share gets 10 coins`, font around 17-18 pt, medium.
- Platform row:
  - Five actions: Instagram, Snapchat, Facebook Messenger, WhatsApp, Copy Link.
  - Icons must be large, around 74-84 pt circles.
  - Labels around 16-18 pt.
  - Use brand-like colors:
    - Instagram: pink/orange/purple gradient circle with white camera.
    - Snapchat: bright yellow circle with a high-contrast simple icon.
    - Facebook Messenger: blue/purple/pink gradient circle with white message.
    - WhatsApp: green circle with white phone/chat icon.
    - Copy Link: dark gray circle with white link.
  - Use a horizontal `ScrollView` only if needed, but Copy Link must be reachable and visually present.

Implementation requirements:

- Fix the root cause in `RelaxShort/Views/RecommendPage/ShareSheet.swift`: the sheet content must fill the presentation detent height. Do not leave an upper translucent blank area.
- Update all sheet presenters using `ShareSheet`:
  - `RelaxShort/Views/RecommendPage/RecommendView.swift`
  - `RelaxShort/Views/Series/SeriesPlayerView.swift`
- Prefer a single reusable presentation style for ShareSheet, for example an extension/helper or consistent modifiers in both presenters:
  - `.presentationDetents([.height(...)])`
  - `.presentationDragIndicator(.hidden)`
  - `.presentationCornerRadius(...)`
  - `.presentationBackground(...)`
- The share action may still be local-only. Copy Link should write to `UIPasteboard`.
- Do not trigger any playback side effects when opening or closing the share sheet.

## B. Home Shell Spacing

User-visible R1 issues:

- Search bar is too close to the screen top.
- Search bar to top tab spacing is poor.
- Top tab to content spacing is too tight.

Fix requirements:

- Remove the negative top lift pattern in `RelaxShort/Views/Home/HomeView.swift`:

```swift
let topLift = ...
.padding(.top, -topLift)
```

- Replace it with an explicit safe-area-aware spacing contract:
  - Search/header must sit below the status bar / dynamic island with comfortable spacing.
  - Search/header to tab bar gap: around 12-16 pt.
  - Tab bar to content gap: around 14-18 pt.
  - Do not use ad hoc negative padding.
- The reference Home layout has a clear vertical rhythm:
  - Status bar.
  - Search/reward header row.
  - Main tab row.
  - Content area.
  These layers must not visually collide or look glued together.
- Verify the layout conceptually for:
  - Small screen width such as iPhone mini / SE class.
  - Standard screen such as iPhone 17.
  - Large screen such as iPhone 17 Pro Max.
- Keep the existing Home navigation behavior and API loading behavior.

## C. Home Tab Polish

R1 only changed Rankings. R2 must make real Home page changes where required.

### Popular / New / Anime / VIP / Original+

- Make visible UI improvements in the actual Home files, not only in the delivery report.
- Keep the existing data sources and API calls.
- Do not invent backend-only dependencies.
- Cards/lists should use the existing design tokens (`DB`, `DT`) and be visually consistent with the dark DramaBox style:
  - Dark panels instead of flat page background where a row/card needs separation.
  - Consistent poster corner radius.
  - Clean title, category, episode count, view count hierarchy.
  - No text overlap on small screens.

### Categories

The current one-row genre pill list is not enough. Implement a multi-row filter matrix above the grid:

- Region row: `All`, `US`, `Korea`, `China`
- Audio/Text row: `Dubbed`, `Subtitles`
- Access row: `Free`, `Member`
- Genre row: use `viewModel.categories` from the backend. This is the only row that must affect API/category selection.
- Theme row: `Boss`, `Revenge`, `Mafia`, `Werewolf`
- Sort row: `Popular`, `Newest`

Behavior:

- Genre row selection must continue to call `viewModel.selectCategory(at:)`.
- Other rows can be local UI state for now.
- Selected chip should be visually obvious but not oversized.
- Matrix must wrap or scroll cleanly on small screens.
- Use the reference structure: each row begins with a selected/default pill such as `All` or `Trending`, followed by muted text options across the row. Do not make every option look like a heavy capsule.
- Do not break category loading/error/empty states.

### Rankings

The current R1 changes are directionally useful but incomplete.

Rework `RankCardView` / `RankView` so rows look like distinct dark rounded blocks:

- No page-background row blending.
- No visible right chevron unless there is a real action affordance that needs it.
- Rank number large and fixed-width at left.
- Thumbnail with rounded corners.
- Title and metadata in the middle.
- Flame/heat count on the right in warm gold/orange.
- Row spacing should create visible separation, not divider-line list styling.
- Top ranking filters should be pill controls matching the reference:
  - Selected pill filled.
  - Unselected pills outlined/muted.
  - Reasonable horizontal spacing and no cramped text.

## D. Delivery Report Requirements

Rewrite `docs/TASK27_DELIVERY_REPORT.md`.

It must include:

- Exact files changed.
- Which Home tabs were actually modified.
- Share sheet changes.
- Verification commands and exact results.
- Any known limitation.

Do not include:

- Claims about files or tabs not touched.
- Claims that simulator visual QA was done unless it was actually done.
- Backend/API success claims unless a real command was run and recorded.

## Verification

Run from `/Users/ethan/myspance/relaxshort/ios/v1.0.0`:

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

If the simulator/backend is available, also manually smoke:

- For You share sheet opens and visually matches the requirements.
- Series share sheet opens and visually matches the requirements.
- Home search/header/tab/content spacing no longer crowds the status bar.
- Categories filter matrix displays and genre selection still reloads data.
- Rankings rows are distinct rounded cards.

## Acceptance Bar

R2 passes only if the actual diff matches the delivery report and the visible UI quality is improved in the requested files. A build pass alone is not enough.
