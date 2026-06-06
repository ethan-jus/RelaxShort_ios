import Foundation

/// 观看历史记录模型 — 记录用户观看过的短剧及进度
struct WatchHistoryItem: Codable, Identifiable {
    /// 观看记录唯一标识
    let id: String
    /// 关联的短剧信息
    let drama: DramaItem
    /// 当前观看到的集数
    var currentEpisode: Int
    /// 最近一次观看时间
    var watchedAt: Date
    /// 当前集观看进度 (0.0 ~ 1.0)
    var progress: Double
    
    // MARK: - Computed Properties
    
    /// 是否已完成当前集（进度 ≥ 95%）
    var isCurrentEpisodeFinished: Bool {
        progress >= 0.95
    }
    
    /// 格式化进度百分比，如 "78%"
    var formattedProgress: String {
        String(format: "%.0f%%", progress * 100)
    }
    
    /// 相对时间描述，如 "刚刚"、"3分钟前"、"昨天"
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: watchedAt, relativeTo: Date())
    }
}
