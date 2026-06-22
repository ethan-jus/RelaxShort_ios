# CC Task 21: iOS Guest/Profile Auth State Consistency

## Context

After Task20, local backend + iOS smoke works for Home, For You, and Player.

Current P1 issue:

- `My List` correctly treats the user as not logged in and shows a login guide.
- `Profile` incorrectly shows mock user `ER / u_mock_001`, wallet, logout, and membership actions while the same app session is not logged in.

This breaks real API smoke credibility and can mislead monetization/auth work.

## Goal

Make `Profile` auth state consistent with `My List`:

- when `authStore.isLoggedIn == false`, Profile must show a guest/login state, not mock user data
- when logged in, Profile may show existing profile menu
- real API mode must not automatically fetch/show `MockProfileRepository` data for a logged-out user

## Scope

Work only in `ios/v1.0.0`.

Likely files:

- `RelaxShort/Views/Profile/ProfileView.swift`
- `RelaxShort/Core/Services/DependencyContainer.swift`
- `RelaxShort/Core/Services/MockAPIRepository.swift` only if needed
- localization files only if new visible strings are required
- docs under `docs/`

Allowed:

- add a logged-out Profile view that matches the dark, compact style of `My List`
- present existing `LoginView` from Profile login CTA
- hide logout/wallet/user-id when logged out
- avoid loading profile repository when logged out

Do not:

- implement real OAuth or Apple/Google auth in this task
- modify backend
- change payment/VIP purchase flows
- remove mock login support for explicit mock-mode testing
- fake successful login

## Required Behavior

### Logged Out

When `authStore.isLoggedIn == false`:

- no mock nickname/user id such as `ER` or `u_mock_001`
- no logout button
- no wallet balance as if it belonged to a user
- show clear login CTA
- login CTA opens existing `LoginView`
- bottom tab remains stable

### Logged In

When `authStore.isLoggedIn == true`:

- existing profile header/menu remains usable
- logout still works and returns Profile to logged-out state

### Repository Loading

`ProfileView` must not call `viewModel.loadProfile()` while logged out.

If `ProfileViewModel` currently defaults to mock profile data, guard it at the view layer or update dependency injection so logged-out state cannot display it.

## Verification

Run:

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Simulator smoke with local backend running:

```bash
xcrun simctl spawn booted defaults write com.relaxshort.ios use_real_api -bool true
xcrun simctl spawn booted defaults write com.relaxshort.ios api_base_url -string http://127.0.0.1:8080
xcrun simctl spawn booted defaults write com.relaxshort.ios isLoggedIn -bool false || true
xcrun simctl terminate booted com.relaxshort.ios || true
xcrun simctl launch booted com.relaxshort.ios
```

Verify:

- My List shows logged-out/login state.
- Profile also shows logged-out/login state.
- Profile does not show `ER`, `u_mock_001`, wallet, or logout while logged out.
- Login CTA opens `LoginView`.

Optional:

- use guest/mock login from `LoginView`, confirm Profile switches to logged-in state.
- logout returns to guest state.

## ECC Usage

Use ECC where available:

- `swiftui-patterns`
- `swift-reviewer`
- `swift-build-resolver` if build fails
- checklist/review for auth state consistency

If ECC commands are unavailable in terminal mode, record that and perform the equivalent manual checklist.

## Delivery

Commit all changes.

Create `docs/TASK21_DELIVERY_REPORT.md` with:

- changed files
- exact behavior changes
- ECC usage record
- verification commands/results
- simulator smoke notes/screenshots if run
- remaining risks

