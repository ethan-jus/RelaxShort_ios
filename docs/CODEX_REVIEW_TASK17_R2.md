# Codex Review: Task17 R2

**Branch**: `task/task17-ios-real-api-smoke`
**Reviewed head**: `e79527d`
**Date**: 2026-06-22
**Decision**: PASS

## Result

Task17 R2 passes review.

R2 fixed the blocking issue from R1: `DebugSettingsView` is now reachable in DEBUG builds through Profile → Settings → `Developer: API Smoke`. The route is guarded by `#if DEBUG`.

## Verification

```bash
git diff --check main...HEAD
# PASS

xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
# ** BUILD SUCCEEDED **
```

Simulator UI verification:

- Installed the Debug build into the booted iPhone 17 simulator.
- Opened Profile → Settings.
- Confirmed `Developer: API Smoke` is visible.
- Confirmed tapping it presents `DebugSettingsView`.

## Remaining

Live smoke test is not complete yet because the local backend is not currently running for this review. Next task should start the backend locally, set `api_base_url`, enable `use_real_api`, and run the 10-step smoke test from the app.
