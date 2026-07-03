import SwiftUI

// MARK: - Profile Sheet Type

/// Profile 菜单导航目标
enum ProfileSheet: Identifiable, Hashable {
    case recharge
    case wallet
    case welfare
    case watchHistory
    case downloads
    case language
    case theme
    case customerService
    case settings
    case topUp

    var id: String {
        switch self {
        case .recharge: return "recharge"
        case .wallet: return "wallet"
        case .welfare: return "welfare"
        case .watchHistory: return "watchHistory"
        case .downloads: return "downloads"
        case .language: return "language"
        case .theme: return "theme"
        case .customerService: return "customerService"
        case .settings: return "settings"
        case .topUp: return "topUp"
        }
    }

    var title: String {
        switch self {
        case .recharge: return L10n.rechargeNow
        case .wallet: return L10n.myWallet
        case .welfare: return L10n.welfareCenter
        case .watchHistory: return L10n.watchHistory
        case .downloads: return L10n.download
        case .language: return L10n.language
        case .theme: return L10n.themeMenuTitle
        case .customerService: return L10n.customerService
        case .settings: return "profile.settings".localized
        case .topUp: return "profile.top_up".localized
        }
    }
}

// MARK: - Profile View

/// 个人中心主页面 — Task33 电影感重设计。
/// 使用纯黑背景、深色卡片、Logo 红作为唯一高饱和强调色。
struct ProfileView: View {

    @StateObject private var viewModel: ProfileViewModel
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var dependencies: DependencyContainer

    @State private var selectedDestination: ProfileSheet?
    @State private var showLoginSheet = false
    @State private var showLogoutAlert = false

    init(viewModel: ProfileViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var pageInset: CGFloat {
        min(max(DT.Space.pageH, 16), 24)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部用户区
                if authStore.isLoggedIn {
                    switch viewModel.loadState {
                    case .loading:
                        ProfileHeaderSkeleton()
                    case .failed(let msg):
                        identityHeader
                        ProfileInlineError(message: msg) {
                            Task { await viewModel.loadProfile() }
                        }
                    default:
                        identityHeader
                    }
                } else {
                    guestHeader
                }

                // 会员卡
                membershipCard
                    .padding(.top, DT.Space.md)

                // 菜单第一组
                ProfileMenuCard {
                    if authStore.isLoggedIn, let user = viewModel.profile {
                        ProfileMenuRow(icon: "bitcoinsign.circle.fill", iconColor: DB.gold, title: "profile.top_up".localized, subtitle: "@\(user.coinBalance)", onTap: { selectedDestination = .topUp })
                    } else {
                        ProfileMenuRow(icon: "bitcoinsign.circle.fill", iconColor: DB.gold, title: "profile.top_up".localized, onTap: { presentLoginOrNavigate(.topUp) })
                    }
                    if authStore.isLoggedIn, let user = viewModel.profile {
                        ProfileMenuRow(icon: "wallet.pass.fill", iconColor: .white, title: L10n.myWallet, subtitle: "@\(user.coinBalance)", onTap: { selectedDestination = .wallet })
                    } else {
                        ProfileMenuRow(icon: "wallet.pass.fill", iconColor: .white, title: L10n.myWallet, onTap: { presentLoginOrNavigate(.wallet) })
                    }
                    ProfileMenuRow(icon: "gift.fill", iconColor: .orange, title: "profile.earn_rewards".localized, onTap: { selectedDestination = .welfare })
                    ProfileMenuRow(icon: "clock.fill", iconColor: .white, title: "profile.history".localized, onTap: { selectedDestination = .watchHistory })
                    ProfileMenuRow(icon: "arrow.down.to.line", iconColor: .white, title: "profile.membership_benefit_download".localized, onTap: { selectedDestination = .downloads })
                }
                .padding(.top, DT.Space.lg)

                // 菜单第二组
                ProfileMenuCard {
                    ProfileMenuRow(icon: "globe", iconColor: .white, title: L10n.language, onTap: { selectedDestination = .language })
                    ProfileMenuRow(icon: "questionmark.circle.fill", iconColor: .white, title: "profile.help_feedback".localized, onTap: { selectedDestination = .customerService })
                }
                .padding(.top, DT.Space.md)

                // 登出
                if authStore.isLoggedIn {
                    Button(role: .destructive, action: { showLogoutAlert = true }) {
                        Text(L10n.logout)
                            .font(.system(size: 15))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .padding(.horizontal, DT.Space.pageH)
                    .padding(.top, DT.Space.md)
                }
            }
            .padding(.bottom, DT.Layout.tabBarHeight + DT.Space.xl)
        }
        .background(DB.black)
        .navigationDestination(item: $selectedDestination) { destination in
            profileDestination(for: destination)
        }
        .navigationBarHidden(true)
        .task(id: authStore.isLoggedIn) {
            guard authStore.isLoggedIn else { return }
            await viewModel.loadProfile()
        }
        .onChange(of: viewModel.profile) { _, user in
            guard let user, authStore.isLoggedIn else { return }
            authStore.applyLoadedProfile(user)
        }
        .alert(L10n.confirmLogout, isPresented: $showLogoutAlert) {
            Button(L10n.logout, role: .destructive) { authStore.logout() }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.logoutConfirmMessage)
        }
    }

    // MARK: - Identity Header (Logged In)

    private var identityHeader: some View {
        ProfileIdentityHeader(
            avatarURL: viewModel.profile?.avatarURL,
            title: viewModel.displayName.isEmpty ? "Guest" : viewModel.displayName,
            subtitle: viewModel.shortId.isEmpty ? "profile.sign_in_subtitle".localized : viewModel.shortId,
            followingText: viewModel.profile.map { L10n.followedCount($0.followedCount) },
            isVIP: viewModel.profile?.isVipValid ?? false,
            onTap: {},
            onSettings: { selectedDestination = .settings }
        )
    }

    // MARK: - Guest Header

    private var guestHeader: some View {
        ProfileIdentityHeader(
            avatarURL: nil,
            title: "profile.sign_in".localized,
            subtitle: "profile.sign_in_subtitle".localized,
            followingText: nil,
            isVIP: false,
            onTap: { showLoginSheet = true },
            onSettings: { selectedDestination = .settings }
        )
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
    }

    // MARK: - Membership Card

    private var membershipCard: some View {
        ProfileMembershipCard(
            isVIP: viewModel.profile?.isVipValid ?? false,
            vipExpireDate: viewModel.profile?.vipExpireDate,
            onJoin: {
                NotificationCenter.default.post(name: .showMembership, object: nil)
            }
        )
    }

    // MARK: - Helpers

    private func presentLoginOrNavigate(_ destination: ProfileSheet) {
        if authStore.isLoggedIn {
            selectedDestination = destination
        } else {
            showLoginSheet = true
        }
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func profileDestination(for sheet: ProfileSheet) -> some View {
        switch sheet {
        case .recharge:
            PlaceholderView(title: sheet.title)
        case .wallet:
            PlaceholderView(title: sheet.title)
        case .welfare:
            CoinRewardView(mode: .pushed)
        case .watchHistory:
            PlaceholderView(title: sheet.title)
        case .downloads:
            PlaceholderView(title: sheet.title)
        case .language:
            LanguagePickerView()
        case .theme:
            ThemePickerView()
        case .customerService:
            PlaceholderView(title: sheet.title)
        case .settings:
            SettingsView()
        case .topUp:
            TopUpView()
                .environmentObject(StoreKitManager())
        }
    }
}

// MARK: - Language Picker

private struct LanguagePickerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(AppLanguage.allCases, id: \.self) { lang in
                Button(action: {
                    ThemeManager.shared.language = lang
                    dismiss()
                }) {
                    HStack {
                        Text(lang.displayName)
                            .foregroundColor(.white)
                        Spacer()
                        if ThemeManager.shared.language == lang {
                            Image(systemName: "checkmark")
                                .foregroundColor(DT.logoRed)
                        }
                    }
                }
                .listRowBackground(DB.panel)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DB.black)
        .navigationTitle(L10n.language)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Theme Picker

private struct ThemePickerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(ThemeMode.allCases, id: \.self) { mode in
                Button(action: {
                    ThemeManager.shared.themeMode = mode
                    dismiss()
                }) {
                    HStack {
                        Text(mode.displayName)
                            .foregroundColor(.white)
                        Spacer()
                        if ThemeManager.shared.themeMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundColor(DT.logoRed)
                        }
                    }
                }
                .listRowBackground(DB.panel)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DB.black)
        .navigationTitle(L10n.themeMenuTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let authStore = AuthStore()
        authStore.isLoggedIn = true
        authStore.currentUser = User(
            id: "preview",
            nickname: "测试用户",
            isVip: true,
            vipExpireDate: Date().addingTimeInterval(86400 * 30),
            coinBalance: 100,
            followedCount: 3
        )
        authStore.isVip = true
        authStore.vipExpireDate = Date().addingTimeInterval(86400 * 30)
        authStore.coinBalance = 100
        authStore.loginMethod = .google
        return ProfileView(viewModel: ProfileViewModel(repository: RealProfileRepository()))
            .environmentObject(authStore)
            .environmentObject(AppStore())
            .preferredColorScheme(.dark)
    }
}
#endif
