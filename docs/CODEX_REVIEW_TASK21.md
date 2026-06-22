# Codex Review: Task21 iOS Guest/Profile Auth State Consistency

Date: 2026-06-22
Branch: `main`

## Verdict

PASS.

Task21 fixes the observed P1 inconsistency:

- My List and Profile now agree when logged out.
- Profile no longer displays mock user state while logged out.
- Login CTA opens the existing login flow.
- Explicit guest/mock login still transitions to the existing logged-in Profile menu.

## Evidence

Commands:

```bash
git diff --check
xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Results:

```text
git diff --check: PASS
xcodebuild: BUILD SUCCEEDED
```

Simulator smoke:

- launched with `use_real_api=true`
- local backend base URL `http://127.0.0.1:8080`
- cleared stored login state
- Profile displayed only guest/login content
- no visible `ER`, `u_mock_001`, wallet, or logout in logged-out state
- tapping login opened `LoginView`
- guest login switched Profile to logged-in content

## Notes

CC did not finish with a report/commit. Codex completed review, localization coverage, verification, and documentation.

Real OAuth and real backend profile/auth integration are intentionally out of scope and should be scheduled separately.

