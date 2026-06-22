import Foundation

// MARK: - Real Profile Repository

/// 真实后端 ProfileRepositoryProtocol 实现（Task23）。
///
/// 通过 `/api/v2/users/me` 获取用户信息，通过 `/api/v2/users/me/wallet` 获取钱包/VIP 状态，
/// 合并映射为 `User` UI 模型。
///
/// 仅在 `use_real_api=true` 时由 `DependencyContainer` 注入。
@MainActor
final class RealProfileRepository: ProfileRepositoryProtocol {

    private let client = APIClient.shared

    func fetchUserProfile() async throws -> User {
        async let profileDTO: UserProfileResponseDTO = client.requestData(.userMe)
        async let walletDTO: WalletResponseDTO = client.requestData(.userWallet)

        let (profile, wallet) = try await (profileDTO, walletDTO)

        return User(
            id: String(profile.userId),
            nickname: profile.nickname ?? "Guest",
            avatarURL: nil,
            isVip: wallet.vip?.active ?? false,
            vipExpireDate: wallet.vip?.expiresAt.flatMap(parseISO8601),
            coinBalance: wallet.balance.map { ($0 as NSDecimalNumber).intValue } ?? 0,
            followedCount: 0,
            qualityLevel: nil,
            totalDramas: nil,
            benefitCoins: nil
        )
    }

    // MARK: - Helpers

    /// 解析 ISO 8601 日期字符串（如 `"2026-06-01T00:00:00Z"`）
    private func parseISO8601(_ raw: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: raw) { return date }
        // 降级：无毫秒
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: raw)
    }
}
