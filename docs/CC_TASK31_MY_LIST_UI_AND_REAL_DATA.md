# Task31 My List UI + Real Data Implementation Plan

## Goal

Complete the iOS My List experience so it faithfully matches the written DramaBox visual contract and uses the real Task31 bookmark, watch-history, resume-progress, and trending APIs.

CC must implement directly from this document and:

`docs/CC_TASK31_MY_LIST_VISUAL_CONTRACT.md`

CC does not need to inspect or interpret screenshots. The visual contract is the authoritative textual translation of the screenshots.

## Repository and starting state

- Repository: `/Users/ethan/myspance/relaxshort/ios/v1.0.0`
- Branch: `main`
- The worktree already contains uncommitted Task31 core work: real favorites repository, bookmark store, watch-progress reporter, resume-time support, tests, and Xcode project references.
- Preserve and review those changes. Do not reset, discard, or replace them with Mock-only code.
- The backend Task31 contract is already committed in `app-server/v2` at `bda0373`.
- Do not modify any other repository.
- Final delivery must be one independent iOS commit containing all current uncommitted Task31 production code, tests, localization, and My List UI.

Before editing, read only:

1. Root and iOS `AGENTS.md` / `CLAUDE.md`.
2. `docs/CC_TASK31_MY_LIST_VISUAL_CONTRACT.md`.
3. Current `FavoritesView`, `FavoritesViewModel`, `MainTabView`, navigation route, Task31 repository/store models, and their tests.
4. Current `git diff --stat`, then only relevant diffs.

## Product decisions

- My List has exactly two tabs: `Following` and `History`.
- `Following` means backend bookmark. Do not call or recreate a follow API.
- Do not implement `Reminder Set`.
- Logged-out behavior keeps the existing login guide and must not flash real or Mock content first.
- Real API failures remain visible errors; do not fall back to Mock data.
- Most Trending uses `homeRepository.fetchRankingEntries(type: "trending")`.

## 1. Stabilize the existing Task31 core

Run the existing Task31 targeted tests first. Fix current code only where required for correctness or compilation.

The following invariants are mandatory:

- `BookmarkStore.isBookmarked` reflects the optimistically updated `bookmarkedIDs`; `pendingIDs` only blocks duplicate requests.
- A failed or late `loadStatus` response must not erase newer user bookmark changes.
- `WatchProgressReporter.finalize(false)` sends the latest observed progress and actual total duration. It must never manufacture `progress == duration`.
- Old heartbeat/final responses cannot clear or overwrite a newer playback session.
- Heartbeat and final sends preserve request order.
- `PlaybackMediaSourceDTO.resumeTime` remains mapped from the play response.

Do not broaden this into a player rewrite.

## 2. My List state model

Extend `FavoritesViewModel` as the single screen state owner:

- Keep bookmark and history pagination/loading/error state independent.
- Add `trendingEntries: [RankingEntry]`, `isTrendingLoading`, and `trendingError`.
- Add `selectedSegment`, `isEditing`, `selectedBookmarkIDs`, and `isRemoving`.
- `enterEditing()` is valid only on Following.
- `cancelEditing()` clears selection and exits edit mode.
- `toggleSelection(id:)` never navigates.
- `removeSelectedBookmarks()` calls `setBookmarked(false, seriesID:)` once per selected ID.
- During removal, block duplicate submission.
- Successful removals immediately disappear from `bookmarks` and call `bookmarkStore.applyServerState(false, seriesID:)`.
- Failed removals remain visible and selected. Show one localized aggregate error, not one alert per item.
- Exiting edit mode after removal occurs only when no failed selected items remain.

Derived row data:

- Build a history lookup by `drama.id`.
- Following rows use matching real history progress when available.
- Following rows without history display current episode `max(drama.currentEpisode, 1)` and progress `0`.
- History rows always use backend `episodeID`, `currentEpisode`, `resumeTime`, and `progress`.
- Clamp all displayed progress to `0...1`.

Initial loading:

- When logged in, load bookmarks, history, and trending concurrently once.
- Changing tabs does not refetch or clear the other tab.
- Pagination triggers near the last visible row and must guard `isLoading` and `hasMore`.
- Retry acts only on the failed data source.

## 3. Navigation and real resume

Extend `SeriesPlayerNav` with an optional `episodeID` while retaining `startEpisode` and `resumeTime`.

Update both `MainTabView` navigation destinations and `SeriesPlayerView` so:

- Following without history opens at the drama’s playable entry, default episode 1.
- Following with matching history opens the exact backend episode and resume time.
- History always sends backend `episodeID`, `episodeNumber`, and `resumeTime`.
- Explicit My List resume time has priority over play-asset resume time for the initial episode only.
- It must not leak to later episodes after the user switches episodes.
- Existing For You handoff remains the highest-priority resume source.
- Use source scenes `my_list_following`, `my_list_history`, and `my_list_trending`.

Do not create a second playback screen.

## 4. Screen implementation

Replace the logged-in body of `FavoritesView`; do not layer patches over the current card UI.

Required structure:

- Full black background and no `My List` navigation title.
- One top row with Following, History, and the edit/sliders icon.
- Edit icon is available only when Following is selected and bookmarks are non-empty; reserve its width so tab alignment does not jump.
- Flat transparent list rows: no panel background, border, shadow, or chevron.
- Poster width:

```swift
min(max(containerWidth * 0.22, 72), 92)
```

- Poster ratio `2:3`, `DB.posterRadius`, and a 3pt bottom progress track.
- Text hierarchy and spacing must exactly follow `CC_TASK31_MY_LIST_VISUAL_CONTRACT.md`.
- Following and History share one focused row component but receive different row data/navigation actions.
- After the list, show the real `Most Trending` three-column grid.
- Trending cards navigate to the player.

Editing mode:

- Only Following can enter editing.
- Replace the tab row with centered Choose and right-aligned Cancel.
- Add fixed-width selection circles aligned with poster centers.
- Selected poster receives a 45% black overlay; text stays unchanged.
- Hide the app’s main tab bar through `appStore.isBottomTabBarHidden`.
- Add a fixed bottom Remove bar above the bottom safe area.
- Cancel, successful completion, disappearance, and logout must restore the main tab bar.
- There must be only one bottom safe-area consumer; the last row must scroll above the Remove bar.

Loading/error/empty:

- First load: centered red-tinted progress.
- Pagination: small inline progress at list bottom.
- Error: localized message plus Retry.
- Empty Following/History: localized empty state without Mock content.
- Trending failure must not hide successfully loaded bookmarks/history.

## 5. Localization and accessibility

Add My List keys to every existing localization:

- Following, History, Choose, Cancel, Remove, Retry, Most Trending.
- Empty Following, empty History, load failure, partial removal failure.
- Accessibility selected/unselected values and selected-count Remove label.

Update `LocalizationHelper` only if typed accessors are the project convention. Do not hardcode visible English text.

Support system RTL without manually reversing arrays or using hardcoded left/right offsets.

## 6. Tests

Extend `FavoritesViewModelTests` with:

- Bookmarks/history/trending load independently.
- One source failure preserves the other successful sources.
- Pagination appends without duplicates or repeated concurrent requests.
- Enter/cancel edit clears selection correctly.
- Partial removal removes successful IDs, retains failed IDs and their selection, and synchronizes `BookmarkStore`.
- Duplicate Remove taps issue one removal operation.
- Following row data uses matching history; no-history fallback is episode 1/progress 0.

Extend navigation/player tests with:

- History route preserves episode ID, episode number, and resume time.
- Explicit My List resume applies only to the initial episode.
- For You handoff remains higher priority.

Retain and pass the existing Task31 API, repository, bookmark-store, reporter, and coordinator tests.

## 7. Verification

Run targeted tests first:

```bash
xcodebuild test -quiet \
  -project RelaxShort.xcodeproj \
  -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:RelaxShortTests/APIEndpointTests \
  -only-testing:RelaxShortTests/FavoritesRepositoryContractTests \
  -only-testing:RelaxShortTests/BookmarkStoreTests \
  -only-testing:RelaxShortTests/WatchProgressReporterTests \
  -only-testing:RelaxShortTests/PlayerCoordinatorTests \
  -only-testing:RelaxShortTests/FavoritesViewModelTests
```

Then run one full test pass:

```bash
xcodebuild test -quiet \
  -project RelaxShort.xcodeproj \
  -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Build the other required sizes:

```bash
xcodebuild build -quiet -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation),OS=17.0'

xcodebuild build -quiet -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

Also run:

```bash
git diff --check
```

Do not claim visual parity. Codex will launch the simulator, capture normal/edit states, and compare them with the reference screenshots after delivery.

## 8. Commit and handoff

- Delete temporary Task31 Xcode-editing scripts; do not commit `scripts/add_task31_files.py` or `scripts/add_files_to_xcode.py`.
- Do not add another delivery-report file.
- Review `git status` and ensure only Task31 iOS files are staged.
- Create one commit:

```bash
git commit -m "feat: complete Task31 My List experience"
```

Return in chat:

- commit hash
- concise changed-area summary
- exact test/build exit results
- any remaining issue

Stop after the commit. Do not push.
