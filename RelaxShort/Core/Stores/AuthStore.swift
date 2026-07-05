import Combine
import Foundation

/// SwiftUI 认证门面。匿名账户拥有真实资产，但只有 REGISTERED 才展示为“已登录”。
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var state: AuthState
    @Published var currentUser: User?
    @Published var isVip = false
    @Published var vipExpireDate: Date?
    @Published var coinBalance = 0

    private let coordinator: AuthSessionCoordinator
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: AuthSessionCoordinator? = nil) {
        let coordinator = coordinator ?? .shared
        self.coordinator = coordinator
        self.state = coordinator.state

        coordinator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.state = state
                if state.account?.isRegistered != true {
                    self?.currentUser = nil
                }
            }
            .store(in: &cancellables)
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var hasSession: Bool { coordinator.hasSession }
    var isLoggedIn: Bool { coordinator.isRegistered }
    var account: AuthAccount? { coordinator.account }
    var isSigningIn: Bool { coordinator.isSigningIn }

    var authError: String? {
        get { coordinator.errorMessage }
        set {
            if newValue == nil { coordinator.clearError() }
        }
    }

    func bootstrap() async {
        await coordinator.bootstrap()
    }

    func signInWithGoogle() {
        Task { await coordinator.signInWithGoogle() }
    }

    func signInWithFacebook() {
        Task { await coordinator.signInWithFacebook() }
    }

    func logout() {
        Task {
            await coordinator.logout()
            currentUser = nil
            isVip = false
            vipExpireDate = nil
            coinBalance = 0
        }
    }

    func applyLoadedProfile(_ user: User) {
        currentUser = user
        isVip = user.isVipValid
        vipExpireDate = user.vipExpireDate
        coinBalance = user.coinBalance
    }
}
