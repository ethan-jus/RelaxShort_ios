import Foundation

// MARK: - APIConfig

/// 后端 baseURL 配置。
/// Debug 默认 `http://127.0.0.1:8080`，可通过 UserDefaults 键 `api_base_url` 覆盖。
/// 生产环境通过环境变量或 Info.plist 注入，不硬编码 IP。
enum APIConfig {

    /// UserDefaults 键，用于运行时覆盖 baseURL
    static let overrideKey = "api_base_url"

    /// 当前有效 baseURL
    static var baseURL: String {
        // 1. UserDefaults 运行时覆盖（Debug 可切换服务器）
        if let override = UserDefaults.standard.string(forKey: overrideKey), !override.isEmpty {
            return override.hasSuffix("/") ? String(override.dropLast()) : override
        }
        // 2. Debug 默认本地开发服务器
        #if DEBUG
        return "http://127.0.0.1:8080"
        #else
        // 3. Release 由 Info.plist 或环境变量注入（不可硬编码生产地址）
        if let envURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !envURL.isEmpty {
            return envURL.hasSuffix("/") ? String(envURL.dropLast()) : envURL
        }
        return "http://127.0.0.1:8080"
        #endif
    }
}
