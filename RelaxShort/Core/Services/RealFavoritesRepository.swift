import Foundation

// MARK: - RealFavoritesRepository

/// 真实 v2 收藏/历史仓库，只调用后端 /api/v2/** 接口。
/// 错误原样抛出，不回退 Mock。
///
/// `@unchecked Sendable`：仅持有共享不可变 `APIClient.shared` 引用；
/// `APIClient` 本身未标记 Sendable 但其共享实例跨 actor 使用是安全的。
struct RealFavoritesRepository: FavoritesRepositoryProtocol, @unchecked Sendable {

    private let client = APIClient.shared

    // MARK: - Watch History

    func fetchWatchHistory(cursor: String?, limit: Int) async throws
        -> CursorPage<WatchHistoryItem> {
        let endpoint = APIEndpoint.watchHistoryV2(cursor: cursor, limit: limit)
        let dto: WatchHistoryResponseDTO = try await client.requestData(endpoint)
        return dto.toDomain()
    }

    // MARK: - Bookmarks

    func fetchBookmarks(cursor: String?, limit: Int) async throws
        -> CursorPage<DramaItem> {
        let endpoint = APIEndpoint.bookmarksV2(cursor: cursor, limit: limit)
        let dto: BookmarksResponseDTO = try await client.requestData(endpoint)
        return dto.toDomain()
    }

    // MARK: - Bookmark Status

    func fetchBookmarkedSeriesIDs(_ seriesIDs: [String]) async throws -> Set<String> {
        let deduped = Array(Set(seriesIDs.filter { !$0.isEmpty }))
        guard !deduped.isEmpty else { return [] }
        let endpoint = APIEndpoint.bookmarkStatus(seriesIDs: deduped)
        let dto: BookmarkStatusResponseDTO = try await client.requestData(endpoint)
        let ids = dto.bookmarkedSeriesIds ?? []
        return Set(ids.map(String.init))
    }

    // MARK: - Set Bookmark

    func setBookmarked(_ bookmarked: Bool, seriesID: String) async throws -> Bool {
        let endpoint = APIEndpoint.setBookmark(seriesID: seriesID, bookmarked: bookmarked)
        let dto: BookmarkWriteResponseDTO = try await client.requestData(endpoint)
        return dto.bookmarked ?? bookmarked
    }

    // MARK: - Report Progress

    func reportProgress(_ report: WatchProgressReport) async throws {
        let endpoint = APIEndpoint.watchProgress(report)
        let _: WatchProgressResponseDTO = try await client.requestData(endpoint)
    }
}
