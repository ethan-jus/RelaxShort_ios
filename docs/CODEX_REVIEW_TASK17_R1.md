# Codex Review: Task17 R1

**Branch**: `task/task17-ios-real-api-smoke`
**Reviewed head**: `a540054`
**Date**: 2026-06-22
**Decision**: FAIL

## Findings

### P0: Debug panel is not reachable from the app

Task17 required a developer-only settings entry that can be reached in simulator/dev builds. `DebugSettingsView` exists and is in the Xcode target, but the delivery report says it is "not wired to main UI". That leaves the smoke runner unusable without editing code manually.

Required fix:

- Add a DEBUG-only route to `DebugSettingsView`.
- Preferred location: Profile -> Settings, because `ProfileView` already has a Settings destination.
- The entry must be wrapped in `#if DEBUG` and must not appear in Release builds.

### P1: Verification report is false

`docs/TASK17_DELIVERY_REPORT.md` says `git diff --check` passed, but current range fails:

```text
RelaxShort.xcodeproj/project.pbxproj:388: trailing whitespace.
RelaxShort.xcodeproj/project.pbxproj:525: trailing whitespace.
RelaxShort.xcodeproj/project.pbxproj:757: trailing whitespace.
RelaxShort.xcodeproj/project.pbxproj:759: trailing whitespace.
```

Required fix:

- Remove trailing whitespace.
- Re-run `git diff --check main...HEAD` or `git diff --check`.
- Update the report truthfully.

### P1: AGENTS.md contains contradictory stale Task16 follow-up

`AGENTS.md` now says Task17 moved `fetchCategorySeries` into `HomeRepositoryProtocol`, but still says:

```text
当前 P2 follow-up：HomeViewModel 仍通过 repository as? RealHomeRepository ...
```

Required fix:

- Remove the stale P2 follow-up.
- Replace it with the actual remaining state after Task17.

### P2: Delivery report is incomplete

The delivery report only lists the first code commit (`d8a69ba`) while docs were committed separately (`a540054`). It also lacks the mandatory ECC usage record required by the task protocol.

Required fix:

- List all Task17 commits.
- Add an `ECC 使用记录` section.
- Do not claim real smoke passed unless it is actually run against a reachable backend.

## Verification Required For R2

Run:

```bash
git diff --check main...HEAD
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If possible, run the app and verify the DEBUG-only path to `DebugSettingsView` is visible in Debug and unavailable by construction in Release.
