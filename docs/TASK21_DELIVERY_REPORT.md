# Task21 Delivery Report: iOS Guest/Profile Auth State Consistency

Date: 2026-06-22
Branch: `main`

## Summary

Profile now matches My List auth state behavior:

- logged-out Profile shows a guest/login state
- logged-out Profile no longer shows mock user `ER`, `u_mock_001`, wallet, or logout
- login CTA opens the existing `LoginView`
- after guest/mock login, Profile returns to the existing logged-in menu
- `ProfileView` only loads profile data inside logged-in content

CC started this task and produced the initial implementation, but did not create a final delivery report or commit. Codex reviewed, completed multilingual localization coverage, verified, and committed.

## Changed Files

- `docs/CC_TASK21_IOS_GUEST_PROFILE_STATE.md`
- `docs/TASK21_DELIVERY_REPORT.md`
- `RelaxShort/Views/Profile/ProfileView.swift`
- `RelaxShort/Utils/LocalizationHelper.swift`
- all existing `Localizable.strings` resources:
  - `Base`
  - `en`
  - `zh-Hans`
  - `zh-Hant`
  - `es`
  - `pt`
  - `ja`
  - `ko`
  - `ar`

## Implementation Details

- Split `ProfileView.body` into logged-in and guest branches based on `authStore.isLoggedIn`.
- Added `guestProfileContent` with a login CTA and no user-owned menu state.
- Added `showLoginSheet` to present existing `LoginView`.
- Kept existing logged-in Profile menu behavior.
- Added `profile.login_to_view` and `profile.login_to_sync` localization keys to all language resources.

## ECC Usage Record

- ECC plugin state was checked by the automation wrapper before task execution.
- CC did not complete its own final ECC report.
- Codex performed manual review for:
  - SwiftUI auth-state branching
  - localization coverage across existing languages
  - no backend/API/payment/OAuth scope expansion
  - logged-out state not loading/displaying mock profile

## Verification

Build:

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Result:

```text
BUILD SUCCEEDED
```

Diff check:

```bash
git diff --check
```

Result: passed.

Simulator smoke:

- Forced `use_real_api=true`.
- Forced `api_base_url=http://127.0.0.1:8080`.
- Cleared simulator auth state:
  - `isLoggedIn=false`
  - removed `userProfileData`
  - removed `loginMethod`
- Launched app.
- Profile showed guest/login state.
- Profile did not show `ER`, `u_mock_001`, wallet, or logout.
- Login CTA opened `LoginView`.
- Guest login switched Profile to the logged-in menu.

## Remaining Risks

- Google/Apple/Facebook real OAuth remains mock-backed and must be handled by a later auth integration task.
- Logged-in profile still uses mock auth/profile data after explicit mock/guest login. This is acceptable for the current task because the goal was logged-out consistency.

