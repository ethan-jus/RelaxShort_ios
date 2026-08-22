import SwiftUI

// MARK: - Profile ViewModel

/// 个人中心 ViewModel，遵循 MVVM 架构。
/// 通过 ProfileRepositoryProtocol 协议注入数据源，解耦视图与数据层。
/// 不使用 Mock fallback，不返回虚构数值。
@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Load State

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // MARK: - Published State

    @Published private(set) var profile: User?
    @Published private(set) var loadState: LoadState = .idle

    // MARK: - Dependencies

    private let repository: ProfileRepositoryProtocol

    // MARK: - Init

    init(repository: ProfileRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Public Methods

    func loadProfile() async {
        loadState = .loading
        do {
            profile = try await repository.fetchUserProfile()
            loadState = .loaded
        } catch {
            // 保留已加载的旧数据，不清空
            loadState = .failed(error.localizedDescription)
            #if DEBUG
            Logger.viewModel.error("ProfileViewModel.loadProfile failed: \(error)")
            #endif
        }
    }

    func updateNickname(_ nickname: String) async throws {
        let updated = try await repository.updateNickname(nickname)
        profile = updated
        loadState = .loaded
    }

    func uploadAvatar(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws {
        let updated = try await repository.uploadAvatar(
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )
        profile = updated
        loadState = .loaded
    }

    // MARK: - Computed Display Properties

    /// Apple 只会在首次授权时返回姓名；缺失时使用邮箱前缀或稳定用户编号兜底。
    var displayName: String {
        guard let profile else { return "" }
        let nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty { return nickname }

        if let email = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.lowercased().hasSuffix("@privaterelay.appleid.com"),
           let localPart = email.split(separator: "@").first,
           !localPart.isEmpty {
            return String(localPart)
        }
        return "profile.default_user_name".localizedFormat(String(profile.id.suffix(4)))
    }

}
