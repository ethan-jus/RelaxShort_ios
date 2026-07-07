import SwiftUI

// MARK: - Rank View (Embedded, DramaBox Style)

/// DramaBox 风格排行榜页面 — 嵌入首页 Rankings Tab。
/// 顶部使用克制的棕黑氛围渐变，列表仍由真实 rankings API 驱动。
struct RankView: View {
    @Binding var playerDrama: DramaItem?
    @StateObject private var viewModel: RankViewModel
    private let onCategoryChange: (RankCategory) -> Void

    init(
        playerDrama: Binding<DramaItem?>,
        repository: HomeRepositoryProtocol,
        onCategoryChange: @escaping (RankCategory) -> Void = { _ in }
    ) {
        self._playerDrama = playerDrama
        self._viewModel = StateObject(wrappedValue: RankViewModel(repository: repository))
        self.onCategoryChange = onCategoryChange
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            categoryTabs
            rankList
        }
        .task {
            onCategoryChange(viewModel.selectedCategory)
            await viewModel.loadData()
        }
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        HStack(spacing: 8) {
            ForEach(RankCategory.allCases) { category in
                rankCategoryPill(category)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.sm)
        .padding(.bottom, 10)
    }

    private func rankCategoryPill(_ category: RankCategory) -> some View {
        let isSelected = category == viewModel.selectedCategory
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.switchCategory(category)
                onCategoryChange(category)
            }
        } label: {
            Text(category.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : DB.mutedText)
                .minimumScaleFactor(0.86)
                .padding(.horizontal, 6)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(isSelected ? category.pillColor : Color.clear))
                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rank List

    private var rankList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                if viewModel.isLoading {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage,
                          viewModel.dramas.isEmpty {
                    errorState(errorMessage)
                } else if viewModel.dramas.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(viewModel.dramas.enumerated()), id: \.element.id) { index, drama in
                        RankCardView(
                            drama: drama,
                            onTap: { playerDrama = drama.drama }
                        )
                        .padding(.horizontal, DT.Space.pageH)
                        .padding(.bottom, 16)
                    }
                }
            }
            .padding(.bottom, 64)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(DB.logoRed)
            Text(L10n.loading)
                .font(.system(size: 13))
                .foregroundColor(DT.Color.textSecondary)
        }
        .padding(.top, 60)
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundColor(DT.Color.textTertiary)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(DT.Color.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: {
                Task { await viewModel.loadData() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                    Text(L10n.retry)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .frame(height: 38)
                .background(DB.logoRed.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DT.Space.lg) {
            Image(systemName: "list.number")
                .font(DT.Font.emptyIcon)
                .foregroundColor(DT.Color.textTertiary)

            Text(L10n.noRankData)
                .font(DT.Font.bodyDefault)
                .foregroundColor(DT.Color.textSecondary)
        }
        .padding(.top, 60)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Rank View") {
    RankView(playerDrama: .constant(nil), repository: MockHomeRepository())
        .background(DT.Color.bgPrimary)
}
#endif

private extension RankCategory {
    var pillColor: Color {
        switch self {
        case .hot:
            Color(hex: "#7A5A4A")
        case .trending:
            Color(red: 0.35, green: 0.15, blue: 0.55)
        case .new:
            Color(red: 0.08, green: 0.35, blue: 0.38)
        }
    }
}
