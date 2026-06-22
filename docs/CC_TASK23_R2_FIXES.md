# CC Task 23 R2: Finish iOS Real Profile and Wallet Smoke

> **For agentic workers:** Execute this task visibly in the user's terminal. Do not run as a hidden background automation. Do not commit unless the user explicitly asks after Codex review.

## Goal

Finish the current Task23 half-done iOS changes so real API mode can load Profile and Wallet data from the backend local/dev API.

Expected behavior when `use_real_api=true`, `api_base_url=http://127.0.0.1:8080`, and the app is logged in:

- Profile uses `GET /api/v2/users/me` and `GET /api/v2/users/me/wallet`.
- User display derives from backend user `Local Guest` / `user_id=1`.
- Wallet display derives from backend balance `50`.
- VIP state is inactive when backend returns `vip.active=false`.
- Logged-out Profile behavior from Task21 remains unchanged.

## Current State

There are already uncommitted Task23 changes in this repository. Treat them as work-in-progress, not as final code.

Known changed files:

- `RelaxShort.xcodeproj/project.pbxproj`
- `RelaxShort/Core/Services/APIEndpoint.swift`
- `RelaxShort/Core/Services/DependencyContainer.swift`
- `RelaxShort/Core/Services/RealProfileRepository.swift`
- `RelaxShort/Models/API/UserProfileResponseDTO.swift`
- `RelaxShort/ViewModels/ProfileViewModel.swift`
- `RelaxShort/Views/MainTabView.swift`
- `RelaxShort/Views/Profile/ProfileView.swift`

Do not revert these files wholesale. Review the diff and fix forward.

## Hard Scope

Only work in:

- `/Users/ethan/myspance/relaxshort/ios/v1.0.0`

Do not:

- Modify backend code.
- Implement Apple/Google/Facebook OAuth.
- Implement JWT/session production auth.
- Touch DramaBox UI redesign or screenshot matching in this task.
- Remove mock mode.
- Add production secrets or tokens.
- Commit automatically.

## Required Fixes

### 1. Normalize Profile dependency injection

`MainTabView` already passes:

```swift
ProfileView(viewModel: ProfileViewModel(repository: dependencies.profileRepository))
```

Keep this as the main app path.

Fix `ProfileView.init(viewModel:)` so it does not create `RealProfileRepository()` directly for production app routing. The default initializer should be a safe fallback for preview/simple construction only.

Recommended final shape:

```swift
init(viewModel: ProfileViewModel? = nil) {
    let vm = viewModel ?? ProfileViewModel(repository: MockProfileRepository())
    _viewModel = StateObject(wrappedValue: vm)
}
```

Reason: real/mock selection belongs in `DependencyContainer`; `ProfileView` should not duplicate DI decisions.

### 2. Add an AuthStore helper for loaded profile sync

In `RelaxShort/Core/Stores/AuthStore.swift`, add a small public method:

```swift
func applyLoadedProfile(_ user: User) {
    currentUser = user
    isVip = user.isVipValid
    vipExpireDate = user.vipExpireDate
    coinBalance = user.coinBalance
    storage.userId = user.id
    persistUser()
}
```

Use this helper instead of directly assigning `authStore.coinBalance`, `authStore.isVip`, `authStore.vipExpireDate`, and `authStore.currentUser` in the view.

### 3. Update ProfileView sync code

In `RelaxShort/Views/Profile/ProfileView.swift`, change the `onChange(of: viewModel.profile)` handler to:

```swift
.onChange(of: viewModel.profile) { _, newProfile in
    guard let user = newProfile, authStore.isLoggedIn else { return }
    authStore.applyLoadedProfile(user)
}
```

Keep the logged-out guard. Real API mode must not mark a logged-out user as logged in.

### 4. Verify RealProfileRepository mapping

Keep `RealProfileRepository` conservative:

- `id = String(profile.userId)`
- `nickname = profile.nickname ?? "Guest"`
- `avatarURL = nil`
- `isVip = wallet.vip?.active ?? false`
- `vipExpireDate = wallet.vip?.expiresAt.flatMap(parseISO8601)`
- `coinBalance = Int(wallet.balance rounded down)`
- other fields stay mock-safe defaults

If the current `Decimal` conversion builds cleanly, it may remain. If it fails, use:

```swift
let coinBalance = wallet.balance.map { NSDecimalNumber(decimal: $0).intValue } ?? 0
```

### 5. Keep APIEndpoint local bridge scoped

Keep `X-User-Id` injection limited to:

- `.userMe`
- `.userWallet`
- `.updateUserPreferences`

Fallback to `"1"` only when `use_real_api=true` and `StorageService.shared.userId` is nil.

Do not send `X-User-Id` to every endpoint.

### 6. Add delivery report

Create `docs/TASK23_DELIVERY_REPORT.md` with:

- changed files
- API endpoints added
- DTO mapping summary
- DI changes
- AuthStore sync behavior
- exact verification commands and results
- local smoke result or exact blocker
- remaining risk: `X-User-Id` is only a dev/local bridge, not production auth

## Required Verification

Run from `/Users/ethan/myspance/relaxshort/ios/v1.0.0`:

```bash
git diff --check
rg -n "ProfileViewModel\\(repository: MockProfileRepository\\(\\)|profileRepository: ProfileRepositoryProtocol = MockProfileRepository\\(\\)|case \\.userProfile" RelaxShort
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected:

- `git diff --check` has no output.
- `rg` may only find old mock endpoint compatibility such as `case .userProfile`; it must not find production Profile routing that hardcodes `MockProfileRepository()` in the real app path.
- `xcodebuild` passes, or the exact simulator/runtime error is recorded.

If the backend is running in IDEA on port 8080, also smoke:

```bash
curl -fsS -H 'X-User-Id: 1' http://127.0.0.1:8080/api/v2/users/me
curl -fsS -H 'X-User-Id: 1' http://127.0.0.1:8080/api/v2/users/me/wallet
```

Then configure simulator only if a simulator is already booted:

```bash
xcrun simctl spawn booted defaults write com.relaxshort.ios use_real_api -bool true
xcrun simctl spawn booted defaults write com.relaxshort.ios api_base_url -string http://127.0.0.1:8080
xcrun simctl spawn booted defaults write com.relaxshort.ios isLoggedIn -bool true
xcrun simctl spawn booted defaults write com.relaxshort.ios userId -string 1
```

Manual UI smoke:

- Profile logged-in state loads backend data.
- It does not show mock user `ER` or `u_mock_001`.
- Wallet/menu balance shows `50` or `@50`.
- VIP membership state is non-VIP.
- Logged-out state still shows guest/login UI.

## Delivery Format

When done, report in Chinese:

- files changed
- commands run and exact result
- whether build passed
- whether backend curl smoke passed or why it was skipped
- whether simulator UI smoke passed or exact blocker
- remaining risks

Do not commit. Leave the diff for Codex review.
