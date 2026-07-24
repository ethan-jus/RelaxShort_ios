import SwiftUI

private enum AppPreferenceKey {
    static let language = "app.language"
    static let followsDeviceLanguage = "app.language.followsDevice"
}

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

    var nativeDisplayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ko: return "한국어"
        case .ja: return "日本語"
        case .pt: return "Português"
        case .es: return "Español"
        case .ar: return "العربية"
        }
    }

    /// 是否 RTL 语言
    var isRTL: Bool {
        self == .ar
    }

    /// 首次启动跟随设备的首选语言；不支持的语言统一回退英文。
    static func preferred(from identifiers: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in identifiers {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("zh") {
                let usesTraditionalChinese =
                    normalized.contains("hant")
                    || normalized.contains("-tw")
                    || normalized.contains("-hk")
                    || normalized.contains("-mo")
                return usesTraditionalChinese ? .zhHant : .zhHans
            }
            if normalized.hasPrefix("en") { return .en }
            if normalized.hasPrefix("ko") { return .ko }
            if normalized.hasPrefix("ja") { return .ja }
            if normalized.hasPrefix("pt") { return .pt }
            if normalized.hasPrefix("es") { return .es }
            if normalized.hasPrefix("ar") { return .ar }
        }
        return .en
    }
}

// MARK: - Localization Runtime

/// 全 App 唯一的文案查找入口。
/// 用户选择优先于设备语言，目标语言缺键时只回退英文，避免中英文混杂。
enum AppLocalization {
    private static let fallbackMarker = "\u{0010}RELAXSHORT_MISSING\u{0010}"

    static var currentLanguage: AppLanguage {
        if UserDefaults.standard.bool(forKey: AppPreferenceKey.followsDeviceLanguage) {
            return AppLanguage.preferred()
        }
        if let saved = UserDefaults.standard.string(forKey: AppPreferenceKey.language),
           let language = AppLanguage(rawValue: saved) {
            return language
        }
        return AppLanguage.preferred()
    }

    static var locale: Locale {
        Locale(identifier: currentLanguage.rawValue)
    }

    static func text(_ key: String, arguments: [CVarArg] = []) -> String {
        let selected = localizedBundle(for: currentLanguage)
        let selectedValue = selected?.localizedString(
            forKey: key,
            value: fallbackMarker,
            table: nil
        ) ?? fallbackMarker

        let template: String
        if selectedValue != fallbackMarker {
            template = selectedValue
        } else {
            let english = localizedBundle(for: .en)
            template = english?.localizedString(forKey: key, value: key, table: nil) ?? key
        }

        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: locale, arguments: arguments)
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
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
    @Published private(set) var followsDeviceLanguage: Bool

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let themeMode = "app.themeMode"
        static let language = AppPreferenceKey.language
        static let followsDeviceLanguage = AppPreferenceKey.followsDeviceLanguage
    }

    private init() {
        let savedTheme = defaults.string(forKey: Keys.themeMode)
        self.themeMode = savedTheme.flatMap(ThemeMode.init(rawValue:)) ?? .dark

        let savedLang = defaults.string(forKey: Keys.language)
        let hasFollowDevicePreference =
            defaults.object(forKey: Keys.followsDeviceLanguage) != nil
        let followsDeviceLanguage = hasFollowDevicePreference
            ? defaults.bool(forKey: Keys.followsDeviceLanguage)
            : savedLang == nil
        self.followsDeviceLanguage = followsDeviceLanguage
        self.language = followsDeviceLanguage
            ? AppLanguage.preferred()
            : savedLang.flatMap(AppLanguage.init(rawValue:))
                ?? AppLanguage.preferred()
        applyRTLLayout()
    }

    private func save() {
        defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
        defaults.set(language.rawValue, forKey: Keys.language)
        defaults.set(
            followsDeviceLanguage,
            forKey: Keys.followsDeviceLanguage
        )
    }

    func selectLanguage(_ language: AppLanguage) {
        followsDeviceLanguage = false
        self.language = language
        applyRTLLayout()
        save()
    }

    @discardableResult
    func followDeviceLanguage() -> AppLanguage {
        followsDeviceLanguage = true
        language = AppLanguage.preferred()
        applyRTLLayout()
        save()
        return language
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
