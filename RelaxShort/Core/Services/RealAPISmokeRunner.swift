import Foundation

// MARK: - Smoke Result

struct SmokeStepResult: Identifiable {
    let id = UUID()
    let step: String
    let endpoint: String
    let status: SmokeStatus
    let summary: String
    let errorMessage: String?
    let durationMs: Int

    enum SmokeStatus: String { case success, failure, skipped }
}

// MARK: - Smoke Runner

/// DEBUG-only 真实 API 冒烟测试。顺序执行一组后端接口并收集结果。
/// Release 构建应通过 #if DEBUG 排除。
#if DEBUG
@MainActor
final class RealAPISmokeRunner: ObservableObject {

    @Published var isRunning = false
    @Published var results: [SmokeStepResult] = []
    @Published var currentStep = ""

    private let client = APIClient.shared

    func run() async {
        isRunning = true
        results = []
        currentStep = ""

        let lang = UserDefaults.standard.string(forKey: "app_content_language") ?? "en"
        let country = UserDefaults.standard.string(forKey: "app_country_code") ?? "GLOBAL"
        var lastSeriesId: Int64?
        var lastEpisodeId: Int64?
        var lastCategoryCode: String?

        // 1. App Init
        await step("App Init", "POST /api/v2/app/init") {
            let dto: AppInitResponseDTO = try await self.client.requestData(.appInit)
            return "ui=\(dto.uiLanguage) content=\(dto.contentLanguage) country=\(dto.countryCode)"
        }

        // 2. For You
        await step("For You", "GET /api/v2/feed/for-you") {
            let dto: ForYouFeedResponseDTO = try await self.client.requestData(
                .forYou(cursor: nil, limit: 5, contentLanguage: lang, countryCode: country)
            )
            if let first = dto.items?.first { lastSeriesId = first.seriesId }
            return "items=\(dto.items?.count ?? 0) hasMore=\(dto.hasMore ?? false)"
        }

        // 3. Home
        await step("Home", "GET /api/v2/home") {
            let dto: HomeResponseDTO = try await self.client.requestData(
                .home(contentLanguage: lang, countryCode: country)
            )
            return "tabs=\(dto.tabs?.count ?? 0)"
        }

        // 4. Categories
        await step("Categories", "GET /api/v2/categories") {
            let dto: CategoriesResponseDTO = try await self.client.requestData(
                .categories(contentLanguage: lang, countryCode: country)
            )
            if let first = dto.items?.first { lastCategoryCode = first.code }
            return "categories=\(dto.items?.count ?? 0)"
        }

        // 5. Category Series
        if let catCode = lastCategoryCode {
            await step("Category Series", "GET /api/v2/categories/\(catCode)/series") {
                let dto: SearchResponseDTO = try await self.client.requestData(
                    .categorySeries(categoryCode: catCode, cursor: nil, limit: 5,
                                    contentLanguage: lang, countryCode: country)
                )
                return "items=\(dto.items?.count ?? 0)"
            }
        } else {
            await addResult("Category Series", "GET /api/v2/categories/{code}/series",
                          .skipped, "no category code from categories step", nil, 0)
        }

        // 6. Search Default
        await step("Search Default", "GET /api/v2/search/default") {
            let dto: SearchDefaultResponseDTO = try await self.client.requestData(
                .searchDefault(contentLanguage: lang, countryCode: country)
            )
            return "hotSeries=\(dto.hotSeries?.count ?? 0) suggestions=\(dto.suggestions?.count ?? 0)"
        }

        // 7. Search V2
        await step("Search V2", "GET /api/v2/search?q=love") {
            let dto: SearchResponseDTO = try await self.client.requestData(
                .searchV2(query: "love", cursor: nil, limit: 20, contentLanguage: lang, countryCode: country)
            )
            return "items=\(dto.items?.count ?? 0) hasMore=\(dto.hasMore ?? false)"
        }

        // 8. Rankings
        await step("Rankings", "GET /api/v2/rankings?type=popular") {
            let dto: RankingResponseDTO = try await self.client.requestData(
                .rankings(type: "popular", contentLanguage: lang, countryCode: country)
            )
            if let first = dto.items.first { lastSeriesId = lastSeriesId ?? first.card.seriesId }
            return "items=\(dto.items.count)"
        }

        // 9. Series Episodes
        if let sid = lastSeriesId {
            await step("Series Episodes", "GET /api/v2/series/\(sid)/episodes") {
                let dto: SeriesEpisodesResponseDTO = try await self.client.requestData(
                    .seriesEpisodes(seriesId: String(sid))
                )
                if let first = dto.episodes?.first { lastEpisodeId = first.episodeId }
                return "episodes=\(dto.episodes?.count ?? 0)"
            }
        } else {
            await addResult("Series Episodes", "GET /api/v2/series/{id}/episodes",
                          .skipped, "no series id from prior steps", nil, 0)
        }

        // 10. Episode Play
        if let eid = lastEpisodeId {
            await step("Episode Play", "GET /api/v2/episodes/\(eid)/play") {
                let dto: EpisodePlayResponseDTO = try await self.client.requestData(
                    .episodePlay(episodeId: String(eid))
                )
                return "sourceType=\(dto.sourceType ?? "?") cdnStatus=\(dto.cdnReadyStatus ?? -1)"
            }
        } else {
            await addResult("Episode Play", "GET /api/v2/episodes/{id}/play",
                          .skipped, "no episode id from prior steps", nil, 0)
        }

        isRunning = false
    }

    private func step(_ name: String, _ endpoint: String, _ body: @escaping () async throws -> String) async {
        currentStep = name
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let summary = try await body()
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            await addResult(name, endpoint, .success, summary, nil, ms)
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            await addResult(name, endpoint, .failure, "failed", error.localizedDescription, ms)
        }
    }

    @MainActor
    private func addResult(_ name: String, _ endpoint: String, _ status: SmokeStepResult.SmokeStatus,
                           _ summary: String, _ error: String?, _ ms: Int) {
        results.append(SmokeStepResult(step: name, endpoint: endpoint, status: status,
                                        summary: summary, errorMessage: error, durationMs: ms))
    }
}
#endif
