import SwiftUI

/// 钱包首页：图片 1 的余额背景 + 图片 3 的双操作按钮和流水布局。
struct WalletView: View {
    @StateObject private var viewModel: WalletViewModel
    private let repository: WalletRepositoryProtocol

    init(repository: WalletRepositoryProtocol = RealWalletRepository()) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: WalletViewModel(repository: repository))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                CompactProfileNavigationHeader(title: "wallet.title".localized)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                balanceHero
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                actionButtons
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                recentActivity
                    .padding(.top, 26)
            }
            .padding(.bottom, 28)
        }
        .background(DB.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            Task { await viewModel.load(limit: 4) }
        }
    }

    private var balanceHero: some View {
        ZStack(alignment: .trailing) {
            Image("ProfileRedLight")
                .resizable()
                .scaledToFill()
                .frame(height: 156)
                .opacity(0.78)
                .blendMode(.screen)
                .clipped()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("wallet.coin_balance".localized)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DB.mutedText)

                    HStack(spacing: 12) {
                        Image("RewardCoinIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)

                        Text(balanceText)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image("TopUpCoinStackLarge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 118, height: 88)
                    .offset(x: 4)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 156)
        .background(Color(hex: "#080605"))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(DT.brandGold.opacity(0.48), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("wallet.balance_accessibility".localizedFormat(viewModel.overview?.balance ?? 0))
    }

    private var balanceText: String {
        guard let balance = viewModel.overview?.balance else { return "—" }
        return balance.formatted(.number.grouping(.automatic))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            NavigationLink {
                TopUpView()
            } label: {
                walletActionLabel(
                    title: "wallet.top_up".localized,
                    systemImage: "plus.circle",
                    foreground: .white,
                    background: DT.logoRed,
                    border: DT.logoRed
                )
            }

            NavigationLink {
                CoinRewardView(mode: .pushed)
            } label: {
                walletActionLabel(
                    title: "wallet.earn_coins".localized,
                    systemImage: "gift",
                    foreground: DT.coinGold,
                    background: DB.panel.opacity(0.58),
                    border: DT.brandGold.opacity(0.52)
                )
            }
        }
    }

    private func walletActionLabel(
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        border: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(foreground)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(border, lineWidth: 0.8)
        }
    }

    private var recentActivity: some View {
        VStack(spacing: 0) {
            HStack {
                Text("wallet.recent_activity".localized)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if !(viewModel.overview?.transactions.isEmpty ?? true) {
                    NavigationLink {
                        WalletTransactionsView(repository: repository)
                    } label: {
                        HStack(spacing: 4) {
                            Text("wallet.view_all".localized)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DT.logoRed)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            if let transactions = viewModel.overview?.transactions, !transactions.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        WalletTransactionRow(transaction: transaction)
                        if index < transactions.count - 1 {
                            Divider()
                                .overlay(DB.divider)
                                .padding(.leading, 70)
                                .padding(.trailing, 20)
                        }
                    }
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .tint(DT.coinGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 42)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("wallet.load_failed".localized)
                        .foregroundColor(DB.mutedText)
                    Button("wallet.retry".localized) {
                        Task { await viewModel.load(limit: 4) }
                    }
                    .foregroundColor(DT.logoRed)
                    .accessibilityHint(error)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                Text("wallet.empty_activity".localized)
                    .font(.system(size: 14))
                    .foregroundColor(DB.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 42)
            }
        }
    }
}

private struct WalletTransactionRow: View {
    let transaction: WalletTransaction

    var body: some View {
        HStack(spacing: 12) {
            transactionIcon
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(dateText)
                    .font(.system(size: 12))
                    .foregroundColor(DB.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Text(amountText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(transaction.amount >= 0 ? DT.coinGold : .white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var transactionIcon: some View {
        ZStack {
            Circle()
                .fill(DB.panel.opacity(0.7))
                .overlay(Circle().stroke(DB.divider, lineWidth: 0.8))

            if transaction.source == "purchase" {
                Image("RewardCoinIcon")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(iconColor)
            }
        }
    }

    private var title: String {
        switch transaction.source {
        case "purchase": return "wallet.transaction.purchase".localized
        case "ad_reward": return "wallet.transaction.ad_reward".localized
        case "unlock_episode": return "wallet.transaction.episode_unlock".localized
        case "invite": return "wallet.transaction.invitation_reward".localized
        case "check_in": return "wallet.transaction.check_in".localized
        case "task": return "wallet.transaction.task_reward".localized
        case "account_merge": return "wallet.transaction.account_merge".localized
        default: return transaction.transactionType == "spend"
            ? "wallet.transaction.coin_spend".localized
            : "wallet.transaction.coin_reward".localized
        }
    }

    private var iconName: String {
        switch transaction.source {
        case "ad_reward": return "play.rectangle"
        case "unlock_episode": return "lock.fill"
        case "invite": return "person.badge.plus"
        case "check_in": return "calendar.badge.checkmark"
        case "task": return "gift"
        case "account_merge": return "arrow.triangle.merge"
        default: return transaction.amount >= 0 ? "plus.circle" : "minus.circle"
        }
    }

    private var iconColor: Color {
        transaction.source == "unlock_episode" ? DT.logoRed : DT.coinGold
    }

    private var amountText: String {
        let sign = transaction.amount >= 0 ? "+" : ""
        return sign + transaction.amount.formatted(.number.grouping(.automatic))
    }

    private var dateText: String {
        guard let date = transaction.createdAt else { return "wallet.date_unavailable".localized }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLocalization.currentLanguage.rawValue)
        formatter.timeStyle = .short
        if Calendar.current.isDateInToday(date) {
            return "wallet.today_time".localizedFormat(formatter.string(from: date))
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct CompactProfileNavigationHeader: View {
    @Environment(\.dismiss) private var dismiss

    let title: String

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(DB.panel.opacity(0.78))
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(DB.divider, lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("common.back".localized)

                Spacer()
            }
        }
        .frame(height: 46)
    }
}
