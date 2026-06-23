# Task26 For You Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the iOS For You feed and Series Player so the real API playback experience visually and behaviorally matches the approved Task26 design.

**Architecture:** Keep the existing `PlayerKit`, `RecommendView`, and `SeriesPlayerView` structure. Add small focused SwiftUI helper views inside the current RecommendPage/Player boundaries, fix player item indexing, and wire bottom sheets to existing `PlayerMediaSource` data without rewriting playback internals.

**Tech Stack:** SwiftUI, AVPlayer/PlayerKit, existing `DependencyContainer`, real `/api/v2/feed/for-you` and `/api/v2/episodes/{episodeId}/play` APIs.

---

## File Map

- Modify `RelaxShort/Views/RecommendPage/RecommendView.swift`: For You visual polish, long-press state, title/about sheet entry, bookmark/share feedback, player index safety.
- Modify `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`: top controls, bottom membership/download strip, episode sheet, speed/quality/more sheets, play asset fetching on episode switch.
- Modify `RelaxShort/Views/Components/RightActionBar.swift`: align action rail to reference, keep shared API stable.
- Modify `RelaxShort/Views/RecommendPage/ShareSheet.swift`: tune bottom share sheet spacing and copy text.
- Modify `RelaxShort/Views/RecommendPage/SpeedHUDView.swift`: keep small `2.0x >>` HUD for long press.
- Create `RelaxShort/Views/RecommendPage/PlayerOptionSheets.swift`: reusable bottom sheets for speed, quality, and more menu.
- Modify `RelaxShort.xcodeproj/project.pbxproj`: add any new Swift files to the app target.
- Create `docs/TASK26_DELIVERY_REPORT.md`: implementation and verification report.

## Visual Notes From Codex

CC cannot inspect images. Use these descriptions instead of opening reference screenshots.

For You normal state:

- Fullscreen vertical video with bottom black gradient.
- Top right search icon only, white, no circular background.
- Bottom info starts around 140-170 pt above bottom tab bar.
- Title is bold white, around 22 pt, one line, trailing chevron.
- Tags are small rounded gray pills, white text, 12-13 pt, with chevrons on non-first tags.
- Synopsis starts with `EP.1 |`, two lines max, light gray, ends with `... more`.
- Right rail has only bookmark and share. Bookmark is large white bookmark icon with count below. Share is large white arrow with `Share` label below.
- `Watch Full Series` is a wide translucent dark gray button below synopsis, height about 56, 5-8 pt radius, bold white text.
- Progress bar is just above the bottom tab bar.

For You paused state:

- Same overlay as normal state.
- Center play button is a translucent dark circle, about 88 pt, white play triangle.

For You long-press fast-forward state:

- Hide title, tags, synopsis, Watch button, search, and right rail.
- Show only small `2.0x >>` text at upper center around 16% screen height.
- Keep bottom progress bar visible.

Title/about sheet:

- Bottom sheet height about 78% of screen.
- Top rounded corners, dark panel, small drag handle, close X at top right.
- Header has 92x124 poster, title, views, rating row.
- Tabs are `Synopsis` and `Episodes`, large bold labels, active underline.
- Synopsis tab includes full synopsis, tag pills, cast rows, and 3-column recommendation grid.
- Episodes tab uses large episode grid, 6 columns, with range tabs like `1-30`, `31-60`, `61-67`.

Share sheet:

- Background video is dimmed.
- Bottom sheet height about 35% of screen, top rounded corners.
- Center title `Share`, close X right.
- Gray reward pill: coin icon + `first share gets 10 coins`.
- Horizontal icon row: Instagram, Snapchat, Facebook Messenger, WhatsApp, Copy Link.

Series Player visible controls:

- Fullscreen video.
- Top left: back chevron + `EP.1`.
- Top right: speed icon/text `Speed` + vertical ellipsis.
- Right rail: bookmark count, Episodes button, Share button.
- Bottom left title and synopsis, no `Watch Full Series` CTA.
- Progress bar above a black bottom strip.
- Bottom strip: left gold `Join membership` pill, right `Download`.

Series Player episode sheet:

- Same dark bottom sheet style as title sheet.
- Header same poster/title/views/rating.
- Active tab `Episodes`.
- Range tabs `1-30`, `31-60`, `61-67`.
- Large 6-column grid. Current episode cell is lighter and includes a tiny playing indicator at bottom left. Locked cells show a small lock badge at top right.

Speed sheet:

- Bottom sheet about half screen, dark panel, rounded top corners.
- Center title `Speed`, close X right.
- Options vertical list: `3.0x`, `2.0x`, `1.5x`, `1.25x`, `1.0x`, `0.75x`.
- Selected row has darker rounded rectangle and pink circular checkmark on right.

Quality sheet:

- Same bottom sheet style.
- Center title `Current Quality`, close X right.
- Options: `Auto`, available qualities from `PlayerMediaSource.qualities`, fallback labels `1080p`, `720p`, `540p` when qualities are missing.
- VIP-only qualities can show a small gold VIP badge but must be disabled unless real entitlement exists.
- Selected row has dark rounded background and pink circular checkmark.

## Task 1: Fix For You Player Item Indexing

**Files:**
- Modify `RelaxShort/Views/RecommendPage/VideoPlayerView.swift`
- Modify `RelaxShort/Views/RecommendPage/RecommendView.swift`

- [ ] Add a playable item mapping to keep `dramas` indexes aligned with `PlayerMediaItem` indexes.

Implementation direction:

```swift
struct RecommendPlayableItem: Identifiable, Hashable {
    let id: String
    let dramaIndex: Int
    let item: PlayerMediaItem
}
```

- [ ] Change `RecommendSession.initializePool` so it stores or returns the playable drama indexes, instead of blindly using `compactMap` and then calling `engine.move(to: new)` with the original drama index.

Acceptance:

- If any `DramaItem` has nil/invalid `videoURL`, it is skipped safely.
- Swiping to a later visible drama still moves to the matching playable item.
- No `about:blank` URL is ever constructed.

- [ ] Run:

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected: `BUILD SUCCEEDED`.

## Task 2: Polish For You Overlay States

**Files:**
- Modify `RelaxShort/Views/RecommendPage/RecommendView.swift`
- Modify `RelaxShort/Views/Components/RightActionBar.swift`
- Modify `RelaxShort/Views/RecommendPage/SpeedHUDView.swift`

- [ ] Adjust For You normal overlay to match the visual notes: bottom title/tags/synopsis/CTA, right rail with bookmark/share only, progress bar above tab bar.

- [ ] Add a long-press fast-forward overlay state that hides all metadata and buttons except `SpeedHUDView` and the progress bar.

- [ ] Ensure paused state shows a large central play button while preserving metadata and right rail.

- [ ] Keep search icon top right, white, no opaque circular chip.

Acceptance:

- `play_normal.PNG`, `click_screen_stop_UI.PNG`, `click_introduction.PNG`, and `long_press_screen_fast_forward_UI.PNG` are represented by concrete app states.
- Text does not overlap the right rail or bottom tab bar on iPhone 17 simulator.

## Task 3: Convert Title/About Sheet Into Reference-Style Details Sheet

**Files:**
- Modify `RelaxShort/Views/RecommendPage/RecommendView.swift`

- [ ] Keep `DramaAboutSheet` local if it remains manageable; otherwise extract it to `RelaxShort/Views/RecommendPage/DramaAboutSheet.swift`.

- [ ] Ensure the sheet has handle, close X, poster header, views, rating row, `Synopsis`/`Episodes` tabs, synopsis content, tag pills, cast rows, and recommendation grid.

- [ ] Episodes tab must use 6 columns and range tabs. Use `drama.episodeCount` when available; if fewer than 30, still render available count only.

Acceptance:

- Title tap opens the sheet.
- Close button and backdrop tap dismiss it.
- `Watch Full Series` from the sheet navigates to `SeriesPlayerView` with handoff context.

## Task 4: Polish Share Sheet

**Files:**
- Modify `RelaxShort/Views/RecommendPage/ShareSheet.swift`

- [ ] Tune `ShareSheet` to match the visual notes: dimmed background handled by `.sheet` presentation, dark rounded top panel, title, close X, reward pill, horizontal icon row.

- [ ] Keep copy-link behavior local with `UIPasteboard`.

Acceptance:

- Share opens from For You and Series Player.
- Copy Link writes a stable `https://relaxshort.app/drama/<title-or-id>` placeholder and dismisses.
- No real coin reward is issued.

## Task 5: Polish Series Player Chrome

**Files:**
- Modify `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- Modify `RelaxShort/Views/Components/RightActionBar.swift`

- [ ] Add a top control row visible when `isUIVisible` is true:

```swift
HStack {
    Button { dismiss/back } label: { Image(systemName: "chevron.left") }
    Text("EP.\(currentEpisode)")
    Spacer()
    Button { showSpeedSheet = true } label: { Label("Speed", systemImage: "speedometer") }
    Button { showMoreSheet = true } label: { Image(systemName: "ellipsis") }
}
```

- [ ] Add bottom strip with gold `Join membership` pill on left and `Download` text button on right. These are UI-only in Task26; tap can show a toast or no-op diagnostic.

- [ ] Ensure bottom metadata excludes `Watch Full Series` CTA in Series Player.

Acceptance:

- `play_ui_show.PNG` and `play_ui_hide.PNG` states are represented.
- Hidden state removes chrome while video keeps playing.

## Task 6: Rebuild Episode Sheet

**Files:**
- Modify `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`

- [ ] Replace the current compact 5-column `EpisodePickerSheet` with a reference-style large sheet:
  - header with poster/title/views/rating
  - `Synopsis`/`Episodes` tabs, active `Episodes`
  - range tabs in 30-episode chunks
  - 6-column grid
  - current episode lighter cell with tiny playing bars
  - locked cell lock badge at top right

- [ ] Use `drama.freeEpisodeRange` for lock decisions. If nil, default to `1...3`.

Acceptance:

- Current episode is highlighted.
- Locked episode opens existing unlock sheet.
- Unlocked episode changes `currentEpisode` and dismisses sheet.

## Task 7: Add Speed, Quality, and More Sheets

**Files:**
- Create `RelaxShort/Views/RecommendPage/PlayerOptionSheets.swift`
- Modify `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`
- Modify `RelaxShort.xcodeproj/project.pbxproj`

- [ ] Create reusable bottom sheet primitives for:
  - `PlayerSpeedSheet`
  - `PlayerQualitySheet`
  - `PlayerMoreSheet`

- [ ] Speed options: `3.0x`, `2.0x`, `1.5x`, `1.25x`, `1.0x`, `0.75x`.

- [ ] Selecting speed calls `playerCoordinator.engine.setRate(value)` and stores selected speed for UI.

- [ ] Quality options come from cached `PlayerMediaSource` where possible. If empty, show `Auto`, `720p` as current fallback, and disabled `1080p VIP`, `540p`.

- [ ] More sheet should include entries for `Quality`, `Subtitles`, and `Report subtitle issue`; unsupported entries show disabled state or a toast, not a crash.

Acceptance:

- `speed.PNG`, `quality.PNG`, and `三个点按钮.PNG` are represented by app states.
- Sheets open and close without stopping playback.

## Task 8: Ensure Episode Switch Fetches Real Play Asset

**Files:**
- Modify `RelaxShort/Views/RecommendPage/SeriesPlayerView.swift`

- [ ] When `currentEpisode` changes, fetch the target episode's play asset before or during player item refresh. Current code fetches only the initial episode; Task26 must avoid switching to stale or missing URLs.

- [ ] Update `episodeMediaSources[episodeId]` when the play asset returns.

- [ ] Rebuild/refresh the engine item for that episode without reintroducing `about:blank`.

Acceptance:

- Switching from episode 1 to episode 2 uses `/api/v2/episodes/{episodeId}/play`.
- Xcode logs show concrete HTTP MP4/HLS URL, not nil/about:blank.

## Task 9: Delivery Report and Verification

**Files:**
- Create `docs/TASK26_DELIVERY_REPORT.md`

- [ ] Include modified files, screenshot states covered, commands run, results, and known gaps.

- [ ] Run iOS build:

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- [ ] If backend code changed, run backend tests:

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn test
```

- [ ] With backend running, run smoke curl:

```bash
curl 'http://127.0.0.1:8080/api/v2/feed/for-you?limit=3&content_language=en&country_code=GLOBAL'
```

Expected: feed cards include non-empty `play_asset` URLs.

## Self-Review

- Spec coverage: This plan covers For You overlay, title/about sheet, share sheet, Series Player chrome, episode sheet, speed, quality, more menu, real play asset switching, and verification.
- Placeholder scan: No TBD/TODO placeholders are present.
- Type consistency: New helper names are scoped to RecommendPage and can be adjusted during implementation, but public behavior and files are fixed.
