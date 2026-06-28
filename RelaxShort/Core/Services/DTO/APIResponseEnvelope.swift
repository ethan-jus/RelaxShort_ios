import Foundation

// MARK: - APIResponseEnvelope

/// 后端统一响应信封 `{"data": ..., "error": {...}, "request_id": "..."}`。
/// APIClient 在 requestData() 中自动解包，Repository 不直接接触 Envelope。
struct APIResponseEnvelope<T: Decodable>: Decodable {
    let data: T?
    let error: APIErrorDetail?
    let requestId: String?
    let pagination: PaginationInfo?
}

/// 后端分页信息（当前多数 App API 不填此字段，分页信息在 data 内部）。
struct PaginationInfo: Decodable {
    let nextCursor: String?
    let hasMore: Bool?
}

/// 后端错误详情 `{"code": "...", "message": "..."}`。
struct APIErrorDetail: Decodable {
    let code: String?
    let message: String?
}

// MARK: - API Error Wrapper

/// 包装后端错误，保留 code 供业务判断
struct APIError: LocalizedError {
    let code: String?
    let message: String
    let statusCode: Int?

    init(code: String?, message: String, statusCode: Int? = nil) {
        self.code = code
        self.message = message
        self.statusCode = statusCode
    }

    var errorDescription: String? { message }
}
