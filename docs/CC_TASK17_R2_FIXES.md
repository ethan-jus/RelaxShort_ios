# CC Task17 R2 Fixes: Reachable Debug Smoke Panel

**Branch**: continue on `task/task17-ios-real-api-smoke`.
**Owner**: CC implements. Codex reviews.
**Review source**: `docs/CODEX_REVIEW_TASK17_R1.md`.

## Goal

Fix Task17 so the DEBUG-only real API smoke panel is actually usable from the app, and clean up false/stale documentation.

## Required Fixes

1. Wire `DebugSettingsView` into a DEBUG-only reachable route.
   - Preferred route: `ProfileView` -> `SettingsView`.
   - Add a visible DEBUG-only row/button such as `Developer: API Smoke`.
   - Present `DebugSettingsView` through a sheet or navigation destination.
   - Must be guarded by `#if DEBUG` so Release builds do not expose it.

2. Clean whitespace.
   - Remove trailing whitespace in `RelaxShort.xcodeproj/project.pbxproj`.
   - `git diff --check main...HEAD` must pass.

3. Clean stale memory/docs.
   - `AGENTS.md` must not say `HomeViewModel` still casts to `RealHomeRepository`.
   - `docs/TASK17_DELIVERY_REPORT.md` must list both commits from R1 and the new R2 commit after you commit.
   - The delivery report must clearly state whether real smoke was actually run.

4. Add mandatory ECC usage record.
   - Check `claude plugin list`.
   - Use relevant ECC capabilities if available:
     - `swiftui-patterns` for the DEBUG-only settings route.
     - `swift-protocol-di-testing` or `swift-reviewer` for protocol cleanup review.
     - `swift-build-resolver` or `build-error-resolver` if build fails.
     - `security-reviewer` or `security-review` to confirm no secrets/token/baseURL credentials are committed.
   - If an ECC capability cannot be invoked in this environment, write the real reason. Do not fake usage.

## Forbidden

- Do not expose debug controls in Release.
- Do not hardcode production URLs, tokens, passwords, or private server credentials.
- Do not remove Mock mode.
- Do not claim live smoke success unless it was run against a reachable backend and the report includes baseURL plus step results.
- Do not rewrite unrelated UI.

## Verification

Run:

```bash
git diff --check main...HEAD
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If simulator UI testing is possible, launch Debug build and verify:

- Profile -> Settings shows the DEBUG-only developer/API smoke entry.
- Tapping it opens `DebugSettingsView`.

## Delivery

Commit your fixes. Report:

- Branch
- Commit hash
- Changed files
- Verification results
- ECC usage record
- Whether live smoke was run, skipped, or blocked
