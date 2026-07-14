import Foundation

// MARK: - Real Detail Repository

/// 真实后端 DetailRepositoryProtocol 实现。
/// 通过 `/api/v2/series/{id}/episodes` 获取剧集列表，
/// 通过 `/api/v2/episodes/{id}/play` 获取播放地址。
@MainActor
final class RealDetailRepository: DetailRepositoryProtocol {

    private let client = APIClient.shared

    func fetchDramaDetail(id: String) async throws -> DramaItem {
        // 当前后端未实现真实 series detail 端点到 v2 APIEndpoint，
        // 暂时通过 episodes 端点取到 seriesId 再构造一个最小 DramaItem。
        // 后续 Task13+ 补 series detail 端点后可替换此处 stub。
        let episodes = try await fetchEpisodes(dramaId: id)
        let coverURL = firstCoverFromCache(id)
        return DramaItem(
            id: id,
            title: "",
            coverURL: coverURL,
            videoURL: nil,
            category: "",
            tags: [],
            viewCount: 0,
            episodeCount: episodes.count,
            currentEpisode: 0,
            synopsis: "",
            isHot: false, isTrending: false, rating: 0, coinReward: 0,
            badgeText: nil, imageHeight: 168, badge: nil,
            regionTag: nil, languageTag: nil,
            isFollowed: false, isBookmarked: false,
            isVIPOnly: false, isComingSoon: false,
            coinPrice: nil, freeEpisodeRange: nil, isMemberOnly: false
        )
    }

    func fetchEpisodes(dramaId: String) async throws -> [Episode] {
        let dto: SeriesEpisodesResponseDTO = try await client.requestData(
            .seriesEpisodes(seriesId: dramaId)
        )
        return (dto.episodes ?? []).map { item in
            Episode(
                id: String(item.episodeId),
                dramaId: String(dto.seriesId),
                episodeNumber: item.episodeNumber,
                title: item.localizedTitle ?? "EP \(item.episodeNumber)",
                videoURL: "",   // 播放页需单独调 episodePlay 填充
                duration: TimeInterval(item.durationSeconds ?? 0),
                isLocked: !(item.isFree ?? true) || (item.vipRequired ?? false),
                unlockCoinPrice: item.unlockCoinCost.flatMap { Int(truncating: $0 as NSNumber) },
                requiresVIP: item.vipRequired ?? false
            )
        }
    }

    func fetchRelatedDramas(dramaId: String) async throws -> [DramaItem] {
        // Gap: 后端暂缺 related dramas 接口，返回空
        return []
    }

    // MARK: - Play Asset

    /// 获取播放地址并映射到播放接口 DTO，同时更新 Episode.videoURL 为兼容 URL。
    func fetchPlayAsset(episodeId: String) async throws -> PlaybackMediaSourceDTO {
        let dto: EpisodePlayResponseDTO = try await client.requestData(
            .episodePlay(episodeId: episodeId)
        )
        return PlaybackMediaSourceDTO(from: dto)
    }

    func fetchUnlockAccount() async throws -> EpisodeUnlockAccount {
        let wallet: WalletResponseDTO = try await client.requestData(.userWallet)
        return EpisodeUnlockAccount(
            balance: wallet.balance.map { Int(truncating: $0 as NSNumber) } ?? 0,
            isVIP: wallet.vip?.active ?? false
        )
    }

    func unlockEpisode(episodeId: String, method: EpisodeUnlockMethod) async throws -> EpisodeUnlockResult {
        let response: EpisodeUnlockResponseDTO = try await client.requestData(
            .episodeUnlock(
                episodeId: episodeId,
                method: method,
                idempotencyKey: "ios-unlock-\(episodeId)-\(method.rawValue)-\(UUID().uuidString)"
            )
        )
        return EpisodeUnlockResult(
            unlocked: response.unlocked,
            balanceAfter: response.balanceAfter.map { Int(truncating: $0 as NSNumber) }
        )
    }

    func verifyCoinPurchase(_ receipt: ApplePurchaseReceipt) async throws -> Int {
        let response: ApplePaymentVerifyResponseDTO = try await client.requestData(
            .applePaymentVerify(
                receipt: receipt,
                idempotencyKey: "ios-apple-\(receipt.transactionID)"
            )
        )
        guard response.status == "completed", let balance = response.wallet?.balance else {
            throw APIError(code: "PAYMENT_DELIVERY_FAILED", message: "金币尚未到账，请稍后重试")
        }
        return Int(truncating: balance as NSNumber)
    }

    func verifyVIPPurchase(_ receipt: ApplePurchaseReceipt) async throws -> EpisodeUnlockAccount {
        let response: ApplePaymentVerifyResponseDTO = try await client.requestData(
            .applePaymentVerify(
                receipt: receipt,
                idempotencyKey: "ios-apple-\(receipt.transactionID)"
            )
        )
        guard response.status == "completed" else {
            throw APIError(code: "PAYMENT_DELIVERY_FAILED", message: "会员权益尚未生效，请稍后重试")
        }
        let account = try await fetchUnlockAccount()
        guard account.isVIP else {
            throw APIError(code: "VIP_NOT_ACTIVE", message: "会员权益尚未生效，请稍后重试")
        }
        return account
    }

    /// 获取播放地址并按兼容方式更新 episode.videoURL
    func fetchPlaybackURL(episodeId: String) async throws -> String? {
        let source = try await fetchPlayAsset(episodeId: episodeId)
        return source.preferredPlaybackURL
    }

    // MARK: - 临时封面缓存

    private func firstCoverFromCache(_ seriesId: String) -> String {
        // 简易缓存：从 For You 列表可能已加载的 cover URL
        return ""
    }
}
