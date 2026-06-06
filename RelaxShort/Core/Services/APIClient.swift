import Foundation
import OSLog

// MARK: - APIClient

/// RelaxShort 统一网络客户端。
///
/// 基于 `URLSession` + Swift `async/await`，提供泛型 JSON 解码能力。
/// 所有请求经过统一错误映射，失败时抛出 `NetworkError`。
///
/// ## 使用示例
/// ```swift
/// let dramas: [DramaItem] = try await APIClient.shared.request(.homeFeed(category: .all))
/// ```
final class APIClient {

    // MARK: - Singleton

    /// 共享单例
    static let shared = APIClient()

    // MARK: - Dependencies

    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = os.Logger(subsystem: "com.relaxshort.ios", category: "APIClient")

    // MARK: - Init

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Public API

    /// 发起请求，解码为指定 `Decodable` 类型。
    ///
    /// - Parameter endpoint: 预定义的 API 端点
    /// - Returns: 解码后的模型对象
    /// - Throws: `NetworkError` 封装的请求/解码错误
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let urlRequest = try buildRequest(for: endpoint)
        logRequest(urlRequest)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NetworkError.from(error)
        }

        try validateResponse(response, data: data)
        logResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("解码失败: \(error.localizedDescription)")
            throw NetworkError.decodingFailed(error)
        }
    }

    /// 发起请求，解码为 `Decodable` 数组。
    ///
    /// - Parameter endpoint: 预定义的 API 端点
    /// - Returns: 解码后的模型数组
    /// - Throws: `NetworkError`
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> [T] {
        let urlRequest = try buildRequest(for: endpoint)
        logRequest(urlRequest)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NetworkError.from(error)
        }

        try validateResponse(response, data: data)
        logResponse(response, data: data)

        do {
            return try decoder.decode([T].self, from: data)
        } catch {
            logger.error("解码失败: \(error.localizedDescription)")
            throw NetworkError.decodingFailed(error)
        }
    }

    // MARK: - Request Building

    /// 将 `APIEndpoint` 构造为 `URLRequest`
    private func buildRequest(for endpoint: APIEndpoint) throws -> URLRequest {
        guard let url = endpoint.url else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.allHTTPHeaderFields = endpoint.headers
        request.httpBody = endpoint.body
        return request
    }

    // MARK: - Response Validation

    /// 校验 HTTP 响应状态码
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw NetworkError.unauthorized
        case 500...:
            // 尝试解析服务端错误消息
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw NetworkError.serverMessage(message)
            }
            throw NetworkError.badStatus(httpResponse.statusCode)
        default:
            throw NetworkError.badStatus(httpResponse.statusCode)
        }
    }

    // MARK: - Logging

    private func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        logger.info("⬆️ \(method) \(url)")
        if let body = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) {
            logger.debug("    Body: \(String(describing: json))")
        }
    }

    private func logResponse(_ response: URLResponse, data: Data) {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        let url = httpResponse.url?.absoluteString ?? "?"
        logger.info("⬇️ [\(httpResponse.statusCode)] \(url) (\(data.count) bytes)")
    }
}
