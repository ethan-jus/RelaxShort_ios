import SwiftUI

// MARK: - Rank View (Embedded, DramaBox Style)

/// DramaBox 风格排行榜页面 — 嵌入首页 Rankings Tab
///
/// - 深色背景 + 顶部橙红渐变装饰
/// - 三个榜单切换: 热播榜/热搜榜/新剧榜
/// - 排名列表：大号排名数字(前三金色) + 60×80封面 + 标题+标签+播放量 + 右箭头
/// - 每个排名项可点击，通过 playerDrama 绑定触发上级页面的 SeriesPlayerView 导航
struct RankView: View {
    @Binding var playerDrama: DramaItem?
    @StateObject private var viewModel: RankViewModel

    init(playerDrama: Binding<DramaItem?>, repository: HomeRepositoryProtocol = MockHomeRepository()) {
        self._playerDrama = playerDrama
        self._viewModel = StateObject(wrappedValue: RankViewModel(repository: repository))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            gradientBar
            categoryTabs
            rankList
        }
        .background(DT.Color.bgPrimary)
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - Gradient Bar

    private var gradientBar: some View {
        LinearGradient(
            colors: [
                DT.rankGradientStart.opacity(0.35),
                DT.rankGradientMid.opacity(0.12),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 32)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        HStack(spacing: DT.Space.md) {
            ForEach(RankCategory.allCases) { category in
                rankCategoryPill(category)
            }
            Spacer()
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.sm)
        .padding(.bottom, DT.Space.md)
    }

    private func rankCategoryPill(_ category: RankCategory) -> some View {
        let isSelected = category == viewModel.selectedCategory

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.switchCategory(category)
            }
        } label: {
            Text(category.rawValue)
                .font(DT.Font.body(14, weight: .medium))
                .foregroundColor(isSelected ? DT.Color.textPrimary : DT.Color.textSecondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? DT.brandPink
                        : Color.clear
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : DT.Color.textPrimary.opacity(0.15),
                            lineWidth: 1
                        )
                )
                .clipShape(Capsule())
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
                        if index < viewModel.dramas.count - 1 {
                            Divider()
                                .background(DT.Color.textPrimary.opacity(0.06))
                                .padding(.leading, 36 + DT.Space.sm + 60 + DT.Space.md + DT.Space.pageH)
                        }
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
