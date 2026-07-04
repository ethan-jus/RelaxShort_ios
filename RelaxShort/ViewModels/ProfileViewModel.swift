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

    // MARK: - Computed Display Properties

    /// 昵称，未加载时返回空
    var displayName: String {
        profile?.nickname ?? ""
    }

}
