import Foundation

/// 收藏模型 — 记录用户收藏的短剧
struct Bookmark: Codable, Identifiable {
    /// 收藏记录唯一标识
    let id: String
    /// 关联的短剧信息
    let drama: DramaItem
    /// 是否已收藏
    var isBookmarked: Bool
    /// 收藏时间
    var bookmarkedAt: Date

    // MARK: - Computed Properties

    /// 是否是新收藏（24小时内）
    var isNewBookmark: Bool {
        let interval = Date().timeIntervalSince(bookmarkedAt)
        return interval < 24 * 60 * 60
    }

    /// 相对时间描述
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: bookmarkedAt, relativeTo: Date())
    }

    /// 收藏状态文案
    var statusText: String {
        isBookmarked ? "已收藏" : "已取消收藏"
    }
}
