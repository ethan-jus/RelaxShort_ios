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

    /// 发起请求，解码为指定 `Decodable` 类型（不解包 envelope）。
    ///
    /// - Parameter endpoint: 预定义的 API 端点
    /// - Returns: 解码后的模型对象
    /// - Throws: `NetworkError` 封装的请求/解码错误
    func requestRaw<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
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

    /// 发起请求，自动解包后端 `ApiResponse<T>` envelope 的 `data` 字段。
    /// - 2xx 但 `error != nil` 时转为 `APIError`。
    /// - 返回 `data` 必须非 nil，否则抛 `NetworkError.invalidResponse`。
    func requestData<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let envelope: APIResponseEnvelope<T> = try await requestRaw(endpoint)
        if let apiError = envelope.error {
            throw APIError(code: apiError.code, message: apiError.message ?? "未知错误")
        }
        guard let data = envelope.data else {
            throw NetworkError.invalidResponse
        }
        return data
    }

    /// 发起请求，解码为 `Decodable` 数组（不解包 envelope）。
    func requestArray<T: Decodable>(_ endpoint: APIEndpoint) async throws -> [T] {
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
        if let error = Self.errorForHTTPResponse(statusCode: httpResponse.statusCode, data: data) {
            throw error
        }
    }

    /// 将非 2xx 响应优先映射为后端业务错误，避免丢失错误码和可操作信息。
    static func errorForHTTPResponse(statusCode: Int, data: Data) -> Error? {
        guard !(200..<300).contains(statusCode) else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
           let detail = envelope.error {
            return APIError(
                code: detail.code,
                message: detail.message ?? "请求失败",
                statusCode: statusCode
            )
        }

        switch statusCode {
        case 401:
            return NetworkError.unauthorized
        default:
            return NetworkError.badStatus(statusCode)
        }
    }

    private struct ErrorEnvelope: Decodable {
        let error: APIErrorDetail?
    }

    // MARK: - Logging

    private func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        logger.info("⬆️ \(method) \(url)")
        if url.contains("/events/discovery") { return }
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
