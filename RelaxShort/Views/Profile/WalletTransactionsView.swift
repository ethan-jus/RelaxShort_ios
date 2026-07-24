import SwiftUI

/// 钱包流水页：月度收支、类型筛选、按日分组和游标分页均使用真实后端数据。
struct WalletTransactionsView: View {
    @StateObject private var viewModel: WalletTransactionsViewModel

    init(repository: WalletRepositoryProtocol = RealWalletRepository()) {
        _viewModel = StateObject(
            wrappedValue: WalletTransactionsViewModel(repository: repository)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0, pinnedViews: []) {
                monthSummary
                filters
                    .padding(.top, 20)
                    .padding(.bottom, 14)
                transactionContent
            }
            .padding(.bottom, 32)
        }
        .background(DB.black.ignoresSafeArea())
        .compactSecondaryNavigation(
            title: "wallet.transaction_history".localized
        )
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var monthSummary: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(viewModel.availableMonths, id: \.self) { month in
                    Button(monthTitle(month)) {
                        Task { await viewModel.selectMonth(month) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(monthTitle(viewModel.selectedMonth))
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(minWidth: 88, alignment: .leading)
            }

            Spacer(minLength: 4)
            summaryValue(
                title: "wallet.earned".localized,
                value: "+\(formatted(viewModel.totalEarned))",
                color: DT.coinGold
            )
            summaryValue(
                title: "wallet.spent".localized,
                value: "-\(formatted(viewModel.totalSpent))",
                color: DT.logoRed
            )
        }
        .padding(.horizontal, 20)
        .frame(height: 88)
        .background(DB.panel.opacity(0.58))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DB.divider)
                .frame(height: 0.5)
        }
    }

    private func summaryValue(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DB.mutedText)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(color)
        }
        .frame(minWidth: 72, alignment: .trailing)
    }

    private var filters: some View {
        HStack(spacing: 10) {
            filterButton(
                title: "wallet.filter_all".localized,
                selected: viewModel.selectedCategory == .all
            ) {
                Task { await viewModel.selectCategory(.all) }
            }

            Menu {
                ForEach(WalletTransactionCategory.allCases.filter { $0 != .all }) { category in
                    Button(categoryTitle(category)) {
                        Task { await viewModel.selectCategory(category) }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(viewModel.selectedCategory == .all
                         ? "wallet.filter_type".localized
                         : categoryTitle(viewModel.selectedCategory))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(viewModel.selectedCategory == .all ? DB.mutedText : .white)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(DB.panel)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(DB.divider, lineWidth: 1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func filterButton(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selected ? .white : DB.mutedText)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(selected ? DT.logoRed : DB.panel)
                .clipShape(Capsule())
                .overlay {
                    if !selected {
                        Capsule().stroke(DB.divider, lineWidth: 1)
                    }
                }
        }
    }

    @ViewBuilder
    private var transactionContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .tint(DT.coinGold)
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
        } else if let error = viewModel.errorMessage, viewModel.transactions.isEmpty {
            VStack(spacing: 12) {
                Text("wallet.load_failed".localized)
                    .foregroundColor(DB.mutedText)
                Button("wallet.retry".localized) {
                    Task { await viewModel.load() }
                }
                .foregroundColor(DT.logoRed)
                .accessibilityHint(error)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
        } else if dayGroups.isEmpty {
            Text("wallet.empty_activity".localized)
                .font(.system(size: 14))
                .foregroundColor(DB.mutedText)
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
        } else {
            ForEach(dayGroups) { group in
                VStack(spacing: 0) {
                    Text(dayTitle(group.date))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DB.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    ForEach(group.transactions) { transaction in
                        WalletHistoryRow(transaction: transaction)
                            .onAppear {
                                if transaction.id == viewModel.transactions.last?.id {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        Divider()
                            .overlay(DB.divider)
                            .padding(.leading, 84)
                            .padding(.trailing, 20)
                    }
                }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(DT.coinGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        }
    }

    private var dayGroups: [WalletTransactionDayGroup] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: viewModel.transactions) { transaction in
            transaction.createdAt.map(calendar.startOfDay(for:)) ?? .distantPast
        }
        return grouped.keys.sorted(by: >).map {
            WalletTransactionDayGroup(date: $0, transactions: grouped[$0] ?? [])
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    private func dayTitle(_ date: Date) -> String {
        guard date != .distantPast else { return "wallet.date_unavailable".localized }
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter.string(from: date)
    }

    private func categoryTitle(_ category: WalletTransactionCategory) -> String {
        switch category {
        case .all: return "wallet.filter_all".localized
        case .purchase: return "wallet.filter_purchases".localized
        case .reward: return "wallet.filter_rewards".localized
        case .unlock: return "wallet.filter_unlocks".localized
        }
    }

    private func formatted(_ amount: Int) -> String {
        amount.formatted(.number.grouping(.automatic))
    }
}

private struct WalletTransactionDayGroup: Identifiable {
    let date: Date
    let transactions: [WalletTransaction]

    var id: Date { date }
}

private struct WalletHistoryRow: View {
    let transaction: WalletTransaction

    var body: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(DB.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(amountText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(transaction.amount >= 0 ? DT.coinGold : .white)
                if let balance = transaction.balanceAfter {
                    Text("wallet.balance_after".localizedFormat(balance))
                        .font(.system(size: 11))
                        .foregroundColor(DB.mutedText)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(DB.panel)
                .overlay(Circle().stroke(DB.divider, lineWidth: 1))

            if transaction.source == "purchase" {
                Image("RewardCoinIcon")
                    .resizable()
                    .scaledToFit()
                    .padding(9)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(transaction.source == "unlock_episode" ? DT.logoRed : DT.coinGold)
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

    private var detail: String {
        let source: String
        switch transaction.source {
        case "purchase": source = "wallet.detail.app_store".localized
        case "ad_reward": source = "wallet.detail.watch_ad".localized
        case "unlock_episode": source = "wallet.detail.paid_episode".localized
        case "invite": source = "wallet.detail.invite_friends".localized
        case "check_in": source = "wallet.detail.daily_bonus".localized
        case "task": source = "wallet.detail.complete_task".localized
        default: source = title
        }

        guard let date = transaction.createdAt else { return source }
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.locale
        formatter.timeStyle = .short
        return "\(formatter.string(from: date)) · \(source)"
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

    private var amountText: String {
        let sign = transaction.amount >= 0 ? "+" : ""
        return sign + transaction.amount.formatted(.number.grouping(.automatic))
    }
}
