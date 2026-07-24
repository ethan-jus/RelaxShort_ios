# Help & Feedback Product Design QA

## Evidence

- Source visual truth: `/var/folders/24/hnnvyxbn1s13bt4bjv9bl4m40000gn/T/codex-clipboard-3ba638a4-76d1-47a7-bbd1-431e56d01816.png`
- Final help center: `/tmp/relaxshort-support-1to1-qa/help-final.png`
- VIP common-question menu: `/tmp/relaxshort-support-1to1-qa/vip-dropdown.png`
- Combined comparison: `/tmp/relaxshort-support-1to1-qa/design-comparison.png`
- Viewport: iPhone 17 Simulator, 402 × 874 pt, dark mode, Simplified Chinese.
- Source pixels: 1342 × 1310 composite image.
- Implementation pixels: 1206 × 2622 at 3× density.
- The source help-center panel was cropped and normalized to the same 402 × 874 visual slot as the implementation.

## State and comparison scope

- The source contains seeded ticket rows while the local simulator has no tickets. Ticket-list data was not treated as a visual defect.
- The comparison covers navigation, search, the three quick-category entries, CTA, ticket-section hierarchy, spacing, typography, icon shape, and color.
- The VIP issue is intentionally placed in the common-question menu rather than compressing the three source category columns into four.

## Comparison history

1. The previous implementation approximated all three category graphics with SF Symbols.
   - Finding: P2 icon-shape and color drift, especially for playback/download and the coin stack.
2. Replaced the three approximations with tightly cropped assets extracted from the supplied source visual.
   - Increased the icon presentation area and category-card height to match the source proportions.
   - Confirmed there are no visible raster-background seams against the dark category card.
3. The previous support flow used the global coral red `#E85048`.
   - Finding: P2 color drift from the supplied support design.
   - Scoped the support flow to the source-sampled deep red `#DA1D20`, including the CTA, status color, message accents, and send controls.
4. Added an accessible common-question menu to the search bar.
   - The menu contains playback, coins, VIP activation, and sign-in issues.
   - Selecting the VIP entry filters directly to “购买 VIP 后没有到账”.

## Required fidelity surfaces

- Typography: system weights and Chinese labels match the selected design hierarchy without clipping.
- Spacing: search, category card, CTA, and ticket heading follow the source rhythm and safe-area behavior.
- Colors: category graphics preserve their source gold; the support-specific red is sampled from the supplied visual; dark panels, grey borders, and white text are aligned.
- Image and icon quality: the three quick-category icons use the supplied source artwork at 3× density instead of unrelated system-symbol substitutes.
- Copy and content: the VIP purchase-not-activated FAQ exists in all eight localization files and is reachable from the common-question menu and direct search.

## Interaction checks

- Profile → Help & Feedback: passed.
- Common questions → VIP purchase not activated: passed.
- Empty ticket state: passed.
- Live ticket creation and server reply: not run because the backend was intentionally not started.

## Verification

- `xcodebuild -quiet -project RelaxShort.xcodeproj -scheme RelaxShort -configuration Debug -destination 'platform=iOS Simulator,id=99782FD0-C497-439F-B95E-949E6AB85F1C' build`
- Result: `BUILD SUCCEEDED`

final result: passed

---

# Offline Downloads Product Design QA

## Evidence

- Selected visual truth: `/Users/ethan/.codex/generated_images/019f79a3-b347-7671-ab45-21c816edd61d/call_YeRTh1YZyKMj6hbx0a3URufb.png`
- Final download page: `/tmp/relaxshort-downloads-qa/downloads-final.png`
- Combined comparison: `/tmp/relaxshort-downloads-qa/downloads-comparison.png`
- Offline playback proof: `/tmp/relaxshort-downloads-qa/offline-playback.png`
- Viewport: iPhone 17 Simulator, 402 × 874 pt, dark mode, Simplified Chinese.

## Comparison scope

- Compared navigation, storage hierarchy, progress treatment, section titles, row density, typography, dark palette, and red/gold accents against the selected option.
- The selected visual contains three seeded dramas and an active queue item. The functional QA state contains one completed local video, so data quantity was not treated as a layout defect.
- No P0 or P1 visual defects were found. The empty cover in QA is expected because the local fixture intentionally has no remote artwork.

## Interaction checks

- Profile → Offline Downloads: passed.
- Completed download → offline player: passed.
- Local MP4 was opened by the shared `PlayerCoordinator` without the former missing-environment crash: passed.
- Edge-back from offline player: passed.

## Verification

- `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/relaxshort-downloads-derived CODE_SIGNING_ALLOWED=NO build`
- Result: `BUILD SUCCEEDED`

final result: passed
