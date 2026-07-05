import SwiftUI
import GoogleSignInSwift

/// 真实登录页。当前阶段只展示已接通的 Google 登录，不放置不可用入口。
struct LoginView: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#170B0C"), .black, .black],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                brand
                Spacer(minLength: 44)
                googleButton
                facebookButton
                    .padding(.top, 12)
                agreement
                    .padding(.top, 20)
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 24)
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

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(authStore.isSigningIn)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var brand: some View {
        VStack(spacing: 18) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: DT.logoRed.opacity(0.28), radius: 28, y: 12)

            VStack(spacing: 8) {
                Text(L10n.loginTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(L10n.loginTagline)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var googleButton: some View {
        ZStack {
            GoogleSignInButton(
                scheme: .light,
                style: .wide,
                state: authStore.isSigningIn ? .disabled : .normal
            ) {
                authStore.signInWithGoogle()
            }

            if authStore.isSigningIn {
                Color.white
                    .overlay {
                        ProgressView()
                            .tint(.black)
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: 312)
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }

    private var facebookButton: some View {
        ZStack {
            Button(action: { authStore.signInWithFacebook() }) {
                HStack(spacing: 10) {
                    Image("FacebookLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text("login.facebook_button".localized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color(hex: "#1877F2"))
                .cornerRadius(4)
            }
            .disabled(authStore.isSigningIn)

            if authStore.isSigningIn {
                Color(hex: "#1877F2")
                    .overlay { ProgressView().tint(.white) }
                    .frame(height: 40)
                    .cornerRadius(4)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: 312)
    }

    private var agreement: some View {
        Text(
            L10n.loginAgreementPrefix
            + L10n.loginTermsOfService
            + L10n.loginAnd
            + L10n.loginPrivacyPolicy
            + L10n.loginPeriod
        )
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .lineSpacing(3)
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
