import SwiftUI

// MARK: - Rank View (Embedded, DramaBox Style)

/// DramaBox 风格排行榜页面 — 嵌入首页 Rankings Tab。
/// 顶部使用克制的棕黑氛围渐变，列表仍由真实 rankings API 驱动。
struct RankView: View {
    @Binding var playerDrama: DramaItem?
    @StateObject private var viewModel: RankViewModel

    init(playerDrama: Binding<DramaItem?>, repository: HomeRepositoryProtocol = MockHomeRepository()) {
        self._playerDrama = playerDrama
        self._viewModel = StateObject(wrappedValue: RankViewModel(repository: repository))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            rankingBackdrop
            VStack(spacing: 0) {
                categoryTabs
                rankList
            }
        }
        .background(DT.Color.bgPrimary)
        .task {
            await viewModel.loadData()
        }
    }

    private var rankingBackdrop: some View {
        LinearGradient(
            colors: viewModel.selectedCategory.backdropColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 260)
        .ignoresSafeArea(edges: .horizontal)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        HStack(spacing: 0) {
            ForEach(RankCategory.allCases) { category in
                rankCategoryPill(category)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.sm)
        .padding(.bottom, DT.Space.md)
    }

    private func rankCategoryPill(_ category: RankCategory) -> some View {
        let isSelected = category == viewModel.selectedCategory
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.switchCategory(category) }
        } label: {
            Text(category.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : DB.mutedText)
                .minimumScaleFactor(0.86)
                .padding(.horizontal, 8)
                .frame(height: 40)
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
                    ProgressView()
                        .tint(DT.Color.textSecondary)
                        .padding(.top, 40)
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
    RankView(playerDrama: .constant(nil))
        .background(DT.Color.bgPrimary)
}
#endif

private extension RankCategory {
    var pillColor: Color {
        switch self {
        case .hot:
            Color(hex: "#7A5A4A")
        case .trending:
            Color(hex: "#635A62")
        case .new:
            Color(hex: "#5E6049")
        }
    }

    var backdropColors: [Color] {
        switch self {
        case .hot:
            [
                Color(hex: "#4A3028").opacity(0.95),
                Color(hex: "#261A18").opacity(0.72),
                DB.black
            ]
        case .trending:
            [
                Color(hex: "#35313C").opacity(0.9),
                Color(hex: "#1F1C22").opacity(0.7),
                DB.black
            ]
        case .new:
            [
                Color(hex: "#3A3B2A").opacity(0.88),
                Color(hex: "#202016").opacity(0.7),
                DB.black
            ]
        }
    }
}
