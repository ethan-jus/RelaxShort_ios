import Foundation

// MARK: - Profile DTO Mapper

/// 将后端 Profile 和 Wallet DTO 合并映射为 `User` UI 模型。
/// 纯函数，不依赖网络或状态。
enum ProfileDTOMapper {
    static func toUser(
        profile: UserProfileResponseDTO,
        wallet: WalletResponseDTO
    ) -> User {
        User(
            id: String(profile.userId),
            nickname: profile.nickname ?? "",
            avatarURL: profile.avatarUrl,
            isVip: wallet.vip?.active ?? false,
            vipExpireDate: wallet.vip?.expiresAt.flatMap(parseISO8601),
            coinBalance: wallet.balance.map {
                ($0 as NSDecimalNumber).intValue
            } ?? 0,
            followedCount: profile.followingCount ?? 0,
            qualityLevel: profile.preferences?.defaultQuality,
            totalDramas: nil,
            benefitCoins: nil
        )
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

// MARK: - Real Profile Repository

/// 真实后端 ProfileRepositoryProtocol 实现。
///
/// 并发请求 `/api/v2/users/me` 和 `/api/v2/users/me/wallet`，
/// 通过 `ProfileDTOMapper` 合并映射为 `User` UI 模型。
/// 不使用 Mock fallback，不返回虚构数值。
@MainActor
final class RealProfileRepository: ProfileRepositoryProtocol {

    private let client = APIClient.shared

    func fetchUserProfile() async throws -> User {
        async let profileDTO: UserProfileResponseDTO = client.requestData(.userMe)
        async let walletDTO: WalletResponseDTO = client.requestData(.userWallet)

        let (profile, wallet) = try await (profileDTO, walletDTO)

        return ProfileDTOMapper.toUser(profile: profile, wallet: wallet)
    }
}
