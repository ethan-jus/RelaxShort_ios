import Foundation

// MARK: - APIConfig

/// 后端 baseURL 配置。
/// Debug 构建会由 Xcode 脚本把 Mac 当前局域网地址写入构建产物；手动地址只有显式开启后才生效。
/// 生产环境通过环境变量或 Info.plist 注入，不硬编码 IP。
enum APIConfig {

    /// UserDefaults 键，用于保存手动覆盖地址。
    static let overrideKey = "api_base_url"
    /// UserDefaults 键，用于区分自动地址与手动覆盖地址。
    static let manualOverrideEnabledKey = "api_base_url_manual_override_enabled"

    /// 构建时注入的地址；Debug 没有局域网地址时回退到本机地址。
    static var automaticBaseURL: String {
        if let injected = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !injected.isEmpty {
            return normalized(injected)
        }
        return "http://127.0.0.1:8080"
    }

    /// 当前有效 baseURL
    static var baseURL: String {
        #if DEBUG
        // Debug 只有主动开启“手动覆盖”时才读取旧的 UserDefaults 地址，避免网络变化后继续使用旧 IP。
        if UserDefaults.standard.bool(forKey: manualOverrideEnabledKey),
           let override = UserDefaults.standard.string(forKey: overrideKey),
           !override.isEmpty {
            return normalized(override)
        }
        return automaticBaseURL
        #else
        // Release 只读取正式构建注入的地址，不使用开发者本地覆盖。
        if let envURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !envURL.isEmpty {
            return normalized(envURL)
        }
        return "http://127.0.0.1:8080"
        #endif
    }

    private static func normalized(_ value: String) -> String {
        value.hasSuffix("/") ? String(value.dropLast()) : value
    }
}
