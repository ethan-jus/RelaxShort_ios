# Language and Support Product Design QA

## Evidence

- Source visual truth: `/Users/ethan/.codex/generated_images/019f79a3-b347-7671-ab45-21c816edd61d/call_wfqE1B2XvlHhNR2zXCpCeZlt.png`
- Final help center: `/tmp/relaxshort-support-color-qa/help-final.png`
- VIP FAQ search state: `/tmp/relaxshort-support-color-qa/vip-faq-final.png`
- Combined comparison: `/tmp/relaxshort-support-color-qa/design-comparison.png`
- Viewport: iPhone 17 Simulator, 402 × 874 pt, dark mode, English.
- Source pixels: 1563 × 1006 composite image.
- Implementation pixels: 1206 × 2622 at 3× density.
- The middle source panel was cropped and normalized to the same 402 × 874 visual slot as the implementation for the combined comparison.

## State and comparison scope

- The source contains seeded ticket rows; the local simulator had no tickets. Ticket-list contents were therefore not treated as a fidelity comparison.
- The full-view comparison covers navigation, search, quick categories, CTA, ticket-section hierarchy, spacing, typography, and color.
- The focused comparison uses the quick-category region because the requested change concerned the playback/download icon and gold color.

## Comparison history

1. Initial implementation used the global `#C29852` gold and a standalone `play.rectangle` symbol.
   - Finding: P2 visual drift from the source, which uses a brighter warm gold and a combined playback/download glyph.
2. Updated the quick-category icons to scoped design gold `#E6B84E`.
   - Rebuilt the playback/download glyph from SF Symbols using the source-aligned playback frame plus downward arrow.
3. Final simulator capture shows the complete downward arrow, matching color family, line weight, and visual scale.
   - No actionable P0, P1, or P2 differences remain for the requested region.

## Required fidelity surfaces

- Typography: system weights, hierarchy, wrapping, and labels remain consistent with the selected design; localized copy intentionally differs from the Chinese source.
- Spacing: search, quick-category card, CTA, and ticket heading retain the source rhythm without clipping.
- Colors: category icons now use the brighter source-aligned warm gold; black panels, grey borders, white text, and red CTA remain consistent.
- Image and icon quality: all controls use native vector SF Symbols. The playback/download entry now contains both required meanings and remains sharp at 3× density.
- Copy and content: the VIP purchase-not-activated FAQ is present in all eight localization files and appears when searching `VIP`.

## Interaction checks

- Profile → Help & Feedback: passed.
- VIP FAQ search: passed.
- Empty ticket state: passed.
- Live ticket creation and server reply: not run because the backend was intentionally not started.

## Verification

- `xcodebuild -quiet -project RelaxShort.xcodeproj -scheme RelaxShort -configuration Debug -destination 'platform=iOS Simulator,id=99782FD0-C497-439F-B95E-949E6AB85F1C' build`
- Result: `BUILD SUCCEEDED`

final result: passed
