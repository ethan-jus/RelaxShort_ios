import SwiftUI
import Combine

// MARK: - 应用状态
/// 管理全局应用状态：当前标签、通知红点、主题、语言等
@MainActor
final class AppStore: ObservableObject {
    @Published var selectedTab: Tab = .home
    @Published var hasUnreadNotification: Bool = false
    @Published var navigationTarget: SeriesPlayerNav?
    @Published var isShowingSearch = false
    @Published var isShowingMembership = false
    @Published var isShowingRewards = false
    @Published var pendingInviteCode: String?
    @Published var isBottomTabBarHidden = false
    @Published var isFirstLaunch: Bool
    @Published var themeMode: ThemeMode = ThemeManager.shared.themeMode {
        didSet { ThemeManager.shared.themeMode = themeMode }
    }
    @Published var language: AppLanguage = ThemeManager.shared.language {
        didSet {
            ThemeManager.shared.language = language
            ThemeManager.shared.applyRTLLayout()
        }
    }

    enum Tab: Int, CaseIterable {
        case home = 0
        case forYou
        case member
        case myList
        case profile

        var title: String {
            switch self {
            case .home: return "home.tab.title".localized
            case .forYou: return "recommend.tab.title".localized
            case .member: return "vip.tab.title".localized
            case .myList: return "favorites.tab.title".localized
            case .profile: return "profile.tab.title".localized
            }
        }

        var icon: String {
            switch self {
            case .home: return "house"
            case .forYou: return "play.rectangle"
            case .member: return "crown"
            case .myList: return "bookmark"
            case .profile: return "person"
            }
        }

        var selectedIcon: String {
            switch self {
            case .home: return "house.fill"
            case .forYou: return "play.rectangle.fill"
            case .member: return "crown.fill"
            case .myList: return "bookmark.fill"
            case .profile: return "person.fill"
            }
        }
    }

    /// 当前主题对应的配色方案
    var preferredColorScheme: ColorScheme? {
        themeMode.colorScheme
    }

    init() {
        let storage = StorageService.shared
        self.isFirstLaunch = (storage.lastLaunchVersion == nil)
        if isFirstLaunch {
            storage.lastLaunchVersion = Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        }
    }
}

// MARK: - 字符串本地化扩展

extension String {
    /// 便捷本地化方法。当前语言缺键时统一回退英文。
    var localized: String {
        AppLocalization.text(self)
    }

    func localizedFormat(_ arguments: CVarArg...) -> String {
        AppLocalization.text(self, arguments: arguments)
    }
}
