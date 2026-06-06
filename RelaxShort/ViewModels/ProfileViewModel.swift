import SwiftUI

// MARK: - Profile ViewModel

/// 个人中心 ViewModel，遵循 MVVM 架构
/// 通过 ProfileRepositoryProtocol 协议注入数据源，解耦视图与数据层
@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    @Published var profile: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let repository: ProfileRepositoryProtocol

    // MARK: - Init

    init(repository: ProfileRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Public Methods

    func loadProfile() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                profile = try await repository.fetchUserProfile()
            } catch {
                errorMessage = error.localizedDescription
                logError("ProfileViewModel.loadProfile failed: \(error)")
            }
            isLoading = false
        }
    }

    // MARK: - Computed Display Properties

    var displayName: String {
        guard let profile = profile else { return "" }
        return String(profile.nickname.prefix(2)).uppercased()
    }

    var shortId: String {
        guard let profile = profile else { return "" }
        return "ID \(profile.id)"
    }

    var dramaStats: String {
        return "16K+"
    }

    var walletDisplay: String {
        guard let profile = profile else { return "@0" }
        return "@\(profile.coinBalance)"
    }

    var benefitCoinsDisplay: String {
        return "+160"
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
