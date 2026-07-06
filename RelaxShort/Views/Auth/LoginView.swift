import SwiftUI

/// 真实登录页。仅展示已接通后端认证闭环的第三方登录入口。
struct LoginView: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            background

            GeometryReader { proxy in
                let compactHeight = proxy.size.height < 700
                let bottomLift: CGFloat = compactHeight ? 40 : 212

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        topBar
                        brand(compactHeight: compactHeight)

                        Spacer(minLength: compactHeight ? 24 : 52)

                        authArea
                    }
                    .frame(
                        minHeight: max(0, proxy.size.height - bottomLift),
                        alignment: .top
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, bottomLift)
                }
            }
        }
        .interactiveDismissDisabled(authStore.isSigningIn)
        .onChange(of: authStore.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn { dismiss() }
        }
        .alert(L10n.generalError, isPresented: Binding(
            get: { authStore.authError != nil },
            set: { if !$0 { authStore.authError = nil } }
        )) {
            Button(L10n.generalOk, role: .cancel) { authStore.authError = nil }
        } message: {
            Text(authStore.authError ?? "")
        }
    }

    private var background: some View {
        ZStack {
            Color.black

            LinearGradient(
                colors: [
                    Color(hex: "#210D0F"),
                    Color(hex: "#090505"),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    DT.logoRed.opacity(0.24),
                    DT.logoRed.opacity(0.07),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.18),
                startRadius: 10,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.055))
                    .clipShape(Circle())
                    .contentShape(Rectangle())
            }
            .disabled(authStore.isSigningIn)
            Spacer()
        }
        .padding(.top, 10)
    }

    private func brand(compactHeight: Bool) -> some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(
                    width: compactHeight ? 78 : 96,
                    height: compactHeight ? 78 : 96
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: compactHeight ? 18 : 22,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: compactHeight ? 18 : 22,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: DT.logoRed.opacity(0.32), radius: 30, y: 12)

            VStack(spacing: 7) {
                Text(L10n.loginTitle)
                    .font(.system(size: compactHeight ? 29 : 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-0.5)

                Text(L10n.loginTagline)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, compactHeight ? 26 : 66)
    }

    private var authArea: some View {
        VStack(spacing: 14) {
            authPanel
            agreement
        }
    }

    private enum ProviderIcon {
        case asset(String)
        case system(String)
    }

    private var authPanel: some View {
        VStack(spacing: 16) {
            providerButton(
                icon: .asset("GoogleLogo"),
                title: L10n.loginGoogleButton,
                background: .white,
                foreground: Color(hex: "#3C4043"),
                action: authStore.signInWithGoogle
            )

            providerButton(
                icon: .asset("FacebookLogo"),
                title: L10n.loginFacebookButton,
                background: Color(hex: "#1877F2"),
                foreground: .white,
                action: authStore.signInWithFacebook
            )

            providerButton(
                icon: .system("apple.logo"),
                title: L10n.loginAppleButton,
                background: .black,
                foreground: .white,
                action: authStore.signInWithApple
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }

            if authStore.isSigningIn {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "#181415").opacity(0.82))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.065), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.38), radius: 22, y: 10)
    }

    /// 第三方登录按钮统一图标基线与文字中心。
    private func providerButton(
        icon: ProviderIcon,
        title: String,
        background: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 54)

                HStack {
                    providerIconView(icon)
                        .frame(width: 20, height: 20)
                    Spacer()
                }
                .padding(.horizontal, 22)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(background)
            .clipShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .disabled(authStore.isSigningIn)
        .opacity(authStore.isSigningIn ? 0.58 : 1)
    }

    @ViewBuilder
    private func providerIconView(_ icon: ProviderIcon) -> some View {
        switch icon {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var agreement: some View {
        Text(
            L10n.loginAgreementPrefix
            + L10n.loginTermsOfService
            + L10n.loginAnd
            + L10n.loginPrivacyPolicy
            + L10n.loginPeriod
        )
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(Color.white.opacity(0.74))
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
    }
}

#if DEBUG
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthStore())
            .preferredColorScheme(.dark)
    }
}
#endif
