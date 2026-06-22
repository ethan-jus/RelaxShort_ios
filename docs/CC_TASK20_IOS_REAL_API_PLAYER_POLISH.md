# CC Task 20: iOS Real API Player Polish

## Context

Task18/19 made local backend + iOS simulator smoke work:

- backend local URL: `http://127.0.0.1:8080`
- iOS flags:
  - `use_real_api=true`
  - `api_base_url=http://127.0.0.1:8080`
- Home renders real backend data and local generated covers.
- Tapping the first drama opens the player and renders Apple HLS smoke video.

Observed UI issues in simulator:

1. Player overlay shows `category.Romance` instead of `Romance`.
2. English title bar shows `The Billionaires Bargain 第 1 集` instead of an English episode format.
3. Free content still shows hardcoded `Members Only` + `Exclusive` tags in player/recommend views.

## Goal

Polish real API player/recommend display semantics so the local smoke app looks coherent:

- category names should never leak localization keys such as `category.Romance`
- episode number text should use existing localized `player.episode_number`
- player/recommend badges should reflect `DramaItem` state instead of hardcoded `Members Only`/`Exclusive`

## Scope

Work only in `ios/v1.0.0`.

Likely files:

- `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- `RelaxShort/Views/RecommendPage/RecommendView.swift`
- `RelaxShort/Utils/LocalizationHelper.swift`
- localized `Localizable.strings` files if needed
- focused iOS docs/review notes under `docs/`

Allowed:

- small helper methods for display tags if they reduce duplication
- adding missing category localization fallback keys for backend category names/codes
- replacing hardcoded text with existing localization helpers

Do not:

- modify backend code
- change API contracts
- rewrite player architecture
- alter unrelated UI layout
- remove existing language resource files
- add fake test claims

## Required Fixes

### 1. Category Display Fallback

`L10n.categoryDisplayName(drama.category)` must not display `category.<raw>` when no key exists.

Expected behavior:

- known backend names/codes such as `Romance`, `Fantasy`, `Thriller`, `Drama`, `Action`, `romance`, `fantasy`, `thriller`, `drama`, `action` display as user-facing names
- unknown non-empty category returns the raw category text, not a key string
- empty category should not render a category tag

### 2. Episode Number Format

Player title/header should use localized episode number formatting:

- English: `Ep.1`
- Simplified Chinese/Base: `第1集`
- existing other locales should continue using their current `player.episode_number` format

Do not hardcode Chinese `"第 \(n) 集"` in Swift views.

### 3. Badge Semantics

Replace hardcoded `Members Only` / `Exclusive` tags in player and recommend card overlays.

Rules:

- show member/VIP tag only when `drama.isMemberOnly || drama.isVIPOnly || drama.badge == .vip`
- show `Hot`/`New`/`Trending` only when corresponding `DramaItem` fields indicate it
- show category tag only when non-empty
- keep tag count compact; do not create overflowing tag rows
- if localization keys are missing for new tag labels, add them consistently across all existing `.lproj` resources or use existing localized strings

## Verification

Run:

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If backend local is running at `http://127.0.0.1:8080`, also run simulator smoke:

```bash
xcrun simctl spawn booted defaults write com.relaxshort.ios use_real_api -bool true
xcrun simctl spawn booted defaults write com.relaxshort.ios api_base_url -string http://127.0.0.1:8080
xcrun simctl terminate booted com.relaxshort.ios || true
xcrun simctl launch booted com.relaxshort.ios
```

Then verify manually or with Computer Use/screenshot:

- Home still loads real covers.
- Tapping `The Billionaires Bargain` opens player.
- Player title uses localized episode number, not hardcoded Chinese in English UI.
- Player category displays `Romance`, not `category.Romance`.
- Free first episode does not show `Members Only`/`Exclusive` unless the actual `DramaItem` state says it should.

## ECC Usage

Use ECC where available:

- `swiftui-patterns` for view/helper placement
- `swift-reviewer` for SwiftUI correctness
- `swift-build-resolver` if xcodebuild fails
- general checklist/review capability for localization regressions

If ECC commands are unavailable in terminal mode, state it explicitly and perform the equivalent manual checklist.

## Delivery

Commit all changes on current branch.

Create `docs/TASK20_DELIVERY_REPORT.md` with:

- changed files
- exact fixes
- ECC usage record
- verification commands/results
- screenshots path if simulator smoke was run
- remaining risks

