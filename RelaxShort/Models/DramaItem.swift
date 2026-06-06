import Foundation

struct DramaItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let coverURL: String
    var videoURL: String? = nil
    let category: String
    let tags: [String]
    let viewCount: Int
    let episodeCount: Int
    let currentEpisode: Int
    let synopsis: String
    let isHot: Bool
    let isTrending: Bool
    let rating: Double
    /// 观看金币奖励数值
    var coinReward: Int = 0
    /// 卡片角标文案（如"你正在追"），nil 时不显示
    var badgeText: String? = nil
    /// 是否正在追剧中
    var isWatching: Bool { badgeText != nil }
    /// 卡片封面动态高度（瀑布流核心），默认 168pt（固定运营位统一高度）
    var imageHeight: CGFloat = 168
    /// 角标类型（new / hot / vip），nil 不显示
    var badge: BadgeType? = nil

    // MARK: - v1 DramaBox 复刻新增字段

    /// 国家/地区标签 (e.g. "China", "Korea")
    var regionTag: String? = nil
    /// 语言标签 (e.g. "Mandarin", "English")
    var languageTag: String? = nil
    /// 是否已关注
    var isFollowed: Bool = false
    /// 是否已收藏 (For You 收藏按钮)
    var isBookmarked: Bool = false
    /// 是否会员专属
    var isVIPOnly: Bool = false
    /// Legacy release-state flag, not shown in v1 UI
    var isComingSoon: Bool = false
    /// 金币解锁价格 (nil = 不能金币解锁)
    var coinPrice: Int? = nil
    /// 免费集范围 (e.g. 1...3)
    var freeEpisodeRange: ClosedRange<Int>? = nil
    /// 是否为会员专属剧
    var isMemberOnly: Bool = false

    /// 封面图 URL（别名，保持兼容）
    var imageName: String { coverURL }

    var formattedViewCount: String {
        if viewCount >= 1_000_000 {
            return String(format: "%.1fM", Double(viewCount) / 1_000_000)
        } else if viewCount >= 1_000 {
            return String(format: "%.0fK", Double(viewCount) / 1_000)
        }
        return "\(viewCount)"
    }

    var progressPercentage: Double? {
        guard episodeCount > 0 else { return nil }
        return Double(currentEpisode) / Double(episodeCount)
    }
}

// MARK: - Banner Item
struct BannerItem: Identifiable {
    let id: String
    let title: String
    let imageName: String
    let tags: [String]
    let dramaId: String
}

// MARK: - Badge Type
enum BadgeType: String, Codable, Hashable {
    case new, hot, vip
}

// MARK: - Category
enum DramaCategory: String, CaseIterable {
    case all = "全部"
    case modernRomance = "现代言情"
    case ancientCostume = "古装"
    case sweetPet = "甜宠"
    case revenge = "逆袭"
    case billionaire = "总裁"
    case urban = "都市"
    case fantasy = "玄幻"

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .modernRomance: return "heart"
        case .ancientCostume: return "crown"
        case .sweetPet: return "pawprint"
        case .revenge: return "flame"
        case .billionaire: return "briefcase"
        case .urban: return "building.2"
        case .fantasy: return "sparkles"
        }
    }
}
