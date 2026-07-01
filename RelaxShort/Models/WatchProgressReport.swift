import Foundation

// MARK: - Cursor Page

/// 通用游标分页结果。
struct CursorPage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?
    let hasMore: Bool
}

// MARK: - Watch Progress Report

/// 客户端上报的观看进度快照，直接映射到 POST /api/v2/watch-progress。
/// 编码时使用 JSONEncoder.keyEncodingStrategy = .convertToSnakeCase。
struct WatchProgressReport: Sendable, Equatable, Codable {
    let seriesID: String
    let episodeID: String
    let progressSeconds: Int
    let totalDuration: Int
    let completed: Bool
    let playSessionID: UUID
    let finalReport: Bool
    let sourceType: String?
    let quality: String?
    let contentLanguage: String?
    let subtitleLanguage: String?
}
