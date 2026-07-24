import SwiftUI

// MARK: - Profile Sheet Type

/// Profile 菜单导航目标
enum ProfileSheet: Identifiable, Hashable {
    case recharge
    case wallet
    case welfare
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
    @EnvironmentObject private var dependencies: DependencyContainer
    @EnvironmentObject private var rewardSummaryStore: RewardSummaryStore

    @State private var selectedDestination: ProfileSheet?
    @State private var showLoginSheet = false

    init(viewModel: ProfileViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                DB.black
                    .ignoresSafeArea()

                Image("ProfileRedLight")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: 228)
                    .offset(x: -4, y: 10)
                    .opacity(0.88)
                    .blendMode(.screen)
                    .clipped()
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 顶部用户区
                        if authStore.isLoggedIn {
                            loggedInHeader
                        } else {
                            guestHeader
                        }

                        // 会员主视觉
                        membershipCard

                        // 核心入口
                        ProfileMenuCard {
                            ProfileMenuRow(icon: "dollarsign.circle", iconColor: DT.logoRed, title: "profile.top_up".localized, onTap: { selectedDestination = .topUp })
                            ProfileMenuRow(icon: "creditcard", iconColor: .white, title: L10n.myWallet, subtitle: "\(rewardSummaryStore.coinBalance)", usesRewardCoinIcon: true, onTap: { selectedDestination = .wallet })
                            ProfileMenuRow(icon: "gift.fill", iconColor: DT.logoRed, title: "profile.earn_rewards".localized, promoRewardValue: rewardSummaryStore.remainingEarnableCoins, onTap: { selectedDestination = .welfare })
                            ProfileMenuRow(
                                icon: "clock",
                                iconColor: .white,
                                title: "profile.history".localized,
                                onTap: openWatchHistory
                            )
                            ProfileMenuRow(icon: "arrow.down.to.line", iconColor: .white, title: "profile.membership_benefit_download".localized, onTap: { selectedDestination = .downloads })
                        }
                        .padding(.top, DT.Space.sm)

                        // 辅助入口
                        ProfileMenuCard {
                            ProfileMenuRow(icon: "globe", iconColor: .white, title: L10n.language, onTap: { selectedDestination = .language })
                            ProfileMenuRow(icon: "questionmark.circle", iconColor: .white, title: "profile.help_feedback".localized, showsDivider: false, onTap: { selectedDestination = .customerService })
                        }
                        .padding(.top, 2)
                    }
                    .padding(.bottom, DT.Layout.tabBarHeight + DT.Space.xl + 30)
                }
                .frame(width: proxy.size.width)
            }
        }
        .navigationDestination(item: $selectedDestination) { destination in
            profileDestination(for: destination)
        }
        .navigationBarHidden(true)
        .task(id: authStore.account?.publicID) {
            guard authStore.hasSession else { return }
            async let profile: Void = viewModel.loadProfile()
            async let rewards: Void = rewardSummaryStore.refresh()
            _ = await (profile, rewards)
        }
        .onChange(of: viewModel.profile) { _, user in
            guard let user else { return }
            authStore.applyLoadedProfile(user)
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
    }

    // MARK: - Logged In Header

    @ViewBuilder
    private var loggedInHeader: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProfileHeaderSkeleton()
        case .loaded:
            if viewModel.profile != nil {
                identityHeader
            } else {
                ProfileHeaderSkeleton()
            }
        case .failed(let message):
            if viewModel.profile != nil {
                identityHeader
            } else {
                ProfileHeaderSkeleton()
            }
            ProfileInlineError(message: message) {
                Task { await viewModel.loadProfile() }
            }
        }
    }

    // MARK: - Identity Header (Logged In)

    private var identityHeader: some View {
        ProfileIdentityHeader(
            avatarURL: viewModel.profile?.avatarURL,
            title: viewModel.displayName,
            displayID: viewModel.profile?.id ?? "",
            favoriteCount: viewModel.profile?.favoriteCount ?? 0,
            isGuest: false,
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
            displayID: authStore.account?.publicID
                ?? ProfileGuestIdentity.shortID(from: InstallIdentityProvider.shared.installID()),
            favoriteCount: viewModel.profile?.favoriteCount ?? 0,
            isGuest: true,
            isVIP: false,
            onTap: { showLoginSheet = true },
            onSettings: { selectedDestination = .settings }
        )
    }

    // MARK: - Membership Card

    private var membershipCard: some View {
        let profile = viewModel.profile
        return ProfileMembershipCard(
            isVIP: profile?.isVipValid ?? false,
            vipExpireDate: profile?.vipExpireDate,
            onJoin: {
                NotificationCenter.default.post(name: .showMembership, object: nil)
            }
        )
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func profileDestination(for sheet: ProfileSheet) -> some View {
        switch sheet {
        case .recharge:
            PlaceholderView(title: sheet.title)
        case .wallet:
            WalletView()
        case .welfare:
            CoinRewardView(mode: .pushed)
        case .downloads:
            OfflineDownloadsView()
        case .language:
            LanguagePickerView()
        case .theme:
            ThemePickerView()
        case .customerService:
            SupportCenterView(repository: dependencies.supportRepository)
        case .settings:
            SettingsView()
        case .topUp:
            TopUpView()
        }
    }

    private func openWatchHistory() {
        appStore.requestedMyListSegment = .history
        appStore.selectedTab = .myList
    }
}

// MARK: - Language Picker

private struct LanguagePickerView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    appStore.followDeviceLanguage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("language.follow_device".localized)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            Text(AppLanguage.preferred().nativeDisplayName)
                                .font(.system(size: 12))
                                .foregroundColor(DB.mutedText)
                        }

                        Spacer()
                        selectionMark(appStore.followsDeviceLanguage)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 62)
                    .background(DB.panel.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(DB.divider, lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Text("language.choose".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DB.mutedText)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Button {
                            appStore.selectLanguage(language)
                        } label: {
                            HStack {
                                Text(language.nativeDisplayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                selectionMark(
                                    !appStore.followsDeviceLanguage
                                        && appStore.language == language
                                )
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                        }
                        .buttonStyle(.plain)

                        if language != AppLanguage.allCases.last {
                            Divider()
                                .overlay(DB.divider)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(DB.panel.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(DB.divider, lineWidth: 0.8)
                }
                .padding(.horizontal, 20)

                Label(
                    "language.saved_note".localized,
                    systemImage: "lock"
                )
                .font(.system(size: 12))
                .foregroundColor(DT.brandGold)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            }
        }
        .background(DB.black.ignoresSafeArea())
        .compactSecondaryNavigation(title: L10n.language)
    }

    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(selected ? DT.logoRed : DB.mutedText)
    }
}

// MARK: - Theme Picker

private struct ThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        List {
            ForEach(ThemeMode.allCases, id: \.self) { mode in
                Button(action: {
                    appStore.themeMode = mode
                    dismiss()
                }) {
                    HStack {
                        Text(mode.displayName)
                            .foregroundColor(.white)
                        Spacer()
                        if appStore.themeMode == mode {
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
        .compactSecondaryNavigation(title: L10n.themeMenuTitle)
    }
}

// MARK: - Preview

#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let authStore = AuthStore()
        authStore.currentUser = User(
            id: "preview",
            nickname: "测试用户",
            isVip: true,
            vipExpireDate: Date().addingTimeInterval(86400 * 30),
            coinBalance: 100,
            favoriteCount: 3
        )
        authStore.isVip = true
        authStore.vipExpireDate = Date().addingTimeInterval(86400 * 30)
        authStore.coinBalance = 100
        return ProfileView(
            viewModel: ProfileViewModel(
                repository: ProfilePreviewRepository(
                    user: authStore.currentUser!
                )
            )
        )
            .environmentObject(authStore)
            .environmentObject(AppStore())
            .preferredColorScheme(.dark)
    }
}

private struct ProfilePreviewRepository: ProfileRepositoryProtocol {
    let user: User

    func fetchUserProfile() async throws -> User {
        user
    }
}
#endif
