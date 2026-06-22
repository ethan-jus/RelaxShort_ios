# Task23 R2 Fixes — Delivery Report

> 日期：2026-06-22
> 执行代理：Claude Code (ECC)
> 目标目录：`ios/v1.0.0`

## 变更文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `RelaxShort/Views/Profile/ProfileView.swift` | 修改 | **Fix 1**: init 默认降级为 `MockProfileRepository()`，移除重复的 `DependencyContainer.useRealAPI` 判断；**Fix 3**: `onChange(of:)` 改用 `authStore.applyLoadedProfile(user)` |
| `RelaxShort/Core/Stores/AuthStore.swift` | 修改 | **Fix 2**: 新增 `applyLoadedProfile(_:)` 公开方法，同步后端 Profile 数据到 AuthStore（不改变登录状态） |
| `RelaxShort/Models/User.swift` | 修改 | **编译修复**: 添加 `Equatable` 协议遵循，使 `onChange(of:)` 可编译 |

### 已有 Task23 变更（非本任务新增，仅记录）

| 文件 | 说明 |
|------|------|
| `RelaxShort.xcodeproj/project.pbxproj` | 添加 `UserProfileResponseDTO.swift` / `RealProfileRepository.swift` 到项目 |
| `RelaxShort/Core/Services/APIEndpoint.swift` | 新增 `.userMe` / `.userWallet` / `.updateUserPreferences` 端点 + `X-User-Id` 头注入（仅限这三个端点） |
| `RelaxShort/Core/Services/DependencyContainer.swift` | Profile Repository 按 `use_real_api` 开关选择 Real/Mock |
| `RelaxShort/Core/Services/RealProfileRepository.swift` | 新文件：`ProfileRepositoryProtocol` 真实后端实现 |
| `RelaxShort/Models/API/UserProfileResponseDTO.swift` | 新文件：`UserProfileResponseDTO` / `WalletResponseDTO` / `WalletVipDTO` |
| `RelaxShort/ViewModels/ProfileViewModel.swift` | 新增 `avatarInitials` 计算属性、`displayName` guard 加固 |
| `RelaxShort/Views/MainTabView.swift` | `TabContentHost` 注入 `dependencies.profileRepository` 给 `ProfileView` |

## API 端点新增

| 端点 | 方法 | 路径 | X-User-Id |
|------|------|------|-----------|
| `userMe` | GET | `/api/v2/users/me` | ✅ |
| `userWallet` | GET | `/api/v2/users/me/wallet` | ✅ |
| `updateUserPreferences` | PATCH | `/api/v2/users/me/preferences` | ✅ |

## DTO 映射摘要

`RealProfileRepository.fetchUserProfile()` 并发请求 `/users/me` + `/users/me/wallet`，映射为 `User` UI 模型：

- `id` ← `String(profile.userId)`
- `nickname` ← `profile.nickname ?? "Guest"`
- `avatarURL` ← `nil`
- `isVip` ← `wallet.vip?.active ?? false`
- `vipExpireDate` ← `wallet.vip?.expiresAt.flatMap(parseISO8601)`（支持毫秒/无毫秒两种 ISO8601）
- `coinBalance` ← `wallet.balance.map { ($0 as NSDecimalNumber).intValue } ?? 0`
- 其他字段 ← mock-safe 默认值（0 / nil）

## DI 变更

- `DependencyContainer.profileRepository` 参数类型从 `ProfileRepositoryProtocol = MockProfileRepository()` 改为 `ProfileRepositoryProtocol? = nil`，nil 时根据 `use_real_api` 开关自动选择。
- `MainTabView` → `TabContentHost` → `ProfileView(viewModel: ProfileViewModel(repository: dependencies.profileRepository))` 为生产路径。
- `ProfileView.init(viewModel:)` 默认值降级为 `MockProfileRepository()`，仅用于 Preview / 简单构造。

## AuthStore 同步行为

- `applyLoadedProfile(_:)` 同步 `currentUser`、`isVip`、`vipExpireDate`、`coinBalance`、`storage.userId`。
- **不改变** `isLoggedIn` 和 `loginMethod`（这些仅由登录流程设置）。
- `ProfileView.onChange(of: viewModel.profile)` 通过 `guard authStore.isLoggedIn` 保护后调用此方法。

## 验证命令与结果

### 1. `git diff --check`
```
(无输出)
```
✅ 无空白问题。

### 2. `rg` 搜索硬编码 MockProfileRepository
```
RelaxShort/Core/Services/APIEndpoint.swift:110: case .userProfile: ...
RelaxShort/Views/Profile/ProfileView.swift:59: let vm = ... MockProfileRepository()
```
- `case .userProfile`：旧 mock 端点兼容保留 ✅
- `ProfileView.swift:59`：nil-coalescing 安全 fallback（仅 Preview 路径），生产路径由 `MainTabView` 注入 ✅

### 3. `xcodebuild` 构建
```
** BUILD SUCCEEDED **
```
✅ iPhone 17 Simulator (arm64) 构建通过。

### 4. 后端 curl smoke
```
curl: (7) Failed to connect to 127.0.0.1 port 8080
```
⏭ 后端未在 IDEA 中运行，跳过 curl smoke。

### 5. 模拟器配置
已配置 `com.relaxshort.ios` UserDefaults：
- `use_real_api` = true
- `api_base_url` = http://127.0.0.1:8080
- `isLoggedIn` = true
- `userId` = 1

### 6. 模拟器 UI smoke
⏭ 后端未运行，无法验证真实 API 数据加载。后端启动后预期行为：
- Profile 加载 `/api/v2/users/me` + `/api/v2/users/me/wallet`
- 不显示 mock 用户 `ER` 或 `u_mock_001`
- 钱包余额显示后端 `balance`（默认 50）
- VIP 状态非 VIP（`vip.active=false`）
- 未登录状态显示 guest/login UI（Task21 保持不变）

## 遗留风险

1. **`X-User-Id` 仅为 dev/local 桥接方案**，不是生产认证。生产环境需要 JWT Bearer token 传递用户身份。
2. **`RealProfileRepository.Decimal` 转换**：`($0 as NSDecimalNumber).intValue` 在当前构建通过，但极端大值可能溢出 `Int`。
3. **`UserProfileResponseDTO.userId: Int64`**：映射为 `String(profile.userId)`，与 `User.id: String` 类型一致，但精度依赖后端不返回超过 Int64 范围的值。
4. **无人值守 UI smoke**：后端未运行，无法完成端到端 Profile/Wallet 数据流验证。后端启动后需手动验证。
5. **`authStore.isLoggedIn` 语义**：当前 Profile 页依赖此 flag 区分登录/未登录 UI。在 real API 模式下，此 flag 由 mock 登录设置（`MockAuthProvider`），未与后端 session 状态同步。

## ECC 使用记录

- 无（本任务由主 Agent 直接执行，未调用 ECC 子 agent/skill）
