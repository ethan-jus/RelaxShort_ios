import SwiftUI
import StoreKit

// MARK: - Account Profile

/// Apple 登录不提供头像 URL；资料页展示服务端头像，缺失时使用稳定的品牌首字母头像。
struct AccountProfileView: View {
    let user: User
    let displayName: String
    let isVIP: Bool
    let vipExpireDate: Date?
    let onMembershipTap: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    ProfileAvatarView(
                        url: user.avatarURL,
                        initials: String(displayName.prefix(2)).uppercased(),
                        size: 112
                    )

                    Text(displayName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("ID \(user.id)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DB.mutedText)
                        .textSelection(.enabled)
                }
                .padding(.top, 18)

                VStack(spacing: 0) {
                    if let email = user.email, !email.isEmpty {
                        accountRow(
                            icon: "envelope.fill",
                            title: "profile.email".localized,
                            value: email
                        )
                    }

                    accountRow(
                        icon: "crown.fill",
                        title: isVIP
                            ? "profile.membership_active".localized
                            : "profile.join_membership".localized,
                        value: membershipDetail,
                        showsDivider: false
                    )
                }
                .background(DB.panel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DB.divider, lineWidth: 0.8)
                }
                .padding(.horizontal, DT.Space.pageH)

                ProfileMembershipCard(
                    isVIP: isVIP,
                    vipExpireDate: vipExpireDate,
                    onJoin: onMembershipTap
                )
            }
            .padding(.bottom, 36)
        }
        .background(DB.black.ignoresSafeArea())
        .compactSecondaryNavigation(title: "profile.tab.title".localized)
    }

    private var membershipDetail: String {
        guard isVIP else { return "vip.unlock_all".localized }
        guard let vipExpireDate else { return "vip.unlock_all".localized }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "profile.membership_active_until".localizedFormat(
            formatter.string(from: vipExpireDate)
        )
    }

    private func accountRow(
        icon: String,
        title: String,
        value: String,
        showsDivider: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DT.memberGold)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundColor(DB.mutedText)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 62)

            if showsDivider {
                Divider()
                    .overlay(DB.divider)
                    .padding(.leading, 50)
            }
        }
    }
}

// MARK: - Settings View

/// DramaBox 风格设置页。Task33 保持原有实现不变。
struct SettingsView: View {
    @AppStorage("offlineDownloadsCellularEnabled")
    private var downloadWithMobileData = false
    @State private var personalizedRecs = true
    @State private var marketingComms = false
    @ObservedObject private var privacyConsent = PrivacyConsentManager.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @State private var showLogoutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var accountDeletionMessage: String?
    @State private var cachedVideoBytes: Int64 = 0
    @State private var showClearCacheAlert = false
    @State private var subscriptionManagementError: String?
    @AppStorage("playerMediaCacheEnabled") private var videoCacheEnabled = true
    @AppStorage("playerMediaCacheMaximumBytes") private var videoCacheMaximumBytes = Int(PlayerMediaCacheSettings.defaultMaximumBytes)
#if DEBUG
    @State private var showDebugPanel = false
#endif

    var body: some View {
        List {
            Section {
                Button(action: manageSubscription) {
                    settingRow(
                        title: "member.manage_subscription".localized,
                        systemImage: "crown.fill",
                        color: DB.gold
                    )
                }
                if authStore.isLoggedIn,
                   let email = authStore.currentUser?.email,
                   !email.isEmpty {
                    settingRowWithValue(
                        title: "profile.email".localized,
                        systemImage: "envelope.fill",
                        color: .white,
                        value: email
                    )
                }
                settingRow(title: "settings.appearance".localized, systemImage: "paintpalette.fill", color: .blue)
                Button {
                    showClearCacheAlert = true
                } label: {
                    settingRowWithValue(
                        title: "settings.clear_video_cache".localized,
                        systemImage: "trash",
                        color: .gray,
                        value: ByteCountFormatter.string(fromByteCount: cachedVideoBytes, countStyle: .file)
                    )
                }
                if authStore.isLoggedIn {
                    Button {
                        showDeleteAccountAlert = true
                    } label: {
                        HStack {
                            settingRow(
                                title: "settings.delete_account".localized,
                                systemImage: "person.crop.circle.badge.minus",
                                color: .red
                            )
                            if isDeletingAccount {
                                ProgressView().tint(.white)
                            }
                        }
                    }
                    .disabled(isDeletingAccount)
                }
            }

            Section {
                toggleRow(title: "settings.mobile_data_download".localized, isOn: $downloadWithMobileData)
                toggleRow(title: "settings.video_cache".localized, isOn: $videoCacheEnabled)
                Picker("settings.video_cache_limit".localized, selection: $videoCacheMaximumBytes) {
                    Text("1 GB").tag(1 * 1024 * 1024 * 1024)
                    Text("2 GB").tag(2 * 1024 * 1024 * 1024)
                    Text("4 GB").tag(4 * 1024 * 1024 * 1024)
                }
                .disabled(!videoCacheEnabled)
                settingRow(title: "settings.about".localized, systemImage: "info.circle", color: .gray)
            }

            if authStore.isLoggedIn {
                Section {
                    Button(role: .destructive) {
                        showLogoutAlert = true
                    } label: {
                        Text(L10n.logout)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Section {
                toggleRow(title: "settings.personalized_recommendations".localized, isOn: $personalizedRecs)
                if privacyConsent.isPrivacyOptionsRequired {
                    Button {
                        Task { await privacyConsent.presentPrivacyOptions() }
                    } label: {
                        settingRow(
                            title: "settings.privacy_options".localized,
                            systemImage: "hand.raised.fill",
                            color: .blue
                        )
                    }
                }
                toggleRow(title: "settings.marketing_communications".localized, isOn: $marketingComms)
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
        .compactSecondaryNavigation(title: "profile.settings".localized)
        .onAppear { refreshCachedVideoBytes() }
        .onChange(of: videoCacheMaximumBytes) { _, _ in
            HTTPRangeMediaCache.shared.pruneIfNeeded()
        }
#if DEBUG
        .sheet(isPresented: $showDebugPanel) {
            DebugSettingsView()
        }
#endif
        .alert(L10n.confirmLogout, isPresented: $showLogoutAlert) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.logout, role: .destructive) {
                authStore.logout()
                dismiss()
            }
        } message: {
            Text(L10n.logoutConfirmMessage)
        }
        .alert("settings.delete_account_question".localized, isPresented: $showDeleteAccountAlert) {
            Button(L10n.cancel, role: .cancel) {}
            Button("settings.delete_permanently".localized, role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("settings.delete_account_message".localized)
        }
        .alert(
            accountDeletionMessage ?? "",
            isPresented: Binding(
                get: { accountDeletionMessage != nil },
                set: { if !$0 { accountDeletionMessage = nil } }
            )
        ) {
            Button(L10n.generalOk) {
                if !authStore.isLoggedIn { dismiss() }
            }
        }
        .alert("settings.clear_cache_question".localized, isPresented: $showClearCacheAlert) {
            Button(L10n.cancel, role: .cancel) {}
            Button("settings.clear".localized, role: .destructive) {
                HTTPRangeMediaCache.shared.clear()
                refreshCachedVideoBytes()
            }
        } message: {
            Text("settings.clear_cache_message".localized)
        }
        .alert(
            subscriptionManagementError ?? "",
            isPresented: Binding(
                get: { subscriptionManagementError != nil },
                set: { if !$0 { subscriptionManagementError = nil } }
            )
        ) {
            Button("common.cancel".localized, role: .cancel) {}
        }
        .alert(
            privacyConsent.lastErrorMessage ?? "",
            isPresented: Binding(
                get: { privacyConsent.lastErrorMessage != nil },
                set: { if !$0 { privacyConsent.clearLastError() } }
            )
        ) {
            Button("common.cancel".localized, role: .cancel) {
                privacyConsent.clearLastError()
            }
        }
        }

    private func refreshCachedVideoBytes() {
        cachedVideoBytes = HTTPRangeMediaCache.shared.totalCachedBytes()
    }

    private func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        Task {
            do {
                let manualAppleRevocationRequired = try await authStore.deleteAccount()
                if manualAppleRevocationRequired {
                    accountDeletionMessage = "settings.delete_success_apple".localized
                } else {
                    accountDeletionMessage = "settings.delete_success".localized
                }
            } catch {
                accountDeletionMessage = "settings.delete_failed".localizedFormat(error.localizedDescription)
            }
            isDeletingAccount = false
        }
    }

    private func manageSubscription() {
        Task {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            else {
                subscriptionManagementError =
                    "member.manage_subscription_unavailable".localized
                return
            }
            do {
                try await StoreKit.AppStore.showManageSubscriptions(in: scene)
            } catch {
                subscriptionManagementError = error.localizedDescription
            }
        }
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
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(DB.mutedText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .listRowBackground(DB.panel)
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundColor(.white)
            Spacer()
            Toggle("", isOn: isOn).tint(DB.logoRed)
        }
        .listRowBackground(DB.panel)
    }
}

// MARK: - Placeholder View

/// 通用占位页
struct PlaceholderView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DT.Space.lg) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 44))
                .foregroundColor(DB.mutedText)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text(L10n.featureInDevelopment)
                .font(DT.Font.caption)
                .foregroundColor(DB.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DB.black)
        .compactSecondaryNavigation(title: title)
    }
}
