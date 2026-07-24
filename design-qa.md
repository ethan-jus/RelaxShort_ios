# Language and Support Product Design QA

## Evidence

- Source visual truth: `/Users/ethan/.codex/generated_images/019f79a3-b347-7671-ab45-21c816edd61d/call_wfqE1B2XvlHhNR2zXCpCeZlt.png`
- Language implementation: `/tmp/relaxshort-support-qa/language.png`
- Help center implementation: `/tmp/relaxshort-support-qa/help-center.png`
- New ticket implementation: `/tmp/relaxshort-support-qa/new-ticket.png`
- Viewport: iPhone 17 Simulator, 402 × 874 pt, dark mode, English.

## Comparison

- The language page follows the selected compact hierarchy: shared circular back control, follow-device card, native language names, restrained selection controls, and persistent-save note.
- The help center follows the selected support funnel: FAQ search, three high-frequency categories, primary ticket CTA, and ticket history area.
- The ticket form uses real categories, subject and details fields, diagnostic consent, validation, and asynchronous submission.
- The conversation implementation follows the confirmed alignment: support avatar and messages on the left; current-user avatar and messages on the right.
- Runtime values and localized English copy intentionally differ from the Chinese concept copy.

## Findings

- No P0, P1, or P2 visual defects were found at the tested viewport.
- All language options fit without clipping; Arabic remains visible and uses its native label.
- Help center hierarchy, card borders, icon scale, CTA, and safe-area spacing match the selected design direction.
- The local backend was not running during visual QA, so the ticket list correctly rendered its retry state. Ticket conversation rendering was verified from the compiled view implementation rather than a live backend response.

## Interaction checks

- Profile → Language navigation: passed.
- Language follow-device selected state: passed.
- Profile → Help & Feedback navigation: passed.
- Help center → Create Ticket: passed.
- Disabled submit state before valid input: passed.
- Live ticket creation, reply delivery, and resolution: not run because the backend was intentionally not started.

## Verification

- `xcodebuild -quiet -project RelaxShort.xcodeproj -scheme RelaxShort -configuration Debug -destination 'platform=iOS Simulator,id=99782FD0-C497-439F-B95E-949E6AB85F1C' build`
- Result: `BUILD SUCCEEDED`

final result: passed
