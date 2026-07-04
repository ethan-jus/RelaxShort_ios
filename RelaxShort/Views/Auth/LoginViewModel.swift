import Foundation

/// 保留为登录页测试注入边界；真实认证状态由 AuthStore 统一管理。
@MainActor
final class LoginViewModel: ObservableObject {
    func signInWithGoogle(using authStore: AuthStore) {
        authStore.signInWithGoogle()
    }
}
