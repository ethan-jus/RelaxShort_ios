# CC Task13: iOS Real API Phase 1

**分支**: `task/task13-ios-real-api-phase1`
**项目**: `ios/v1.0.0`
**后端合同**: `app-server/v2/docs/IOS_API_CONTRACT_V1.md`

## 目标

把 iOS 从纯 Mock 推进到第一个可验证的真实 API 闭环：
1. App 启动调用 `POST /api/v2/app/init`
2. For You 页面调用 `GET /api/v2/feed/for-you`
3. Series Player 通过 `GET /api/v2/series/{seriesId}/episodes` + `GET /api/v2/episodes/{episodeId}/play` 获取播放

保留 Mock fallback。

## 范围

只做 P0 闭环，不接入支付、广告奖励、搜索、榜单、收藏、钱包、用户中心全量接口。

## 实现清单

1. 网络基础设施：APIConfig + APIResponseEnvelope + APIClient（envelope-aware）
2. APIEndpoint 重构：新增 real v2 case（appInit/forYou/seriesEpisodes/episodePlay）
3. DTO：AppInitResponseDTO / ForYouFeedResponseDTO / SeriesEpisodesResponseDTO / EpisodePlayResponseDTO / PlayerMediaSource
4. Repository：RealHomeRepository + RealDetailRepository
5. App 启动：AppInitService
6. DI：DependencyContainer Mock/Real 开关
