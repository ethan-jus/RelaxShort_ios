import Foundation

/// 仅保存非敏感应用偏好。认证 token 统一由 `AuthKeychainStore` 管理。
final class StorageService {
    static let shared = StorageService()

    private enum Key: String {
        case selectedLanguage
        case hasSeenOnboarding
        case lastLaunchVersion
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedLanguage: String {
        get { defaults.string(forKey: Key.selectedLanguage.rawValue) ?? "zh-Hans" }
        set { defaults.set(newValue, forKey: Key.selectedLanguage.rawValue) }
    }

    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasSeenOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasSeenOnboarding.rawValue) }
    }

    var lastLaunchVersion: String? {
        get { defaults.string(forKey: Key.lastLaunchVersion.rawValue) }
        set { defaults.set(newValue, forKey: Key.lastLaunchVersion.rawValue) }
    }

    func clearAll() {
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        try? AuthKeychainStore.shared.deleteRefreshToken()
    }
}
