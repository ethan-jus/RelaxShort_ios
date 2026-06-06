import SwiftUI
import Combine

// MARK: - App Store
/// 管理全局应用状态：当前 Tab、通知红点、主题、语言等
@MainActor
final class AppStore: ObservableObject {
    @Published var selectedTab: Tab = .home
    @Published var hasUnreadNotification: Bool = false
    @Published var navigationTarget: SeriesPlayerNav?
    @Published var isShowingSearch = false
    @Published var isShowingMembership = false
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
            case .home: return "tab.home".localized
            case .forYou: return "tab.forYou".localized
            case .member: return "tab.member".localized
            case .myList: return "tab.myList".localized
            case .profile: return "tab.profile".localized
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

    /// 当前主题的 ColorScheme
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

// MARK: - String Extension for L10n

extension String {
    /// 便捷本地化方法 — 优先从 Bundle 读取 .strings，若返回 raw key 则回退到 L10n.zhFallback 硬编码中文
    var localized: String {
        let bundleValue = Bundle.main.localizedString(forKey: self, value: "\u{0010}FALLBACK\u{0010}", table: nil)
        if bundleValue != "\u{0010}FALLBACK\u{0010}" {
            return bundleValue
        }
        // 回退：使用 L10n 枚举内部的硬编码字典
        return L10nFallback.value(for: self) ?? self
    }
}

/// L10n 回退字典的公开暴露（供 String.localized 使用）
enum L10nFallback {
    fileprivate static func value(for key: String) -> String? {
        return fallbackDict[key]
    }

    private static let fallbackDict: [String: String] = [
        "tab.home": "Home",
        "tab.forYou": "For You",
        "tab.member": "Member",
        "tab.myList": "My List",
        "tab.profile": "Profile",
    ]
}
