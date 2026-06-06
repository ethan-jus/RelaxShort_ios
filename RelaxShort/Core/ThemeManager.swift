import SwiftUI

// MARK: - Theme Mode

/// 应用主题模式
enum ThemeMode: String, CaseIterable {
    case system   // 跟随系统
    case light    // 强制浅色
    case dark     // 强制深色

    var displayName: String {
        switch self {
        case .system: return L10n.themeSystem
        case .light:  return L10n.themeLight
        case .dark:   return L10n.themeDark
        }
    }

    /// 转换为 SwiftUI ColorScheme?
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Language

/// 应用语言
enum AppLanguage: String, CaseIterable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en     = "en"
    case ko     = "ko"
    case ja     = "ja"
    case pt     = "pt"
    case es     = "es"
    case ar     = "ar"

    var displayName: String {
        switch self {
        case .zhHans: return L10n.langZhHans
        case .zhHant: return L10n.langZhHant
        case .en:     return L10n.langEn
        case .ko:     return L10n.langKo
        case .ja:     return L10n.langJa
        case .pt:     return L10n.langPt
        case .es:     return L10n.langEs
        case .ar:     return L10n.langAr
        }
    }

    /// 是否 RTL 语言
    var isRTL: Bool {
        self == .ar
    }
}

// MARK: - Theme Manager

/// 集中管理主题和语言设置
/// 通过 UserDefaults 持久化，支持实时切换
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var themeMode: ThemeMode {
        didSet { save() }
    }
    @Published var language: AppLanguage {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let themeMode = "app.themeMode"
        static let language = "app.language"
    }

    private init() {
        let savedTheme = defaults.string(forKey: Keys.themeMode)
        self.themeMode = savedTheme.flatMap(ThemeMode.init(rawValue:)) ?? .dark

        let savedLang = defaults.string(forKey: Keys.language)
        self.language = savedLang.flatMap(AppLanguage.init(rawValue:)) ?? .zhHans
    }

    private func save() {
        defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
        defaults.set(language.rawValue, forKey: Keys.language)
    }

    /// 获取当前 ColorScheme
    var preferredColorScheme: ColorScheme? {
        themeMode.colorScheme
    }

    /// 应用 RTL 布局
    func applyRTLLayout() {
        let semantic: UISemanticContentAttribute = language.isRTL
            ? .forceRightToLeft
            : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = semantic
    }

    /// 获取 Apple 语言代码
    var appleLanguageCode: String {
        language.rawValue
    }
}
