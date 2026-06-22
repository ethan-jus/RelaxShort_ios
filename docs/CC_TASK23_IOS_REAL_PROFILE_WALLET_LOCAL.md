# CC Task 23: iOS Real Profile and Wallet Local API Smoke

## Context

Backend Task22 is now reviewed and pushed. The backend `local` profile supports:

- `GET /api/v2/users/me`
- `GET /api/v2/users/me/wallet`
- `PATCH /api/v2/users/me/preferences`

All three require `X-User-Id: 1` for local smoke. This is a dev/local bridge only, not production auth.

iOS Task21 fixed logged-out Profile state, but `ProfileView` still creates `MockProfileRepository()` directly and `DependencyContainer` still injects `MockProfileRepository` by default even when `use_real_api=true`. So real API mode cannot smoke the Profile/Wallet path yet.

## Goal

When `use_real_api=true`, `api_base_url=http://127.0.0.1:8080`, and the user is logged in via the existing guest/mock login, Profile should load user/profile/wallet data from backend local API instead of mock data.

Required real-mode display facts:

- nickname/display should derive from backend `Local Guest`
- ID should derive from backend `user_id=1`
- wallet coin balance should derive from backend `balance=50`
- VIP should be inactive because backend returns `vip.active=false`

Logged-out behavior from Task21 must remain unchanged.

## Scope

Work only in `ios/v1.0.0`.

Allowed changes:

- `RelaxShort/Core/Services/APIEndpoint.swift`
- `RelaxShort/Core/Services/APIClient.swift` only if strictly needed for headers/error handling
- `RelaxShort/Core/Services/DependencyContainer.swift`
- `RelaxShort/Core/Services/RepositoryProtocols.swift`
- new real profile repository / DTO files under existing service/model patterns
- `RelaxShort/ViewModels/ProfileViewModel.swift`
- `RelaxShort/Views/Profile/ProfileView.swift`
- `RelaxShort/Core/Stores/AuthStore.swift` only if needed to sync coin/VIP/currentUser after real profile load
- project file membership if new Swift files are added
- docs delivery report

Do not:

- implement real Apple/Google/Facebook OAuth
- implement JWT/session production auth
- change backend code
- change payment/VIP purchase behavior
- display mock user while logged out
- remove mock mode
- hardcode production secrets or tokens

## Required Design

### 1. API endpoints

Add real v2 endpoints to `APIEndpoint`:

- `case userMe`
- `case userWallet`
- optional `case updateUserPreferences(...)` only if used by this task

Map paths:

- `/api/v2/users/me`
- `/api/v2/users/me/wallet`
- `/api/v2/users/me/preferences`

These must use `APIConfig.baseURL` in real mode.

### 2. Local `X-User-Id`

For local real API smoke, requests to user endpoints must include:

```text
X-User-Id: 1
```

Recommended rule:

- only add `X-User-Id` to user/profile/wallet endpoints
- derive it from `StorageService.shared.userId` if set
- fallback to `"1"` only when `UserDefaults.standard.bool(forKey: "use_real_api") == true`

This keeps the bridge scoped and visible. Do not send `X-User-Id` to every endpoint unless existing backend requires it.

### 3. DTOs and mapping

Add DTOs matching backend snake_case after `JSONDecoder.convertFromSnakeCase`:

`GET /api/v2/users/me` data:

```json
{
  "user_id": 1,
  "nickname": "Local Guest",
  "role": "user",
  "vip_level": 0,
  "status": 1,
  "preferences": {
    "ui_language": "en",
    "content_language": "en",
    "subtitle_language": "en",
    "default_quality": "720p"
  }
}
```

`GET /api/v2/users/me/wallet` data:

```json
{
  "user_id": 1,
  "balance": 50.0,
  "total_earned": 100.0,
  "total_spent": 50.0,
  "vip": {
    "active": false,
    "vip_level": 0
  }
}
```

Map into existing `User` UI model conservatively:

- `id = String(userId)`
- `nickname = nickname`
- `avatarURL = nil` unless backend provides it
- `isVip = wallet.vip.active`
- `vipExpireDate = parsed expiresAt if present`
- `coinBalance = Int(wallet.balance.rounded(.down))`
- keep other fields at current mock-safe defaults

Do not force `displayName` to initials only if the current UI can show full nickname without layout risk. If changing Profile header text from initials to nickname is small and safe, do it; otherwise document it as follow-up.

### 4. Repository and DI

Add `RealProfileRepository: ProfileRepositoryProtocol`.

Implementation should call both:

- `client.requestData(.userMe)`
- `client.requestData(.userWallet)`

Then merge into `User`.

Update `DependencyContainer` so `profileRepository` is `RealProfileRepository()` when `use_real_api=true`, unless explicitly injected.

Update `ProfileView` so its default `ProfileViewModel` uses `DependencyContainer.profileRepository` instead of hardcoding `MockProfileRepository()`.

If direct EnvironmentObject access cannot happen inside `init`, use one of these approaches:

- make `MainTabView` pass a `ProfileViewModel(repository: dependencies.profileRepository)`, or
- change `ProfileView` initializer to require a repository/viewModel from parent, preserving preview compatibility.

Use the smallest change that keeps dependency injection explicit.

### 5. AuthStore sync

After `ProfileViewModel.loadProfile()` succeeds in logged-in state, the visible wallet/menu should reflect real balance and VIP:

- `authStore.coinBalance` should become `50`
- `authStore.isVip` should become `false`
- `authStore.currentUser` should reflect the fetched user

Do this without creating an update loop. Acceptable approaches:

- ProfileView observes `viewModel.profile` and calls existing `authStore.updateCoins` / `authStore.updateVipStatus`, plus a small AuthStore helper if currentUser needs updating.
- ProfileViewModel exposes loaded `User` and view layer syncs AuthStore.

Do not mark logged-out users as logged in just because real API mode is enabled.

## Required Tests / Verification

### Static checks

Run:

```bash
git diff --check
rg -n "ProfileViewModel\\(repository: MockProfileRepository\\(\\)|profileRepository: ProfileRepositoryProtocol = MockProfileRepository\\(\\)|case \\.userProfile" RelaxShort
```

Expected:

- no whitespace errors
- no production Profile entry hardcoding mock repository in real-mode path
- old mock `.userProfile` can remain only for mock endpoint compatibility, not used by `RealProfileRepository`

### Build

Run:

```bash
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If this fails because simulator/runtime is unavailable, record the exact error. Do not claim build passed.

### Local backend smoke

Assume backend is running:

```bash
cd /Users/ethan/myspance/relaxshort/app-server/v2
mvn spring-boot:run -Dspring-boot.run.profiles=local
```

Then configure simulator:

```bash
xcrun simctl spawn booted defaults write com.relaxshort.ios use_real_api -bool true
xcrun simctl spawn booted defaults write com.relaxshort.ios api_base_url -string http://127.0.0.1:8080
xcrun simctl spawn booted defaults write com.relaxshort.ios isLoggedIn -bool true
xcrun simctl spawn booted defaults write com.relaxshort.ios userId -string 1
```

Smoke requirement:

- open app
- Profile logged-in state loads backend data
- Profile does not show `ER` or `u_mock_001`
- wallet/menu balance shows `50` or `@50`
- VIP membership state is non-VIP
- logged-out state still shows guest/login view and does not load/display mock profile

If Simulator UI automation is unavailable, record the blocker and provide curl + build evidence.

## ECC Usage

Use ECC where available:

- `swiftui-patterns`
- `swift-protocol-di-testing`
- `swift-concurrency-6-2`
- `api-design`
- `security-reviewer` for the `X-User-Id` local bridge
- `swift-reviewer`
- `swift-build-resolver` if build fails

If ECC commands are unavailable in terminal mode, record that and perform equivalent manual checklist.

## Delivery

Commit all changes.

Create `docs/TASK23_DELIVERY_REPORT.md` with:

- changed files
- API endpoints added
- DTO mapping summary
- DI changes
- ECC usage record
- exact verification commands/results
- simulator smoke result or exact blocker
- remaining risks, especially that `X-User-Id` is dev/local only

