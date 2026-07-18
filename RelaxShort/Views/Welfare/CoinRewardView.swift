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
        let vm = viewModel ?? CoinRewardViewModel(repository: RealCoinRewardRepository())
        _viewModel = StateObject(wrappedValue: vm)
    }
    @State private var showRules = false
    @State private var showCoinPurchase = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
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

            // 金币购买弹窗
            if showCoinPurchase {
                CoinPurchaseSheet(
                    coinStore: coinStore,
                    storeKit: storeKitManager,
                    firstPurchaseBonusAvailable: viewModel.firstCoinPurchaseBonusAvailable,
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
        .onChange(of: viewModel.coinBalance) { _, balance in
            coinStore.synchronize(balance: balance)
        }
        .alert(
            "Ad unavailable",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var contentScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DT.Space.xl) {
                coinOverviewSection
                checkInCard
                adRewardCard
                bottomLegalDisclaimer
            }
            .padding(.top, DT.Space.sm)
        }
        .refreshable { await viewModel.loadData() }
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Check-in")
                        .font(DT.Font.body(17, weight: .bold))
                        .foregroundColor(DT.Color.textPrimary)
                    Text("Check in daily. Missing a day won't reset your progress.")
                        .font(DT.Font.caption)
                        .foregroundColor(DT.Color.textSecondary)
                }
                Spacer()
                Text("\(viewModel.checkedInCount)/7")
                    .font(DT.Font.body(13, weight: .bold))
                    .foregroundColor(DT.brandGold)
            }

            // 7天签到行
            HStack(spacing: 6) {
                ForEach(viewModel.checkInDays) { day in
                    checkInDayCell(day)
                        .frame(maxWidth: .infinity)
                }
            }

            // 签到按钮
            Button {
                Task { await viewModel.performCheckIn() }
            } label: {
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(checkInButtonTitle)
                        .font(DT.Font.body(15, weight: .bold))
                }
                .foregroundColor(viewModel.claimedCheckInToday ? DT.Color.textSecondary : .black)
                .frame(maxWidth: .infinity)
                .frame(height: DT.Layout.ctaButtonHeight)
                .background(viewModel.claimedCheckInToday ? DT.Color.textPrimary.opacity(0.08) : DT.brandGold)
                .cornerRadius(DT.Radius.md)
            }
            .disabled(viewModel.claimedCheckInToday || viewModel.isLoading)
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
            Text("+\(day.rewardCoins)")
                .font(DT.Font.body(11, weight: .bold))
                .foregroundColor(day.completed ? DT.Color.textSecondary : DT.brandGold)

            ZStack {
                Circle()
                    .fill(day.completed ? DT.brandGold.opacity(0.18) : DT.Color.textPrimary.opacity(0.06))
                    .frame(width: 32, height: 32)
                if day.completed {
                    Image(systemName: "checkmark")
                        .font(DT.Font.body(12, weight: .bold))
                        .foregroundColor(DT.brandGold)
                } else {
                    Image(systemName: day.current ? "sparkles" : "bitcoinsign.circle.fill")
                        .font(DT.Font.body(18))
                        .foregroundColor(DT.brandGold)
                }
            }

            Text("Day \(day.dayNumber)")
                .font(DT.Font.tabLabel)
                .foregroundColor(day.current ? DT.Color.textPrimary : DT.Color.textSecondary)
        }
        .padding(.vertical, DT.Space.sm)
        .background(day.current ? DT.brandGold.opacity(0.08) : DT.Color.textPrimary.opacity(0.03))
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.sm)
                .stroke(day.current ? DT.brandGold.opacity(0.65) : .clear, lineWidth: 1)
        }
        .cornerRadius(DT.Radius.sm)
    }

    private var adRewardCard: some View {
        VStack(alignment: .leading, spacing: DT.Space.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch & Earn")
                        .font(DT.Font.body(17, weight: .bold))
                        .foregroundColor(DT.Color.textPrimary)
                    Text("Rewards grow with each completed video today.")
                        .font(DT.Font.caption)
                        .foregroundColor(DT.Color.textSecondary)
                }
                Spacer()
                Text("\(viewModel.dailyAdWatchCount)/\(viewModel.maxDailyAdWatchCount)")
                    .font(DT.Font.body(13, weight: .bold))
                    .foregroundColor(DT.brandPink)
            }

            HStack(spacing: 8) {
                ForEach(viewModel.adRewardSteps) { step in
                    adRewardStepCell(step)
                        .frame(maxWidth: .infinity)
                }
            }

            Button {
                Task { await viewModel.watchAdForCoins() }
            } label: {
                HStack(spacing: DT.Space.sm) {
                    Image(systemName: "play.fill")
                    if viewModel.remainingAdWatchCount > 0 {
                        Text("Watch video  +\(viewModel.adWatchCoinReward) coins")
                    } else {
                        Text("All rewards claimed today")
                    }
                }
                .font(DT.Font.body(15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: DT.Layout.ctaButtonHeight)
                .background(viewModel.remainingAdWatchCount > 0 ? DT.brandPink : DT.Color.textPrimary.opacity(0.08))
                .cornerRadius(DT.Radius.md)
            }
            .disabled(viewModel.remainingAdWatchCount == 0 || viewModel.isLoading)

            Text("Only completed rewarded videos count. Rewards reset daily at 00:00 UTC.")
                .font(DT.Font.small)
                .foregroundColor(DT.Color.textTertiary)
        }
        .padding(DT.Space.lg)
        .background(DT.Color.bgCard)
        .cornerRadius(DT.Radius.lg)
        .padding(.horizontal, DT.Space.pageH)
    }

    private func adRewardStepCell(_ step: AdRewardStep) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(step.completed ? DT.brandPink.opacity(0.18) : DT.Color.textPrimary.opacity(0.06))
                    .frame(width: 34, height: 34)
                Image(systemName: step.completed ? "checkmark" : "play.fill")
                    .font(DT.Font.body(12, weight: .bold))
                    .foregroundColor(step.completed || step.current ? DT.brandPink : DT.Color.textSecondary)
            }
            Text("+\(step.rewardCoins)")
                .font(DT.Font.body(12, weight: .bold))
                .foregroundColor(step.current ? DT.Color.textPrimary : DT.Color.textSecondary)
        }
        .padding(.vertical, DT.Space.sm)
        .background(step.current ? DT.brandPink.opacity(0.1) : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: DT.Radius.sm)
                .stroke(step.current ? DT.brandPink.opacity(0.65) : .clear, lineWidth: 1)
        }
        .cornerRadius(DT.Radius.sm)
    }

    private var checkInButtonTitle: String {
        if viewModel.claimedCheckInToday {
            return "Checked in today"
        }
        if let reward = viewModel.nextCheckInReward {
            return "Check in  +\(reward) coins"
        }
        return "Check in"
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
