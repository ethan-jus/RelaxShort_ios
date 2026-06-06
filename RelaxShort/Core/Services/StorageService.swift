import Foundation

// MARK: - StorageService

/// 持久化存储服务，封装 `UserDefaults` 与模拟 Keychain。
///
/// 设计原则：
/// - `UserDefaults` 存放非敏感数据（偏好设置、缓存等）
/// - Keychain（Phase 1 以 UserDefaults 模拟）存放敏感数据（Token）
///
/// ## 使用示例
/// ```swift
/// StorageService.shared.accessToken = "eyJhbG..."
/// if StorageService.shared.isLoggedIn { ... }
/// ```
final class StorageService {

    // MARK: - Singleton

    /// 共享单例
    static let shared = StorageService()

    // MARK: - Keys

    private enum Key: String {
        case isLoggedIn
        case userId
        case userProfileData
        case loginMethod
        case selectedLanguage
        case hasSeenOnboarding
        case lastLaunchVersion
        // -- 模拟 Keychain --
        case accessToken
        case refreshToken
    }

    // MARK: - Stores

    private let defaults: UserDefaults
    /// 模拟 Keychain 存储（Phase 1 用 UserDefaults，Phase 2 迁移到 Security.framework）
    private let secureStore: UserDefaults

    // MARK: - Init

    private init() {
        self.defaults = .standard
        // 使用独立的 suite 隔离“敏感”数据
        self.secureStore = UserDefaults(suiteName: "com.relaxshort.ios.secure") ?? .standard
    }

    // MARK: - UserDefaults (非敏感)

    /// 用户是否已登录
    var isLoggedIn: Bool {
        get { defaults.bool(forKey: Key.isLoggedIn.rawValue) }
        set {
            defaults.set(newValue, forKey: Key.isLoggedIn.rawValue)
            if !newValue {
                // 登出时清除所有登录态数据
                clearAuthData()
            }
        }
    }

    /// 当前用户 ID
    var userId: String? {
        get { defaults.string(forKey: Key.userId.rawValue) }
        set { defaults.set(newValue, forKey: Key.userId.rawValue) }
    }

    /// 缓存的用户资料 JSON Data
    var userProfileData: Data? {
        get { defaults.data(forKey: Key.userProfileData.rawValue) }
        set { defaults.set(newValue, forKey: Key.userProfileData.rawValue) }
    }

    /// 登录方式（ggest/默认不存）
    var loginMethod: LoginMethod? {
        get {
            guard let raw = defaults.string(forKey: Key.loginMethod.rawValue) else { return nil }
            return LoginMethod(rawValue: raw)
        }
        set {
            if let method = newValue {
                defaults.set(method.rawValue, forKey: Key.loginMethod.rawValue)
            } else {
                defaults.removeObject(forKey: Key.loginMethod.rawValue)
            }
        }
    }

    /// 用户选择的语言
    var selectedLanguage: String {
        get { defaults.string(forKey: Key.selectedLanguage.rawValue) ?? "zh-Hans" }
        set { defaults.set(newValue, forKey: Key.selectedLanguage.rawValue) }
    }

    /// 是否已展示过新手引导
    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasSeenOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasSeenOnboarding.rawValue) }
    }

    /// 上次启动的 App 版本号（用于版本迁移逻辑）
    var lastLaunchVersion: String? {
        get { defaults.string(forKey: Key.lastLaunchVersion.rawValue) }
        set { defaults.set(newValue, forKey: Key.lastLaunchVersion.rawValue) }
    }

    // MARK: - 模拟 Keychain (Phase 1 用 UserDefaults)

    /// 访问令牌（Phase 2 接入 Security.framework Keychain）
    var accessToken: String? {
        get { secureStore.string(forKey: Key.accessToken.rawValue) }
        set { secureStore.set(newValue, forKey: Key.accessToken.rawValue) }
    }

    /// 刷新令牌
    var refreshToken: String? {
        get { secureStore.string(forKey: Key.refreshToken.rawValue) }
        set { secureStore.set(newValue, forKey: Key.refreshToken.rawValue) }
    }

    // MARK: - Helpers

    /// 清除所有认证相关数据（登出时调用）
    func clearAuthData() {
        userId = nil
        userProfileData = nil
        loginMethod = nil
        accessToken = nil
        refreshToken = nil
        isLoggedIn = false
        defaults.synchronize()
        secureStore.synchronize()
    }

    /// 清除所有本地数据（用于调试/重置）
    func clearAll() {
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        if let secureDomain = secureStore.persistentDomain(forName: "com.relaxshort.ios.secure") {
            secureDomain.keys.forEach { secureStore.removeObject(forKey: $0) }
        }
        defaults.synchronize()
        secureStore.synchronize()
    }
}
