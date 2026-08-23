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

    /// 语言目录可覆盖的本地名称；没有服务端名称时回退到 App 内置名称。
    var catalogNativeDisplayName: String {
        let names = UserDefaults.standard.dictionary(forKey: "app_supported_language_native_names") as? [String: String]
        return names?[rawValue] ?? nativeDisplayName
    }

    /// 后端语言目录启用且当前 App 已随包提供资源的语言。
    /// 未完成 app/init 时保留本地完整列表，避免冷启动期间语言设置页为空。
    static var enabledForCurrentCatalog: [AppLanguage] {
        guard let codes = UserDefaults.standard.array(forKey: "app_supported_ui_languages") as? [String],
              !codes.isEmpty else {
            return allCases
        }
        let enabled = allCases.filter { codes.contains($0.rawValue) }
        return enabled.isEmpty ? allCases : enabled
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

// MARK: - Content Language Preference

/// 内容语言与界面语言是两个独立维度。默认跟随界面语言；保留手动模式，
/// 以后可在不改请求层合同的前提下支持“中文界面看英文剧”。
enum ContentLanguageMode: String {
    case followUI = "follow_ui"
    case manual
}

enum ContentLanguagePreference {
    private enum Keys {
        static let mode = "app_content_language_mode"
        static let language = "app_content_language"
        static let countryCode = "app_country_code"
    }

    private static var defaults: UserDefaults { .standard }

    static var mode: ContentLanguageMode {
        defaults.string(forKey: Keys.mode)
            .flatMap(ContentLanguageMode.init(rawValue:)) ?? .followUI
    }

    static var effectiveLanguage: String {
        switch mode {
        case .followUI:
            return AppLocalization.currentLanguage.rawValue
        case .manual:
            return defaults.string(forKey: Keys.language)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? AppLocalization.currentLanguage.rawValue
        }
    }

    static var countryCode: String? {
        defaults.string(forKey: Keys.countryCode)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 界面语言切换后，仅在 follow_ui 模式同步有效内容语言。
    static func synchronizeWithUILanguage() {
        guard mode == .followUI else { return }
        defaults.set(ContentLanguageMode.followUI.rawValue, forKey: Keys.mode)
        defaults.set(AppLocalization.currentLanguage.rawValue, forKey: Keys.language)
    }

    /// app/init 负责国家决策；内容语言只在手动模式尚无选择时采用服务端值。
    static func applyAppInit(contentLanguage: String, countryCode: String) {
        if defaults.object(forKey: Keys.mode) == nil {
            defaults.set(ContentLanguageMode.followUI.rawValue, forKey: Keys.mode)
        }
        switch mode {
        case .followUI:
            defaults.set(AppLocalization.currentLanguage.rawValue, forKey: Keys.language)
        case .manual:
            if defaults.string(forKey: Keys.language)?.isEmpty != false {
                defaults.set(contentLanguage, forKey: Keys.language)
            }
        }
        defaults.set(countryCode, forKey: Keys.countryCode)
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
        ContentLanguagePreference.synchronizeWithUILanguage()
    }

    @discardableResult
    func followDeviceLanguage() -> AppLanguage {
        followsDeviceLanguage = true
        language = AppLanguage.preferred()
        applyRTLLayout()
        save()
        ContentLanguagePreference.synchronizeWithUILanguage()
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
