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
        case .settings: return "Settings"
        case .topUp: return "Top Up"
        }
    }
}

// MARK: - Profile View

/// 个人中心页 — 复刻 DramaBox，NavigationStack push 替代 sheet
struct ProfileView: View {

    @StateObject private var viewModel: ProfileViewModel
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var appStore: AppStore

    init(viewModel: ProfileViewModel? = nil) {
        let vm = viewModel ?? ProfileViewModel(repository: MockProfileRepository())
        _viewModel = StateObject(wrappedValue: vm)
    }

    @State private var showLogoutAlert = false
    @State private var showLoginSheet = false

    var body: some View {
        Group {
            if authStore.isLoggedIn {
                loggedInContent
            } else {
                guestProfileContent
            }
        }
        .navigationDestination(for: ProfileSheet.self) { sheet in
            profileDestination(for: sheet)
        }
        .navigationBarHidden(true)
        .ignoresSafeArea()
    }

    // MARK: - Logged In Content

    private var loggedInContent: some View {
        ScrollView {
            VStack(spacing: DT.Space.md) {
                // ① Header
                profileHeader
                    .padding(.bottom, DT.Space.xs)

                // VIP Banner
                membershipBanner
                    .padding(.bottom, DT.Space.sm)

                // ② Menu Group 1 — 充值
                menuCard {
                    menuLink(.recharge, icon: "yensign.circle.fill", iconColor: DT.brandPink, title: L10n.rechargeNow, hasDivider: true)
                    menuLink(.wallet, icon: "wallet.pass.fill", iconColor: DT.brandPink, title: L10n.myWallet, rightText: "@\(authStore.coinBalance)", hasDivider: true)
                    menuLink(.welfare, icon: "gift.fill", iconColor: DT.brandPink, title: L10n.welfareCenter, rightText: "+16")
                }

                // ③ Menu Group 2 — 功能
                menuCard {
                    menuLink(.watchHistory, icon: "clock.arrow.circlepath", iconColor: DT.Color.textPrimary, title: L10n.watchHistory, hasDivider: true)
                    menuLink(.downloads, icon: "arrow.down.circle.fill", iconColor: DT.Color.textPrimary, title: L10n.download)
                }

                // ④ Menu Group 3 — 设置
                menuCard {
                    menuLink(.language, icon: "globe", iconColor: DT.Color.textPrimary, title: L10n.language, rightText: appStore.language.displayName, hasDivider: true)
                    menuLink(.theme, icon: "paintpalette.fill", iconColor: DT.Color.textPrimary, title: L10n.themeMenuTitle, rightText: appStore.themeMode.displayName, hasDivider: true)
                    menuLink(.customerService, icon: "headphones", iconColor: DT.Color.textPrimary, title: L10n.customerService, hasDivider: true)
                    menuLink(.settings, icon: "gearshape.fill", iconColor: DT.Color.textPrimary, title: "Settings")
                }

                // ⑤ Logout
                Button {
                    showLogoutAlert = true
                } label: {
                    Text(L10n.logout)
                        .font(DT.Font.body(15, weight: .medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(DT.Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
                }
                .padding(.top, DT.Space.md)
                .padding(.bottom, DT.Space.xxl)
            }
            .padding(.horizontal, DT.Space.pageH)
        }
        .background(DT.Color.bgPrimary)
        .onAppear {
            viewModel.loadProfile()
        }
        .onChange(of: viewModel.profile) { _, newProfile in
            guard let user = newProfile, authStore.isLoggedIn else { return }
            authStore.applyLoadedProfile(user)
        }
        .alert(L10n.confirmLogout, isPresented: $showLogoutAlert) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.logout, role: .destructive) {
                authStore.logout()
            }
        } message: {
            Text(L10n.logoutConfirmMessage)
        }
    }

    // MARK: - Guest Profile Content

    /// 未登录状态的 Profile 页，与 My List 的 guest 状态保持一致
    private var guestProfileContent: some View {
        VStack(spacing: DT.Space.xl) {
            Spacer()

            // Avatar placeholder
            ZStack {
                Circle()
                    .fill(DT.brandPink.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.fill")
                    .font(DT.Font.body(44))
                    .foregroundColor(DT.brandPink)
            }

            Text(L10n.profileLoginToView)
                .font(DT.Font.body(17, weight: .semibold))
                .foregroundColor(DT.Color.textPrimary)

            Text(L10n.profileLoginToSync)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Space.xxl)

            Button {
                showLoginSheet = true
            } label: {
                Text(L10n.loginNow)
                    .font(DT.Font.body(15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 44)
                    .background(DT.brandPink)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DT.Color.bgPrimary)
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
        .onChange(of: authStore.isLoggedIn) { _, newValue in
            if newValue {
                showLoginSheet = false
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        HStack(spacing: DT.Space.md) {
            // Avatar
            avatarView

            // Nickname + VIP + Coin
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                HStack(spacing: 6) {
                    Text(viewModel.displayName)
                        .font(DT.Font.body(18, weight: .bold))
                        .foregroundColor(DT.Color.textPrimary)

                    if authStore.isVip {
                        vipBadge
                    }
                }

                if authStore.coinBalance > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(DT.Font.body(14))
                            .foregroundColor(DT.brandGold)

                        Text("\(authStore.coinBalance)")
                            .font(DT.Font.body(14, weight: .semibold))
                            .foregroundColor(DT.brandGold)
                    }
                }

                Text(viewModel.shortId)
                    .font(DT.Font.small)
                    .foregroundColor(DT.Color.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(DT.Font.body(14, weight: .semibold))
                .foregroundColor(DT.Color.textTertiary)
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.vertical, DT.Space.xxl)
        .padding(.top, DT.Space.xxl)
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DT.brandPink, DT.brandPink.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)

            Text(viewModel.avatarInitials)
                .font(DT.Font.body(22, weight: .bold))
                .foregroundColor(.white)
        }
        .overlay(
            Circle()
                .stroke(DT.Color.bgCard, lineWidth: 2)
        )
    }

    // MARK: - Membership Banner

    private var membershipBanner: some View {
        Button {
            NotificationCenter.default.post(name: .showMembership, object: nil)
        } label: {
            HStack(spacing: DT.Space.md) {
                ZStack {
                    Circle().fill(DB.gold.opacity(0.2)).frame(width: 44, height: 44)
                    Image(systemName: "crown.fill").font(.system(size: 20)).foregroundColor(DB.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(authStore.isVip ? "VIP Member" : "Join Membership")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Text(authStore.isVip ? "Enjoy premium benefits" : "Unlock all content with VIP")
                        .font(.system(size: 12)).foregroundColor(DB.mutedText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(DB.mutedText)
            }
            .padding(DT.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: DB.cardRadius)
                    .fill(DB.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: DB.cardRadius)
                            .stroke(DB.gold.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - VIP Badge

    private var vipBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "crown.fill")
                .font(DT.Font.body(9))
            Text("VIP")
                .font(DT.Font.body(9, weight: .bold))
        }
        .foregroundColor(DT.brandPink)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(DT.brandPink.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
    }

    // MARK: - Menu Card Builder

    @ViewBuilder
    private func menuCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(DT.Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }

    // MARK: - Menu Link (NavigationLink wrapper)

    @ViewBuilder
    private func menuLink(
        _ sheet: ProfileSheet,
        icon: String,
        iconColor: SwiftUI.Color,
        title: String,
        rightText: String? = nil,
        hasDivider: Bool = false
    ) -> some View {
        NavigationLink(value: sheet) {
            menuRowContent(icon: icon, iconColor: iconColor, title: title, rightText: rightText, hasDivider: hasDivider)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Menu Row Content

    @ViewBuilder
    private func menuRowContent(
        icon: String,
        iconColor: SwiftUI.Color,
        title: String,
        rightText: String? = nil,
        hasDivider: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DT.Space.md) {
                Image(systemName: icon)
                    .font(DT.Font.body(17))
                    .foregroundColor(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(DT.Font.body(15))
                    .foregroundColor(DT.Color.textPrimary)

                Spacer()

                if let rightText {
                    Text(rightText)
                        .font(DT.Font.caption)
                        .foregroundColor(DT.Color.textSecondary)
                        .padding(.trailing, DT.Space.xs)
                }

                Image(systemName: "chevron.right")
                    .font(DT.Font.body(11, weight: .semibold))
                    .foregroundColor(DT.Color.textTertiary)
            }
            .padding(.horizontal, DT.Space.lg)
            .frame(height: 52)

            if hasDivider {
                Divider()
                    .frame(height: 0.5)
                    .background(DT.Color.bgDivider)
                    .padding(.leading, 56)
            }
        }
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func profileDestination(for sheet: ProfileSheet) -> some View {
        switch sheet {
        case .language:
            languagePickerView
        case .theme:
            themePickerView
        case .settings:
            SettingsView()
        case .topUp:
            TopUpView()
        case .wallet:
            TopUpView()
        default:
            profilePlaceholderView(for: sheet)
        }
    }

    // MARK: - Language Picker (pushed, no inner NavigationStack)

    private var languagePickerView: some View {
        List {
            ForEach(AppLanguage.allCases, id: \.self) { lang in
                Button {
                    appStore.language = lang
                } label: {
                    HStack {
                        Text(lang.displayName)
                            .font(DT.Font.bodyDefault)
                            .foregroundColor(DT.Color.textPrimary)
                        Spacer()
                        if appStore.language == lang {
                            Image(systemName: "checkmark")
                                .foregroundColor(DT.brandPink)
                        }
                    }
                }
                .listRowBackground(DT.Color.bgCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DT.Color.bgPrimary)
        .navigationTitle(L10n.language)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Theme Picker (pushed, no inner NavigationStack)

    private var themePickerView: some View {
        List {
            ForEach(ThemeMode.allCases, id: \.self) { mode in
                Button {
                    appStore.themeMode = mode
                } label: {
                    HStack {
                        Text(mode.displayName)
                            .font(DT.Font.bodyDefault)
                            .foregroundColor(DT.Color.textPrimary)
                        Spacer()
                        if appStore.themeMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundColor(DT.brandPink)
                        }
                    }
                }
                .listRowBackground(DT.Color.bgCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DT.Color.bgPrimary)
        .navigationTitle(L10n.themeSheetTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Placeholder View (pushed, no inner NavigationStack)

    @ViewBuilder
    private func profilePlaceholderView(for sheet: ProfileSheet) -> some View {
        VStack(spacing: 0) {
            Text(sheet.title)
                .font(DT.Font.sectionTitle)
                .foregroundColor(DT.Color.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DT.Color.bgPrimary)
        .navigationTitle(sheet.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings View

/// DramaBox 风格设置页
private struct SettingsView: View {
    @State private var downloadWithMobileData = false
    @State private var personalizedAds = true
    @State private var personalizedRecs = true
    @State private var marketingComms = false
    @Environment(\.dismiss) private var dismiss
#if DEBUG
    @State private var showDebugPanel = false
#endif

    var body: some View {
        List {
            Section {
                settingRow(title: "Manage Membership", systemImage: "crown.fill", color: DB.gold)
                settingRow(title: "Appearance", systemImage: "paintpalette.fill", color: .blue)
                settingRowWithValue(title: "Clear Cache", systemImage: "trash", color: .gray, value: "128 MB")
                settingRow(title: "Account Deletion", systemImage: "person.crop.circle.badge.minus", color: .red)
            }

            Section {
                toggleRow(title: "Download with mobile data allowed", isOn: $downloadWithMobileData)
                settingRow(title: "About", systemImage: "info.circle", color: .gray)
            }

            Section {
                toggleRow(title: "Personalized Recommendations", isOn: $personalizedRecs)
                toggleRow(title: "Personalized Ads", isOn: $personalizedAds)
                toggleRow(title: "Marketing Communications", isOn: $marketingComms)
            }

#if DEBUG
            Section {
                Button {
                    showDebugPanel = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text("Developer: API Smoke")
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(DB.mutedText)
                    }
                }
                .listRowBackground(DB.panel)
            }
#endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DB.black)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
#if DEBUG
        .sheet(isPresented: $showDebugPanel) {
            DebugSettingsView()
        }
#endif
    }

    private func settingRow(title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 16)).foregroundColor(color).frame(width: 24)
            Text(title).font(.system(size: 15)).foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(DB.mutedText)
        }
        .listRowBackground(DB.panel)
    }

    private func settingRowWithValue(title: String, systemImage: String, color: Color, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 16)).foregroundColor(color).frame(width: 24)
            Text(title).font(.system(size: 15)).foregroundColor(.white)
            Spacer()
            Text(value).font(.system(size: 13)).foregroundColor(DB.mutedText)
        }
        .listRowBackground(DB.panel)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundColor(.white)
            Spacer()
            Toggle("", isOn: isOn).tint(DB.pink)
        }
        .listRowBackground(DB.panel)
    }
}

// MARK: - Top Up View

/// DramaBox Store 风格充值页
private struct TopUpView: View {
    @EnvironmentObject var coinStore: CoinStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.xl) {
                Text("DramaBox Store")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, DT.Space.pageH)
                    .padding(.top, DT.Space.lg)

                Text("Coin Packages")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, DT.Space.pageH)

                VStack(spacing: DT.Space.sm) {
                    ForEach(StoreKitManager().coinPackages) { pkg in
                        coinPackageCard(pkg)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)

                Text("Membership Packages")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, DT.Space.pageH)
                    .padding(.top, DT.Space.md)

                VStack(spacing: DT.Space.sm) {
                    ForEach(MockData.vipPlans) { plan in
                        vipPackageCard(plan)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)

                Text("Payment will be charged to your Apple ID account. Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period. Manage your subscriptions in App Store settings.")
                    .font(.system(size: 11))
                    .foregroundColor(DB.mutedText)
                    .padding(.horizontal, DT.Space.pageH)
                    .padding(.vertical, DT.Space.xl)
            }
        }
        .background(DB.black)
        .navigationTitle("Top Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func coinPackageCard(_ pkg: CoinPackage) -> some View {
        HStack(spacing: DT.Space.md) {
            ZStack {
                Circle().fill(DB.gold.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: "bitcoinsign.circle.fill").font(.system(size: 22)).foregroundColor(DB.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pkg.amount) Coins").font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                if let label = pkg.label { Text(label).font(.system(size: 12)).foregroundColor(DB.gold) }
            }
            Spacer()
            Text(pkg.displayPrice)
                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
        }
        .padding(DT.Space.lg)
        .background(DB.panel)
        .clipShape(RoundedRectangle(cornerRadius: DB.cardRadius))
    }

    private func vipPackageCard(_ plan: VIPPlan) -> some View {
        HStack(spacing: DT.Space.md) {
            ZStack {
                Circle().fill(DB.gold.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: "crown.fill").font(.system(size: 20)).foregroundColor(DB.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title).font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                if plan.isRecommended { Text("Best Value").font(.system(size: 12)).foregroundColor(DB.pink) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(plan.price).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                Text(plan.period).font(.system(size: 12)).foregroundColor(DB.mutedText)
            }
        }
        .padding(DT.Space.lg)
        .background(DB.panel)
        .clipShape(RoundedRectangle(cornerRadius: DB.cardRadius))
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
            followedCount: 0
        )
        authStore.isVip = true
        authStore.vipExpireDate = Date().addingTimeInterval(86400 * 30)
        authStore.coinBalance = 100
        authStore.loginMethod = .google
        return ProfileView()
            .environmentObject(authStore)
            .preferredColorScheme(.dark)
    }
}
#endif
