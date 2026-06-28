import Foundation

// MARK: - Rank Drama Model

/// 排行榜专用模型，包含排名、热度等排行榜特有字段。
/// 可从 `DramaItem` 转换而来，保持与现有数据层兼容。
struct RankDrama: Identifiable {
    let id: String
    let rank: Int
    let title: String
    let coverURL: String
    let category: String
    let tags: [String]
    /// 热度值，如 "25.3K"、"19.9K"
    let hot: String
    /// 原始 DramaItem，用于导航到播放页
    let drama: DramaItem

    /// 从 RankingEntry 创建排行榜条目
    init(entry: RankingEntry) {
        self.id = entry.drama.id
        self.rank = entry.rankPosition
        self.title = entry.drama.title
        self.coverURL = entry.drama.coverURL
        self.category = entry.drama.category
        self.tags = entry.drama.tags
        self.hot = RankingMetricFormatter.string(from: entry.metricValue)
        self.drama = entry.drama
    }

    /// 从 `DramaItem` 创建排行榜条目（Mock 降级）
    init(from drama: DramaItem, rank: Int) {
        self.id = drama.id
        self.rank = rank
        self.title = drama.title
        self.coverURL = drama.coverURL
        self.category = drama.category
        self.tags = drama.tags
        self.hot = RankingMetricFormatter.string(from: Int64(drama.viewCount))
        self.drama = drama
    }
}

// MARK: - Rank Category

/// R3: API type 与 display title 分离
enum RankCategory: CaseIterable, Identifiable {
    case hot, trending, new
    var id: String { apiType }
    var apiType: String {
        switch self {
        case .hot: "trending"; case .trending: "top_searched"; case .new: "new_releases"
        }
    }
    var title: String {
        switch self {
        case .hot: "Most Trending"; case .trending: "Top Searched"; case .new: "New Releases"
        }
    }
}
