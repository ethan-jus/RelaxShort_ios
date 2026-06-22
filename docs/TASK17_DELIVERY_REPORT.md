# Task 17 Delivery Report: iOS Real API Smoke & Debug Readiness

**Branch**: `task/task17-ios-real-api-smoke`
**Commits**:
- R1: `d8a69ba` — initial implementation (smoke runner, debug panel, protocol cleanup)
- R1 docs: `a540054`, `ec726d9`
- R2: `5ce2e05` — Codex R1 review fixes (wire DebugSettingsView, whitespace, docs)

**Date**: 2026-06-21 (R1), 2026-06-22 (R2)

## Summary

Added DEBUG-only real API smoke runner, debug settings panel, and protocol cleanup per `docs/CC_TASK17_IOS_REAL_API_SMOKE.md`. R2 fixes per `docs/CODEX_REVIEW_TASK17_R1.md` and `docs/CC_TASK17_R2_FIXES.md`.

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
| `docs/TASK17_DELIVERY_REPORT.md` | This report (updated R2) |

### R2 Fixes (per `docs/CC_TASK17_R2_FIXES.md`)

| File | Change |
|------|--------|
| `RelaxShort/Views/Profile/ProfileView.swift` | SettingsView: add DEBUG-only "Developer: API Smoke" row + sheet presentation |
| `RelaxShort.xcodeproj/project.pbxproj` | Clean trailing whitespace (4 lines) |
| `AGENTS.md` | Remove stale `HomeViewModel as? RealHomeRepository` mention |
| `docs/TASK17_DELIVERY_REPORT.md` | Add R2 commits, live smoke status, ECC usage record |

## Debug Panel

`DebugSettingsView` (DEBUG only, not in Release):

- **API Mode**: toggle `use_real_api`, edit `api_base_url`, show effective `APIConfig.baseURL`
- **App Init Context**: display `ui_language`, `content_language`, `country_code`, `matched_language`, `fallback_reason`
- **Actions**: Save Settings, Reset to Mock, Run App Init, Run API Smoke Test
- **Smoke Results**: per-step status (green/red/yellow), endpoint path, summary, error, duration

Accessible via Profile → Settings → "Developer: API Smoke" (DEBUG-only, `#if DEBUG` guarded). Sheet-presented `DebugSettingsView`.

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

### R2

```bash
$ git diff --check               # working tree vs HEAD
PASS (no whitespace issues)

$ git diff --check main...HEAD
PASS
```

```bash
$ xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
    -destination 'platform=iOS Simulator,name=iPhone 17' build
** BUILD SUCCEEDED **
```

### R1

```bash
$ git diff --check
PASS

$ xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort \
    -destination 'platform=iOS Simulator,name=iPhone 17' build
** BUILD SUCCEEDED **
```

Smoke test not run against live backend — requires reachable backend server with `use_real_api=true` and configured `api_base_url`.

## ECC Usage

| ECC 命令/agent/skill | 用途 | 影响的实现/测试 |
|----------------------|------|-----------------|
| Explore agent | 分析 ProfileView、SettingsView、DebugSettingsView 导航结构 | 选择 Profile → Settings 的 DEBUG-only 入口 |
| swiftui-patterns | 任务要求的 SwiftUI 调试入口设计参考 | 将入口限定在 SettingsView 的 `#if DEBUG` 区块 |
| security-reviewer / security-review | 敏感信息自检要求 | 未写入 token、密码、生产 URL 或服务器凭据 |

Note: CC 的 `claude plugin list` 在其执行环境中被权限拦截；Codex 已在工作空间确认 `ecc@ecc` 安装并启用。

## Remaining

- Smoke test requires manual execution in simulator (CC environment cannot launch simulator)
- Simulator UI verification (Profile → Settings → Developer entry) requires manual testing
