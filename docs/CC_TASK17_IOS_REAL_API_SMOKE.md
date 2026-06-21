# CC Task17: iOS Real API Smoke & Debug Readiness

**Branch**: create `task/task17-ios-real-api-smoke` from latest `main`.
**Owner**: CC implements. Codex reviews.
**Goal**: make real API runtime verification repeatable and observable without changing product UI layout.

## Background

Task16 is merged to `main`. iOS now has real API paths for app init, For You, Home, Search, Ranking, Categories, Series Episodes, and Episode Play.

Current risks:

- Real mode depends on manual `UserDefaults` keys: `use_real_api`, `api_base_url`.
- There is no visible/debuggable runtime snapshot of active API mode, baseURL, app init language context, and last request failures.
- AppInit runs during splash but does not block main UI. This is acceptable, but smoke testing must make it clear whether language/country context has been populated before Home/Search/Ranking requests.
- `HomeViewModel` still uses `repository as? RealHomeRepository` for category-series loading. This is a P2 cleanup but should be fixed now if the change is small and safe.

## Scope

Implement a developer-only real API smoke readiness layer.

### 1. Real API Debug Settings

Add a debug-only lightweight settings entry that can be reached in simulator/dev builds without affecting release product UX.

Acceptable implementation options:

- A small DEBUG-only overlay/button in an existing settings/profile/dev area if one already exists.
- A DEBUG-only SwiftUI sheet reachable from a non-production gesture or visible debug control.

Do not redesign main UI. Do not expose this in Release builds.

The debug panel must show and allow changing:

- `use_real_api` boolean
- `api_base_url` string
- current effective `APIConfig.baseURL`
- `app_ui_language`
- `app_content_language`
- `app_country_code`
- `app_matched_language`
- `app_fallback_reason`

It must include actions:

- Save settings
- Reset to Mock
- Run App Init
- Run Real API Smoke

### 2. Smoke Runner

Add a small `RealAPISmokeRunner` service for DEBUG builds.

It should sequentially verify:

1. `POST /api/v2/app/init`
2. `GET /api/v2/feed/for-you`
3. `GET /api/v2/home`
4. `GET /api/v2/categories`
5. If categories has at least one backend category, `GET /api/v2/categories/{code}/series`
6. `GET /api/v2/search/default`
7. `GET /api/v2/search?q=love&limit=20`
8. `GET /api/v2/rankings?type=popular`
9. If For You/Home returns a usable series id, `GET /api/v2/series/{id}/episodes`
10. If an episode id exists, `GET /api/v2/episodes/{id}/play`

The result model must capture:

- step name
- URL or endpoint description
- status: success/failure/skipped
- count/id summary where useful
- error message
- duration

Do not require login for this task. If an endpoint returns an expected auth error, mark it clearly. The above endpoints should be anonymous if backend supports current contract.

### 3. Protocol Cleanup

If low risk, move `fetchDramasByCategoryCode(code:)` into `HomeRepositoryProtocol`:

- `RealHomeRepository` implements backend call.
- protocol default implementation can return local fallback or `fetchDramas(category: .all)` for mock.
- `HomeViewModel` must not cast to `RealHomeRepository`.

If this becomes invasive, stop and report instead of forcing it.

### 4. Documentation

Update:

- `AGENTS.md`: Task17 status, debug settings usage, smoke command/path.
- `docs/TASK17_DELIVERY_REPORT.md`: changed files, verification commands, smoke behavior, known remaining gaps.

Do not leave placeholders such as "本次", "待补", "TODO hash". If commit hash is not known yet, fill it after commit in a docs-only follow-up commit.

## Forbidden

- Do not hardcode server credentials, tokens, MySQL/Redis passwords, or production secrets.
- Do not commit private IP credentials or bearer tokens.
- Do not change Release product behavior or expose debug controls in Release.
- Do not remove Mock mode.
- Do not claim real API smoke passed unless it was actually run against a reachable backend and the report includes baseURL and step results.

## Verification Required

Run:

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Also run the app in simulator if possible and execute the smoke panel. If simulator execution is not possible from CC environment, state that clearly and provide exact manual steps.

## Delivery

Deliver:

- Branch name
- Commit hash
- `docs/TASK17_DELIVERY_REPORT.md`
- Build result
- Smoke result or clear reason it could not be run
- Any blockers requiring Codex/user decision
