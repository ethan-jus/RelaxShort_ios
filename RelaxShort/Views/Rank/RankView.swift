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
            categoryTabs
            rankList
        }
        .background(DT.Color.bgPrimary)
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - Category Tabs

    // Task27 R3: 三 pill 均匀分布，单行不换行
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
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : DB.mutedText)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(isSelected ? DB.pink : Color.clear))
                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.15), lineWidth: 1))
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
                        .padding(.bottom, 10)
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
