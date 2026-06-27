import SwiftUI

/// Search 默认页固定榜单的产品语义和视觉主题。
enum SearchRankTheme: Int, CaseIterable, Hashable, Identifiable {
    case topSearched
    case mostTrending
    case newReleases

    var id: Self { self }

    var apiType: String {
        switch self {
        case .topSearched:
            return "trending"
        case .mostTrending:
            return "popular"
        case .newReleases:
            return "new"
        }
    }

    var title: String {
        switch self {
        case .topSearched:
            return L10n.topSearchedTab
        case .mostTrending:
            return L10n.mostTrendingTab
        case .newReleases:
            return L10n.newReleasesTab
        }
    }

    var topRankGradientColors: [Color] {
        switch self {
        case .topSearched:
            return [Color(hex: "#4A0618"), .black]
        case .mostTrending:
            return [Color(hex: "#432816"), .black]
        case .newReleases:
            return [Color(hex: "#194333"), .black]
        }
    }

    var regularCardColor: Color {
        Color(hex: "#101011")
    }
}
