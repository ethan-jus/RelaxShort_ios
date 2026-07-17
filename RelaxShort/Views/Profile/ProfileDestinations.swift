import SwiftUI
import StoreKit

// MARK: - Settings View

/// DramaBox 风格设置页。Task33 保持原有实现不变。
struct SettingsView: View {
    @State private var downloadWithMobileData = false
    @State private var personalizedAds = true
    @State private var personalizedRecs = true
    @State private var marketingComms = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @State private var showLogoutAlert = false
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
                settingRow(title: "Appearance", systemImage: "paintpalette.fill", color: .blue)
                Button {
                    showClearCacheAlert = true
                } label: {
                    settingRowWithValue(
                        title: "Clear Video Cache",
                        systemImage: "trash",
                        color: .gray,
                        value: ByteCountFormatter.string(fromByteCount: cachedVideoBytes, countStyle: .file)
                    )
                }
                settingRow(title: "Account Deletion", systemImage: "person.crop.circle.badge.minus", color: .red)
            }

            Section {
                toggleRow(title: "Download with mobile data allowed", isOn: $downloadWithMobileData)
                toggleRow(title: "Video cache", isOn: $videoCacheEnabled)
                Picker("Video cache limit", selection: $videoCacheMaximumBytes) {
                    Text("1 GB").tag(1 * 1024 * 1024 * 1024)
                    Text("2 GB").tag(2 * 1024 * 1024 * 1024)
                    Text("4 GB").tag(4 * 1024 * 1024 * 1024)
                }
                .disabled(!videoCacheEnabled)
                settingRow(title: "About", systemImage: "info.circle", color: .gray)
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
        .alert("Clear video cache?", isPresented: $showClearCacheAlert) {
            Button(L10n.cancel, role: .cancel) {}
            Button("Clear", role: .destructive) {
                HTTPRangeMediaCache.shared.clear()
                refreshCachedVideoBytes()
            }
        } message: {
            Text("Cached public videos will be removed. VIP downloads are not affected.")
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
    }

    private func refreshCachedVideoBytes() {
        cachedVideoBytes = HTTPRangeMediaCache.shared.totalCachedBytes()
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
            Toggle("", isOn: isOn).tint(DB.pink)
        }
        .listRowBackground(DB.panel)
    }
}

// MARK: - Top Up View

/// DramaBox Store 风格充值页。Task33 保持原有实现不变。
struct TopUpView: View {
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
