import SwiftUI

// MARK: - Login ViewModel

/// 登录页 ViewModel，轻量包装 AuthStore 登录操作。
/// 状态（isSigningIn / authError）由 AuthStore 通过 @Published 驱动，
/// LoginView 直接访问 authStore 属性，ViewModel 作为可选中介。
@MainActor
final class LoginViewModel: ObservableObject {

    // MARK: - 便捷方法：将 AuthStore Actions 封装为可注入 ViewModel

    func signInWithGoogle(using authStore: AuthStore) {
        authStore.signInWithGoogle()
    }

    func signInWithApple(using authStore: AuthStore) {
        authStore.signInWithApple()
    }

    func signInWithFacebook(using authStore: AuthStore) {
        authStore.signInWithFacebook()
    }

    func signInAsGuest(using authStore: AuthStore) {
        authStore.signInAsGuest()
    }
}
