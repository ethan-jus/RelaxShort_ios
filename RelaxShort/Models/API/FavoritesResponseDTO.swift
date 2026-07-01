import Foundation

// MARK: - Backend Date Parser

/// 兼容后端带/不带时区、有/无小数秒的 ISO 时间格式。
/// 解析失败返回 nil，不抛异常，以避免单个字段导致整页解码失败。
enum BackendDateParser {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoWithoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    /// 按优先级尝试解析：ISO8601 带小数秒 → ISO8601 无小数秒 → UTC 本地格式（带/不带小数秒）。
    /// 使用本地 DateFormatter 实例避免并发修改共享 formatter 的 `dateFormat`。
    static func parse(_ raw: String) -> Date? {
        if let date = isoWithFractional.date(from: raw) { return date }
        if let date = isoWithoutFractional.date(from: raw) { return date }

        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.calendar = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(secondsFromGMT: 0)

        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let date = local.date(from: raw) { return date }

        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: raw)
    }
}

// MARK: - Watch History Response DTO

/// GET /api/v2/watch-history 响应
struct WatchHistoryResponseDTO: Decodable {
    let items: [HistoryItemDTO]?
    let nextCursor: String?
    let hasMore: Bool?
}

struct HistoryItemDTO: Decodable {
    let seriesId: Int64
    let episodeId: Int64
    let episodeNumber: Int?
    let resumeTime: Int?
    let progressPercent: Double?
    let completed: Bool?
    let lastWatchedAt: String?
    let card: FeedCardDTO?
}

// MARK: - Bookmarks Response DTO

/// GET /api/v2/users/me/bookmarks 响应
struct BookmarksResponseDTO: Decodable {
    let items: [FeedCardDTO]?
    let nextCursor: String?
    let hasMore: Bool?
}

// MARK: - Bookmark Status Response DTO

/// GET /api/v2/users/me/bookmark-status 响应
struct BookmarkStatusResponseDTO: Decodable {
    let bookmarkedSeriesIds: [Int64]?
}

// MARK: - Bookmark Write Response DTO

/// POST / DELETE /api/v2/series/{id}/bookmark 响应
struct BookmarkWriteResponseDTO: Decodable {
    let bookmarked: Bool?
    let seriesId: Int64?
}

// MARK: - Watch Progress Response DTO

/// POST /api/v2/watch-progress 响应
struct WatchProgressResponseDTO: Decodable {
    let saved: Bool?
    let progressSeconds: Int?
    let completed: Bool?
}

// MARK: - DTO → Domain Mapping

extension WatchHistoryResponseDTO {
    func toDomain() -> CursorPage<WatchHistoryItem> {
        let mapped = (items ?? []).map { dto -> WatchHistoryItem in
            let drama: DramaItem
            if let card = dto.card {
                drama = FeedCardDTOMapper.toDramaItem(from: card)
            } else {
                drama = DramaItem(
                    id: String(dto.seriesId),
                    title: "",
                    coverURL: "",
                    category: "",
                    tags: [],
                    viewCount: 0,
                    episodeCount: 0,
                    currentEpisode: 0,
                    synopsis: "",
                    isHot: false,
                    isTrending: false,
                    rating: 0
                )
            }

            let episodeID = String(dto.episodeId)
            let seriesID = String(dto.seriesId)
            let resumeTime = TimeInterval(dto.resumeTime ?? 0)
            let progress = min(max(dto.progressPercent ?? 0, 0), 1)
            let watchedAt = dto.lastWatchedAt.flatMap(BackendDateParser.parse) ?? .distantPast

            return WatchHistoryItem(
                id: "\(seriesID)-\(episodeID)",
                drama: drama,
                episodeID: episodeID,
                currentEpisode: dto.episodeNumber ?? 0,
                resumeTime: resumeTime,
                watchedAt: watchedAt,
                progress: progress
            )
        }
        return CursorPage(items: mapped, nextCursor: nextCursor, hasMore: hasMore ?? false)
    }
}

extension BookmarksResponseDTO {
    func toDomain() -> CursorPage<DramaItem> {
        let mapped = (items ?? []).map(FeedCardDTOMapper.toDramaItem)
        return CursorPage(items: mapped, nextCursor: nextCursor, hasMore: hasMore ?? false)
    }
}
