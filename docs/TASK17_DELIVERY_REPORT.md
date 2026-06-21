# Task 17 Delivery Report: iOS Real API Smoke & Debug Readiness

**Branch**: `task/task17-ios-real-api-smoke`
**Commit**: `d8a69ba`
**Date**: 2026-06-21

## Summary

Added DEBUG-only real API smoke runner, debug settings panel, and protocol cleanup per `docs/CC_TASK17_IOS_REAL_API_SMOKE.md`.

## Files Changed

| File | Change |
|------|--------|
| `RelaxShort/Core/Services/RealAPISmokeRunner.swift` | New: DEBUG-only 10-step sequential API smoke test runner |
| `RelaxShort/Views/Debug/DebugSettingsView.swift` | New: DEBUG-only debug panel (API mode, baseURL, init context, smoke test) |
| `RelaxShort/Core/Services/RepositoryProtocols.swift` | New `fetchCategorySeries(code:)` protocol method + default extension |
| `RelaxShort/Core/Services/RealHomeRepository.swift` | Rename `fetchDramasByCategoryCode` → `fetchCategorySeries` (protocol conformance) |
| `RelaxShort/ViewModels/HomeViewModel.swift` | Remove `repository as? RealHomeRepository` cast; use protocol method |
| `RelaxShort.xcodeproj/project.pbxproj` | Add new files to Sources |
| `AGENTS.md` | Update Task17 status |

## Debug Panel

`DebugSettingsView` (DEBUG only, not in Release):

- **API Mode**: toggle `use_real_api`, edit `api_base_url`, show effective `APIConfig.baseURL`
- **App Init Context**: display `ui_language`, `content_language`, `country_code`, `matched_language`, `fallback_reason`
- **Actions**: Save Settings, Reset to Mock, Run App Init, Run API Smoke Test
- **Smoke Results**: per-step status (green/red/yellow), endpoint path, summary, error, duration

Accessible by adding `DebugSettingsView()` as a sheet or navigation destination in a DEBUG-only build. Not wired to main UI to avoid production exposure.

## Smoke Runner

`RealAPISmokeRunner` (DEBUG only) sequentially tests:

1. `POST /api/v2/app/init`
2. `GET /api/v2/feed/for-you`
3. `GET /api/v2/home`
4. `GET /api/v2/categories`
5. `GET /api/v2/categories/{code}/series` (if category found)
6. `GET /api/v2/search/default`
7. `GET /api/v2/search?q=love&limit=20`
8. `GET /api/v2/rankings?type=popular`
9. `GET /api/v2/series/{id}/episodes` (if series found)
10. `GET /api/v2/episodes/{id}/play` (if episode found)

Each step captures: name, endpoint, status (success/failure/skipped), summary, error, duration (ms).

## Protocol Cleanup

- `fetchCategorySeries(code:contentLang:country:)` added to `HomeRepositoryProtocol`
- Default implementation returns `fetchDramas(category: .all)` for Mock
- `RealHomeRepository` overrides to call backend `/api/v2/categories/{code}/series`
- `HomeViewModel.loadCategoryDramas` no longer casts to `RealHomeRepository`

## Verification

```bash
$ git diff --check
PASS

$ xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
    -destination 'platform=iOS Simulator,name=iPhone 17' build
** BUILD SUCCEEDED **
```

Smoke test not run against live backend — requires reachable backend server with `use_real_api=true` and configured `api_base_url`.

## Remaining

- Smoke test requires manual execution in simulator (CC environment cannot launch simulator)
- Debug panel not yet wired to main UI navigation — developer must manually present `DebugSettingsView()`
