import SwiftUI

// MARK: - Login View

/// DramaBox 风格全屏深色登录页。
///
/// 布局：
/// - 顶部：品牌 Logo + 标题 + 副标题
/// - 中部：Google / Apple / Facebook 三个胶囊登录按钮
/// - 底部：游客登录文字按钮 + 隐私政策声明
///
/// 按钮规格：圆角胶囊，高 48pt，间距 12pt
struct LoginView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        ZStack {
            // MARK: Background
            DT.Color.bgPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Top — Brand
                brandSection
                    .padding(.top, 100)

                Spacer()

                // MARK: Center — Login Buttons
                VStack(spacing: DT.Space.md) {
                    googleSignInButton
                    appleSignInButton
                    facebookSignInButton
                }
                .padding(.horizontal, DT.Space.xxl)

                Spacer()

                // MARK: Bottom — Guest + Terms
                VStack(spacing: DT.Space.lg) {
                    guestLoginButton

                    privacyPolicyText
                }
                .padding(.bottom, 48)
            }
        }
        .onChange(of: authStore.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn { dismiss() }
        }
        .alert(L10n.generalError, isPresented: Binding(
            get: { authStore.authError != nil },
            set: { if !$0 { authStore.authError = nil } }
        )) {
            Button(L10n.generalOk, role: .cancel) {
                authStore.authError = nil
            }
        } message: {
            Text(authStore.authError ?? "")
        }
    }

    // MARK: - Brand Section

    private var brandSection: some View {
        VStack(spacing: DT.Space.sm) {
            // App icon placeholder — 可替换为真实 logo
            ZStack {
                RoundedRectangle(cornerRadius: DT.Radius.lg)
                    .fill(DT.brandPink)
                    .frame(width: 72, height: 72)

                Text("RS")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
            }

            Text(L10n.loginTitle)
                .font(DT.Font.largeTitle)
                .foregroundColor(DT.Color.textPrimary)

            Text(L10n.loginTagline)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textSecondary)
        }
    }

    // MARK: - Google Sign In Button

    private var googleSignInButton: some View {
        Button {
            authStore.signInWithGoogle()
        } label: {
            HStack(spacing: DT.Space.sm) {
                if authStore.isSigningIn {
                    ProgressView()
                        .tint(DT.Color.textPrimary)
                } else {
                    Image(systemName: "g.circle.fill")
                        .renderingMode(.original)
                        .font(DT.Font.body(22))
                    Text(L10n.loginGoogleButton)
                        .font(DT.Font.button)
                        .foregroundColor(DT.Color.bgPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: DT.Layout.ctaButtonHeight)
            .background(DT.Color.textPrimary)
            .clipShape(Capsule())
        }
        .disabled(authStore.isSigningIn)
    }

    // MARK: - Apple Sign In Button

    private var appleSignInButton: some View {
        Button {
            authStore.signInWithApple()
        } label: {
            HStack(spacing: DT.Space.sm) {
                if authStore.isSigningIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "apple.logo")
                        .font(DT.Font.body(22))
                    Text(L10n.loginAppleButton)
                        .font(DT.Font.button)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: DT.Layout.ctaButtonHeight)
            .background(Color.black)
            .clipShape(Capsule())
        }
        .disabled(authStore.isSigningIn)
    }

    // MARK: - Facebook Sign In Button

    private var facebookSignInButton: some View {
        Button {
            authStore.signInWithFacebook()
        } label: {
            HStack(spacing: DT.Space.sm) {
                if authStore.isSigningIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("f")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(width: 28, height: 28)
                        .background(Color.white)
                        .foregroundColor(Color(hex: "#1877F2"))
                        .clipShape(Circle())

                    Text(L10n.loginFacebookButton)
                        .font(DT.Font.button)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: DT.Layout.ctaButtonHeight)
            .background(Color(hex: "#1877F2"))
            .clipShape(Capsule())
        }
        .disabled(authStore.isSigningIn)
    }

    // MARK: - Guest Login Button

    private var guestLoginButton: some View {
        Button {
            authStore.signInAsGuest()
        } label: {
            HStack(spacing: DT.Space.xs) {
                if authStore.isSigningIn {
                    ProgressView()
                        .tint(DT.Color.textSecondary)
                } else {
                    Text(L10n.loginGuestButton)
                        .font(DT.Font.bodyDefault)
                        .foregroundColor(DT.Color.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(DT.Font.caption)
                        .foregroundColor(DT.Color.textTertiary)
                }
            }
        }
        .disabled(authStore.isSigningIn)
    }

    // MARK: - Privacy Policy

    private var privacyPolicyText: some View {
        (Text(L10n.loginAgreementPrefix)
            .font(DT.Font.small)
            .foregroundColor(DT.Color.textSecondary)
        + Text(L10n.loginTermsOfService)
            .font(DT.Font.small)
            .foregroundColor(DT.brandPink)
            .underline()
        + Text(L10n.loginAnd)
            .font(DT.Font.small)
            .foregroundColor(DT.Color.textSecondary)
        + Text(L10n.loginPrivacyPolicy)
            .font(DT.Font.small)
            .foregroundColor(DT.brandPink)
            .underline()
        + Text(L10n.loginPeriod)
            .font(DT.Font.small)
            .foregroundColor(DT.Color.textSecondary)
        )
        .multilineTextAlignment(.center)
        .lineSpacing(2)
        .padding(.horizontal, DT.Space.xxl)
    }
}

// MARK: - Preview

#if DEBUG
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthStore())
            .preferredColorScheme(.dark)
    }
}
#endif
