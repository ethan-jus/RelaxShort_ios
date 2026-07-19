import SwiftUI

// MARK: - Reward Presentation Mode

enum CoinRewardPresentationMode {
    case tab
    case pushed
}

// MARK: - 奖励中心

struct CoinRewardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var coinStore: CoinStore
    @EnvironmentObject var storeKitManager: StoreKitManager
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: CoinRewardViewModel

    private let mode: CoinRewardPresentationMode
    private let pageInset: CGFloat = 20
    private let headerHeight: CGFloat = 54
    private let sectionGap: CGFloat = 30
    private let rewardGold = Color(hex: "#E4BA66")

    @State private var showRules = false
    @State private var showCoinPurchase = false

    init(
        mode: CoinRewardPresentationMode = .tab,
        viewModel: CoinRewardViewModel? = nil
    ) {
        self.mode = mode
        let vm = viewModel ?? CoinRewardViewModel(
            repository: RealCoinRewardRepository()
        )
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        GeometryReader { geo in
            let topInset = max(
                geo.safeAreaInsets.top,
                UIApplication.safeAreaInsets.top
            )
            let bottomInset = max(
                geo.safeAreaInsets.bottom,
                UIApplication.safeAreaInsets.bottom
            )
            let tabClearance = mode == .tab
                ? DramaBoxBottomTabBar.totalHeight + bottomInset
                : bottomInset

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: topInset + headerHeight)

                        heroSection(width: geo.size.width)

                        dailyCheckInSection
                            .padding(.top, 14)

                        sectionDivider
                            .padding(.top, sectionGap)

                        watchAndEarnSection
                            .padding(.top, sectionGap)

                        sectionDivider
                            .padding(.top, sectionGap)

                        moreRewardsSection
                            .padding(.top, sectionGap)

                        inviteFriendsSection
                            .padding(.top, 24)

                        firstPurchaseSection
                            .padding(.top, 16)

                        rewardRulesRow
                            .padding(.top, 20)

                        bottomLegalDisclaimer
                            .padding(.bottom, tabClearance + 20)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .refreshable { await viewModel.loadData() }

                header(topInset: topInset)
                    .zIndex(2)

                if showRules {
                    RulePopupView(isPresented: $showRules)
                        .zIndex(50)
                }

                if showCoinPurchase {
                    CoinPurchaseSheet(
                        coinStore: coinStore,
                        storeKit: storeKitManager,
                        firstPurchaseBonusAvailable:
                            viewModel.firstCoinPurchaseBonusAvailable,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showCoinPurchase = false
                            }
                        },
                        fetchAppleAccountToken: {
                            try await dependencies.detailRepository
                                .fetchAppleAccountToken()
                        },
                        verifyPurchase: { receipt in
                            try await dependencies.detailRepository
                                .verifyCoinPurchase(receipt)
                        }
                    )
                    .transition(.move(edge: .bottom))
                    .zIndex(100)
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled(mode == .pushed)
        .animation(.easeInOut(duration: 0.28), value: showCoinPurchase)
        .onReceive(
            NotificationCenter.default.publisher(for: .showCoinPurchase)
        ) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showCoinPurchase = true
            }
        }
        .onChange(of: viewModel.coinBalance) { _, balance in
            coinStore.synchronize(balance: balance)
        }
        .alert(
            "奖励暂不可用",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(L10n.generalOk, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Header & Hero

private extension CoinRewardView {
    func header(topInset: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.96)
                .ignoresSafeArea(edges: .top)

            Text("奖励中心")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            HStack {
                if mode == .pushed {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("返回")
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRules = true
                    }
                } label: {
                    Text(L10n.rules)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(minWidth: 40, minHeight: 40)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: headerHeight)
        .padding(.top, topInset)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
    }

    func heroSection(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RewardsHeroArtwork(
                width: width,
                height: 224,
                opacity: 0.92
            )

            LinearGradient(
                colors: [
                    .black,
                    .black.opacity(0.9),
                    .black.opacity(0.16),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.myCoins)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(rewardGold)

                HStack(alignment: .center, spacing: 10) {
                    Text("\(coinStore.coinBalance)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(rewardGold)
                        .contentTransition(.numericText())

                    RewardCoinBadge(
                        size: 46,
                        glowColor: rewardGold,
                        glowRadius: 3,
                        brightness: 0.02,
                        motion: .bounce
                    )
                    .accessibilityLabel(L10n.coinsUnit)
                }
                .padding(.top, 4)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showCoinPurchase = true
                    }
                } label: {
                    HStack(spacing: 7) {
                        RewardCoinStackIcon(
                            size: 20,
                            glowColor: rewardGold
                        )
                        Text(L10n.buyCoins)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(rewardGold)
                    .padding(.horizontal, 15)
                    .frame(height: 34)
                    .overlay {
                        Capsule()
                            .stroke(rewardGold.opacity(0.72), lineWidth: 1)
                    }
                }
                .padding(.top, 12)
            }
            .padding(.leading, pageInset)
        }
        .frame(width: width, height: 224)
        .clipped()
    }
}

// MARK: - Daily Check-in

private extension CoinRewardView {
    var dailyCheckInSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            rewardSectionHeader(
                title: L10n.coinDailyCheckIn,
                subtitle: "连续签到7天，金币奖励逐步提升",
                completed: viewModel.checkedInCount,
                total: 7,
                color: rewardGold
            )

            if viewModel.checkInDays.isEmpty {
                rewardLoadingRow
            } else {
                progressTrack(
                    items: viewModel.checkInDays.map {
                        RewardProgressItem(
                            id: $0.id,
                            amount: $0.rewardCoins,
                            completed: $0.completed,
                            current: $0.current,
                            label: "\($0.dayNumber)"
                        )
                    },
                    color: rewardGold,
                    style: .checkIn
                )
            }

            Button {
                Task { await viewModel.performCheckIn() }
            } label: {
                HStack(spacing: 7) {
                    Image(
                        systemName: viewModel.claimedCheckInToday
                            ? "checkmark.circle.fill"
                            : "calendar.badge.plus"
                    )
                    Text(checkInButtonTitle)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(
                    viewModel.claimedCheckInToday
                        ? .white.opacity(0.42)
                        : .black
                )
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    viewModel.claimedCheckInToday
                        ? Color.white.opacity(0.08)
                        : rewardGold
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .disabled(
                viewModel.claimedCheckInToday
                    || viewModel.isLoading
                    || viewModel.checkInDays.isEmpty
            )
        }
        .padding(.horizontal, pageInset)
    }

    var checkInButtonTitle: String {
        if viewModel.claimedCheckInToday {
            return "今日已签到"
        }
        if let reward = viewModel.nextCheckInReward {
            return "立即签到  +\(reward)"
        }
        return viewModel.isLoading ? L10n.loading : "立即签到"
    }
}

// MARK: - Watch & Earn

private extension CoinRewardView {
    var watchAndEarnSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            rewardSectionHeader(
                title: "看视频赚金币",
                subtitle: "完整观看视频，领取金币奖励",
                completed: viewModel.dailyAdWatchCount,
                total: max(
                    viewModel.maxDailyAdWatchCount,
                    max(viewModel.adRewardSteps.count, 5)
                ),
                color: DT.logoRed
            )

            if viewModel.adRewardSteps.isEmpty {
                rewardLoadingRow
            } else {
                progressTrack(
                    items: viewModel.adRewardSteps.map {
                        RewardProgressItem(
                            id: $0.id,
                            amount: $0.rewardCoins,
                            completed: $0.completed,
                            current: $0.current,
                            label: "\($0.stepNumber)"
                        )
                    },
                    color: DT.logoRed,
                    style: .video
                )
            }

            Button {
                Task { await viewModel.watchAdForCoins() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text(watchAdButtonTitle)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    viewModel.remainingAdWatchCount > 0
                        ? DT.logoRed
                        : Color.white.opacity(0.08)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .disabled(
                viewModel.remainingAdWatchCount == 0
                    || viewModel.isLoading
                    || viewModel.adRewardSteps.isEmpty
            )

            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11, weight: .medium))
                Text("完整观看后发放奖励，每日00:00重置")
                    .font(.system(size: 11))
            }
            .foregroundColor(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, pageInset)
    }

    var watchAdButtonTitle: String {
        guard viewModel.remainingAdWatchCount > 0 else {
            return "今日奖励已全部领取"
        }
        guard !viewModel.adRewardSteps.isEmpty else {
            return viewModel.isLoading ? L10n.loading : "奖励暂不可用"
        }
        return "观看视频  +\(viewModel.adWatchCoinReward)"
    }
}

// MARK: - Marketing rewards

private extension CoinRewardView {
    var moreRewardsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("更多赚币方式")
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, pageInset)

            VStack(spacing: 0) {
                plannedTaskRow(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "登录账号",
                    subtitle: "首次登录并完成账号绑定",
                    reward: 30
                )
                taskDivider
                plannedTaskRow(
                    icon: "play.rectangle.on.rectangle",
                    title: "连续观看 3 集",
                    subtitle: "当天完整观看任意短剧 3 集",
                    reward: 20
                )
                taskDivider
                plannedTaskRow(
                    icon: "bookmark",
                    title: "收藏喜欢的短剧",
                    subtitle: "首次收藏任意一部短剧",
                    reward: 10
                )
                taskDivider
                plannedTaskRow(
                    icon: "square.and.arrow.up",
                    title: "分享精彩内容",
                    subtitle: "分享短剧给好友，每日限 1 次",
                    reward: 10
                )
            }
            .background(Color(hex: "#111111"))
            .clipShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
            .padding(.horizontal, pageInset)
        }
    }

    func plannedTaskRow(
        icon: String,
        title: String,
        subtitle: String,
        reward: Int
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(rewardGold)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                rewardAmount(reward)
                Text("即将开放")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.36))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 76)
        .accessibilityElement(children: .combine)
        .accessibilityHint("该任务尚未开放")
    }

    var inviteFriendsSection: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#241307"),
                    Color(hex: "#150A07"),
                    Color(hex: "#160506")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    rewardGold.opacity(0.2),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 2,
                endRadius: 180
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(rewardGold.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(rewardGold)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("邀请好友，一起追剧")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("好友完成注册并观看 3 集后，双方获得奖励")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.52))
                    }
                }

                HStack(spacing: 0) {
                    inviteRewardColumn(
                        title: "你可获得",
                        amount: 100
                    )

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 44)

                    inviteRewardColumn(
                        title: "好友可获得",
                        amount: 50
                    )
                }

                HStack {
                    Text("每周最多奖励 3 位有效好友")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text("即将开放")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(rewardGold.opacity(0.72))
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(rewardGold.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal, pageInset)
    }

    func inviteRewardColumn(
        title: String,
        amount: Int
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.44))
            rewardAmount(amount)
        }
        .frame(maxWidth: .infinity)
    }

    var firstPurchaseSection: some View {
        Button {
            guard viewModel.firstCoinPurchaseBonusAvailable else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showCoinPurchase = true
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DT.logoRed.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "gift.fill")
                        .font(.system(size: 21))
                        .foregroundColor(DT.logoRed)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("首充金币翻倍")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text("指定首充档位可享等额赠币，到账以购买页为准")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                }

                Spacer(minLength: 8)

                Text(
                    viewModel.firstCoinPurchaseBonusAvailable
                        ? "去购买"
                        : "已享受"
                )
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(
                    viewModel.firstCoinPurchaseBonusAvailable
                        ? .white
                        : .white.opacity(0.35)
                )
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background(
                    viewModel.firstCoinPurchaseBonusAvailable
                        ? DT.logoRed
                        : Color.white.opacity(0.08)
                )
                .clipShape(Capsule())
            }
            .padding(14)
            .background(Color(hex: "#111111"))
            .clipShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.firstCoinPurchaseBonusAvailable)
        .padding(.horizontal, pageInset)
    }

    var rewardRulesRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showRules = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 17))
                    .foregroundColor(rewardGold)
                    .frame(width: 26)
                Text(L10n.rewardRules)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.28))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color(hex: "#0E0E0E"))
            .clipShape(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, pageInset)
    }
}

// MARK: - Shared layout

private extension CoinRewardView {
    func rewardSectionHeader(
        title: String,
        subtitle: String? = nil,
        completed: Int,
        total: Int,
        color: Color
    ) -> some View {
        HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(rewardGold)
                    .frame(width: 5, height: 30)
                    .shadow(color: rewardGold.opacity(0.35), radius: 3)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.42))
                    }
                }
            }

            Spacer()

            HStack(spacing: 2) {
                Text("\(completed)")
                    .foregroundColor(color)
                Text("/\(total)")
                    .foregroundColor(.white.opacity(0.32))
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .padding(.top, 4)
        }
    }

    func progressTrack(
        items: [RewardProgressItem],
        color: Color,
        style: RewardProgressStyle
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                rewardProgressNode(
                    item,
                    color: color,
                    style: style
                )

                if index < items.count - 1 {
                    let nextItem = items[index + 1]
                    Rectangle()
                        .fill(
                            item.completed
                                && (nextItem.completed || nextItem.current)
                                ? color
                                : color.opacity(0.2)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)
                        .offset(y: style == .checkIn ? 31 : 17)
                }
            }
        }
    }

    func rewardProgressNode(
        _ item: RewardProgressItem,
        color: Color,
        style: RewardProgressStyle
    ) -> some View {
        VStack(spacing: 6) {
            if style == .checkIn {
                Text(item.current ? "今天" : " ")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color)
                    .frame(height: 8)
            }

            ZStack {
                Circle()
                    .fill(
                        item.completed || item.current
                            ? color.opacity(0.16)
                            : Color(hex: "#151515")
                    )
                    .frame(width: 36, height: 36)

                Circle()
                    .stroke(
                        item.completed || item.current
                            ? color
                            : color.opacity(0.28),
                        lineWidth: item.current ? 1.8 : 1
                    )
                    .frame(width: 36, height: 36)

                if item.completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(color)
                } else {
                    Text(item.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(
                            item.current
                                ? color
                                : .white.opacity(0.42)
                        )
                }
            }

            if style == .checkIn {
                Text("第\(item.label)天")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.32))
                    .lineLimit(1)
            }

            Text("+\(item.amount)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color.opacity(item.current ? 1 : 0.88))
        }
        .frame(width: 38)
    }

    func rewardAmount(_ amount: Int) -> some View {
        HStack(spacing: 4) {
            Text("+\(amount)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(rewardGold)
            RewardCoinBadge(
                size: 18,
                glowColor: rewardGold,
                glowRadius: 1
            )
        }
    }

    var rewardLoadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(rewardGold)
            Spacer()
        }
        .frame(height: 74)
    }

    var taskDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.065))
            .frame(height: 0.5)
            .padding(.leading, 60)
    }

    var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.055))
            .frame(height: 8)
    }

    var bottomLegalDisclaimer: some View {
        VStack(spacing: 7) {
            Text("奖励到账、有效期及每日上限以奖励规则和服务端记录为准。")
            Text(L10n.appleDisclaimer)
        }
        .font(.system(size: 10))
        .foregroundColor(.white.opacity(0.24))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.top, 22)
    }
}

private struct RewardProgressItem: Identifiable {
    let id: Int
    let amount: Int
    let completed: Bool
    let current: Bool
    let label: String
}

private enum RewardProgressStyle {
    case checkIn
    case video
}

// MARK: - Preview

#Preview {
    CoinRewardView()
        .environmentObject(CoinStore())
        .environmentObject(StoreKitManager())
        .environmentObject(DependencyContainer())
        .preferredColorScheme(.dark)
}
