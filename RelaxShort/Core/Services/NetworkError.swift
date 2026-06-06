import Foundation

// MARK: - NetworkError

/// 网络层统一错误类型，覆盖请求生命周期中所有可能的失败场景。
enum NetworkError: LocalizedError {
    /// URL 构造失败（传入的 URL 字符串非法）
    case invalidURL
    /// 服务器返回的响应无法解析为 HTTPURLResponse
    case invalidResponse
    /// HTTP 状态码不在 200..<300 范围内
    case badStatus(Int)
    /// JSON 解码失败，携带底层 DecodingError
    case decodingFailed(Error)
    /// 请求超时
    case networkTimeout
    /// 401 未授权，需要重新登录
    case unauthorized
    /// 网络不可达（NSURLErrorNotConnectedToInternet）
    case noConnection
    /// 服务器返回的业务错误
    case serverMessage(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的请求地址"
        case .invalidResponse:
            return "服务器响应异常"
        case .badStatus(let code):
            return "请求失败（状态码：\(code)）"
        case .decodingFailed(let error):
            return "数据解析失败：\(error.localizedDescription)"
        case .networkTimeout:
            return "请求超时，请检查网络后重试"
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .noConnection:
            return "网络连接不可用，请检查网络设置"
        case .serverMessage(let message):
            return message
        }
    }

    /// 从 URLError 映射为 NetworkError
    static func from(_ error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return .networkTimeout
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDataNotAllowed:
                return .noConnection
            default:
                return .serverMessage(error.localizedDescription)
            }
        }
        if error is DecodingError {
            return .decodingFailed(error)
        }
        return .serverMessage(error.localizedDescription)
    }
}
