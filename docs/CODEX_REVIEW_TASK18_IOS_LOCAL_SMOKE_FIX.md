# Task18 iOS Local Smoke Fix Review

日期：2026-06-22

## 结论

PASS。

后端 Task18 local profile 启动后，iOS 首次真实联调暴露两个客户端问题：

1. `APIEndpoint.body` 对 GET 端点返回 `{}`，导致 CFNetwork 拒绝请求并报 `GET method must not have a body`。
2. 后端 local seed 中 `monetization.is_free` / `vip_required` 等 JSON 布尔值可能以 `0/1` 返回，iOS DTO 只按 `Bool` 解码导致 Home/Feed 解码失败。

## 修复

- `APIEndpoint.body`：GET/DELETE 返回 `nil`，POST/PUT/PATCH 保持 JSON body。
- `ForYouFeedResponseDTO`：新增数字/字符串/布尔兼容的 bool 解码 helper。
- `MonetizationDTO`、`QualityDTO`、`SubtitleDTO`、`EpisodeItemDTO`：兼容 `0/1`、`"0"/"1"`、`true/false`。

## 验证

- `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17' build`：PASS。
- 后端 `app-server/v2` 以 `local` profile 跑在 `127.0.0.1:8080`。
- iPhone 17 模拟器安装并启动 Debug 包。
- Home 页面已加载真实接口数据，显示 6 部 local seed 短剧。

## 剩余观察

- 首页封面图片 URL 使用 mock CDN，当前模拟器下载失败时显示占位图；这不阻断 API 联调，但后续需要接真实可访问媒资/CDN。
- `RealAPISmokeRunner` 仍有 `await` warning，不阻断编译，可在后续清理。
