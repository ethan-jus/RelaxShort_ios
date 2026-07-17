import SwiftUI

// MARK: - Reward Presentation Mode

enum CoinRewardPresentationMode {
    case tab
    case pushed
}

// MARK: - 赚金币 / 福利中心主视图
struct CoinRewardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var coinStore: CoinStore
    @EnvironmentObject var storeKitManager: StoreKitManager
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: CoinRewardViewModel
    private let mode: CoinRewardPresentationMode

    init(
        mode: CoinRewardPresentationMode = .tab,
        viewModel: CoinRewardViewModel? = nil
    ) {
        self.mode = mode
        let vm = viewModel ?? CoinRewardViewModel(repository: MockCoinRewardRepository())
        _viewModel = StateObject(wrappedValue: vm)
    }
    @State private var showRules = false
    @State private var showCoinPurchase = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                subTabsView
                contentScrollView
            }
            .background(DT.Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(mode == .pushed ? "Rewards" : "")
            .navigationBarTitleDisplayMode(mode == .pushed ? .inline : .automatic)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showRules = true } }) {
                        Text(L10n.rules)
                            .font(DT.Font.small)
                            .foregroundColor(DT.Color.textSecondary)
                            .padding(.horizontal, DT.Space.sm)
                            .padding(.vertical, 2)
                            .background(DT.Color.textPrimary.opacity(0.1))
                            .cornerRadius(DT.Radius.full)
                    }
                }
            }

            // 规则弹窗
            if showRules {
                RulePopupView(isPresented: $showRules)
            }

            // 激励广告弹窗
            if viewModel.isShowingRewardedAd {
                RewardedAdView(
                    mode: .earnCoins(amount: viewModel.adWatchCoinReward),
                    countdown: viewModel.adCountdown,
                    totalDuration: viewModel.adDuration,
                    isCompleted: false,
                    isFailed: false,
                    resultText: nil,
                    onDismiss: {
                        viewModel.isShowingRewardedAd = false
                    }
                )
                .zIndex(2)
            }

            // 金币购买弹窗
            if showCoinPurchase {
                CoinPurchaseSheet(
                    coinStore: coinStore,
                    storeKit: storeKitManager,
                    onDismiss: { withAnimation(.easeInOut(duration: 0.25)) { showCoinPurchase = false } },
                    fetchAppleAccountToken: {
                        try await dependencies.detailRepository.fetchAppleAccountToken()
                    },
                    verifyPurchase: { receipt in
                        try await dependencies.detailRepository.verifyCoinPurchase(receipt)
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showCoinPurchase)
        .onReceive(NotificationCenter.default.publisher(for: .showCoinPurchase)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { showCoinPurchase = true }
        }
    }

    // MARK: - 二级 Tab 切换
    private var subTabsView: some View {
        HStack(spacing: DT.Space.xxl) {
            VStack(spacing: 6) {
                Text(L10n.coinRewardTab)
                    .font(DT.Font.button)
                    .foregroundColor(DT.Color.textPrimary)
                Capsule()
                    .frame(width: 30, height: 2)
                    .foregroundColor(DT.Color.textPrimary)
            }
            VStack(spacing: 6) {
                Text(L10n.memberPointsTab)
                    .font(DT.Font.body(16))
                    .foregroundColor(DT.Color.textSecondary)
                Capsule()
                    .frame(width: 30, height: 2)
                    .foregroundColor(.clear)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.Space.xs)
        .background(DT.Color.bgPrimary)
    }

    // MARK: - 内容滚动区
    private var contentScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DT.Space.xl) {
                coinOverviewSection
                checkInCard
                taskSectionHeader
                taskListSection
                bottomLegalDisclaimer
            }
        }
    }

    // MARK: - ① 金币总览
    private var coinOverviewSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text("\(coinStore.coinBalance)")
                    .font(DT.Font.largeTitle(40))
                    .foregroundColor(DT.brandGold)
                Text(L10n.myCoins)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
            }
            Spacer()

            // 购买金币按钮
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showCoinPurchase = true }
            } label: {
                HStack(spacing: DT.Space.xs) {
                    Image(systemName: "plus.circle.fill")
                        .font(DT.Font.body(14))
                    Text(L10n.buyCoins)
                        .font(DT.Font.body(13, weight: .medium))
                }
                .foregroundColor(DT.brandGold)
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, DT.Space.sm)
                .background(DT.brandGold.opacity(0.12))
                .cornerRadius(DT.Radius.full)
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.sm)
    }

    // MARK: - ② 签到卡片
    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            Text(L10n.checkedInDays(viewModel.checkedInCount))
                .font(DT.Font.body(16, weight: .medium))
                .foregroundColor(DT.Color.textPrimary)

            // 7天签到行
            HStack(spacing: 6) {
                ForEach(viewModel.checkInDays) { day in
                    checkInDayCell(day)
                        .frame(maxWidth: .infinity)
                }
            }

            // 签到按钮
            Button(action: { viewModel.performCheckIn() }) {
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(L10n.coinDailyCheckIn)
                        .font(DT.Font.body(15, weight: .bold))
                }
                .foregroundColor(DT.Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: DT.Layout.ctaButtonHeight)
                .background(DT.brandPink)
                .cornerRadius(DT.Radius.md)
            }
            .padding(.top, DT.Space.xs)
        }
        .padding(DT.Space.lg)
        .background(DT.Color.bgCard)
        .cornerRadius(DT.Radius.lg)
        .padding(.horizontal, DT.Space.pageH)
    }

    // MARK: - 签到日单元格
    private func checkInDayCell(_ day: CheckInDay) -> some View {
        VStack(spacing: DT.Space.sm) {
            Text(day.coins)
                .font(DT.Font.body(11, weight: .bold))
                .foregroundColor(day.checked ? DT.Color.textSecondary : DT.brandGold)

            ZStack {
                Circle()
                    .fill(day.checked ? DT.Color.bgCard : DT.brandGold.opacity(0.2))
                    .frame(width: 32, height: 32)
                if day.checked {
                    Image(systemName: "checkmark")
                        .font(DT.Font.body(12, weight: .bold))
                        .foregroundColor(DT.brandGold)
                } else {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(DT.Font.body(18))
                        .foregroundColor(DT.brandGold)
                }
            }

            Text(day.label)
                .font(DT.Font.tabLabel)
                .foregroundColor(DT.Color.textSecondary)
        }
        .padding(.vertical, DT.Space.sm)
        .background(DT.Color.textPrimary.opacity(0.03))
        .cornerRadius(DT.Radius.sm)
    }

    // MARK: - ③ 赚金币任务标题
    private var taskSectionHeader: some View {
        Text(L10n.earnCoins)
            .font(DT.Font.button)
            .foregroundColor(DT.Color.textPrimary)
            .padding(.horizontal, DT.Space.pageH)
            .padding(.top, DT.Space.sm)
    }

    // MARK: - ④ 任务卡片列表
    private var taskListSection: some View {
        VStack(spacing: DT.Space.md) {
            // 看广告赚金币每日任务
            adWatchTaskCard

            ForEach(viewModel.tasks) { task in
                taskCard(task)
            }
        }
        .padding(.horizontal, DT.Space.pageH)
    }

    // MARK: - 广告观看任务卡片
    private var adWatchTaskCard: some View {
        let canWatch = viewModel.remainingAdWatchCount > 0

        return HStack(spacing: DT.Space.md) {
            // 左侧图标
            ZStack {
                Circle()
                    .fill(canWatch ? DT.brandPink.opacity(0.15) : DT.Color.textPrimary.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: "play.rectangle.fill")
                    .font(DT.Font.body(18))
                    .foregroundColor(canWatch ? DT.brandPink : DT.Color.textSecondary)
            }

            // 中间文字
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text("Watch Ad +\(viewModel.adWatchCoinReward) Coins")
                    .font(DT.Font.body(14, weight: .medium))
                    .foregroundColor(DT.Color.textPrimary)
                if canWatch {
                    Text(L10n.adRemainingCount(viewModel.remainingAdWatchCount))
                        .font(DT.Font.caption)
                        .foregroundColor(DT.Color.textSecondary)
                } else {
                    Text(L10n.adLimitReached)
                        .font(DT.Font.caption)
                        .foregroundColor(DT.Color.textTertiary)
                }
            }

            Spacer()

            // 右侧按钮
            Button {
                guard canWatch else { return }
                viewModel.isShowingRewardedAd = true
            } label: {
                Text(canWatch ? L10n.adWatchNow : L10n.adWatchedToday)
                    .font(DT.Font.body(13, weight: .medium))
                    .foregroundColor(canWatch ? DT.Color.textPrimary : DT.Color.textTertiary)
                    .padding(.horizontal, DT.Space.lg)
                    .padding(.vertical, DT.Space.sm)
                    .background(canWatch ? DT.brandPink : DT.Color.textPrimary.opacity(0.08))
                    .cornerRadius(DT.Radius.sm)
            }
            .disabled(!canWatch)
        }
        .padding(DT.Space.lg)
        .background(DT.Color.bgCard)
        .cornerRadius(DT.Radius.lg)
    }

    // MARK: - 单个任务卡片
    private func taskCard(_ task: CoinTask) -> some View {
        HStack(spacing: DT.Space.md) {
            // 左侧图标
            ZStack {
                Circle()
                    .fill(DT.Color.textPrimary.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: task.iconName)
                    .font(DT.Font.body(18))
                    .foregroundColor(DT.Color.textPrimary.opacity(0.9))
            }

            // 中间文字
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(task.title)
                    .font(DT.Font.body(14, weight: .medium))
                    .foregroundColor(DT.Color.textPrimary)
                Text(task.subtitle)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
            }

            Spacer()

            // 右侧按钮
            Button(action: { viewModel.performTask(task) }) {
                Text(task.buttonText)
                    .font(DT.Font.body(13, weight: .medium))
                    .foregroundColor(DT.Color.textPrimary)
                    .padding(.horizontal, DT.Space.lg)
                    .padding(.vertical, DT.Space.sm)
                    .background(DT.brandPink)
                    .cornerRadius(DT.Radius.sm)
            }
        }
        .padding(DT.Space.lg)
        .background(DT.Color.bgCard)
        .cornerRadius(DT.Radius.lg)
    }

    // MARK: - ⑤ 底部合规声明
    private var bottomLegalDisclaimer: some View {
        HStack {
            Spacer()
            Text(L10n.appleDisclaimer)
                .font(DT.Font.small)
                .foregroundColor(DT.Color.textPrimary.opacity(0.3))
                .padding(.vertical, DT.Space.xl)
            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    CoinRewardView()
        .environmentObject(CoinStore())
        .environmentObject(StoreKitManager())
        .environmentObject(DependencyContainer())
        .preferredColorScheme(.dark)
}
