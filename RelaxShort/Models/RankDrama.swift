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

    /// 从 `DramaItem` 创建排行榜条目
    init(from drama: DramaItem, rank: Int) {
        self.id = drama.id
        self.rank = rank
        self.title = drama.title
        self.coverURL = drama.coverURL
        self.category = drama.category
        self.tags = drama.tags
        self.hot = drama.formattedViewCount
        self.drama = drama
    }
}

// MARK: - Rank Category

/// 排行榜子榜单类型
enum RankCategory: String, CaseIterable, Identifiable {
    case hot     = "热播榜"
    case trending = "热搜榜"
    case new     = "新剧榜"

    var id: String { rawValue }
}
