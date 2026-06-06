import SwiftUI

// MARK: - Search Default View
/// 搜索默认页 — 用户点击搜索框但未输入时的状态
/// 展示三个榜单（热搜榜/热播榜/新剧榜），横向滑动切换
/// 搜索栏由父视图 SearchView 的 toolbar 管理
struct SearchDefaultView: View {
    @StateObject private var viewModel: SearchDefaultViewModel

    init(viewModel: SearchDefaultViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            rankTabs

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .tint(DT.brandPink)
                Spacer()
            } else if let error = viewModel.errorMessage {
                errorStateView(error)
            } else {
                TabView(selection: $viewModel.selectedTab) {
                    rankList(dramas: viewModel.hotSearch, emptyMessage: L10n.noHotSearch)
                        .tag(0)
                    rankList(dramas: viewModel.hotPlay, emptyMessage: L10n.noHotPlay)
                        .tag(1)
                    rankList(dramas: viewModel.newDrama, emptyMessage: L10n.noNewDrama)
                        .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }

            Spacer(minLength: 0)
        }
        .background(DT.Color.bgPrimary.ignoresSafeArea())
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - Error State

    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: DT.Space.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(DT.Font.emptyIcon)
                .foregroundColor(DT.Color.textTertiary)
            Text(message)
                .font(DT.Font.bodyDefault)
                .foregroundColor(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
            Button(L10n.retry) {
                Task { await viewModel.loadData() }
            }
            .font(DT.Font.button)
            .foregroundColor(DT.brandPink)
            Spacer()
        }
        .padding(.horizontal, DT.Space.pageH)
    }

    // MARK: - 榜单 Tab 标签

    private var rankTabs: some View {
        HStack(spacing: 20) {
            rankTabButton(title: L10n.hotSearchTab, index: 0)
            rankTabButton(title: L10n.hotPlayTab, index: 1)
            rankTabButton(title: L10n.newDramaTab, index: 2)
            Spacer()
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.vertical, 6)
    }

    private func rankTabButton(title: String, index: Int) -> some View {
        Button {
            viewModel.switchTab(to: index)
        } label: {
            Text(title)
                .foregroundColor(viewModel.selectedTab == index ? DT.brandPink : DT.Color.textSecondary)
                .font(DT.Font.button)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 榜单列表

    @ViewBuilder
    private func rankList(dramas: [RankDrama], emptyMessage: String) -> some View {
        if dramas.isEmpty {
            VStack(spacing: DT.Space.md) {
                Image(systemName: "tray")
                    .font(DT.Font.emptyIcon)
                    .foregroundColor(DT.Color.textTertiary)
                Text(emptyMessage)
                    .font(DT.Font.bodyDefault)
                    .foregroundColor(DT.Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DT.Space.md) {
                    ForEach(dramas) { drama in
                        rankDramaRow(drama)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
                .padding(.top, DT.Space.sm)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - 榜单行

    private func rankDramaRow(_ drama: RankDrama) -> some View {
        HStack(spacing: DT.Space.md) {
            // 排名数字
            Text("\(drama.rank)")
                .font(DT.Font.largeTitle(22))
                .foregroundColor(drama.rank <= 3 ? DT.brandGold : DT.Color.textSecondary)
                .frame(width: 28)

            // 封面图
            CoverImageView(
                url: drama.coverURL,
                width: 80,
                height: 80
            )

            // 标题 & 分类
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(drama.title)
                    .foregroundColor(DT.Color.textPrimary)
                    .font(DT.Font.button)
                    .lineLimit(2)

                Text(drama.category + " " + drama.tags.joined(separator: " "))
                    .foregroundColor(DT.Color.textSecondary)
                    .font(DT.Font.caption)
                    .lineLimit(1)
            }

            Spacer()

            // 热度
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(DT.Font.body(14))
                    .foregroundColor(DT.hotTag)
                Text(drama.hot)
                    .foregroundColor(DT.Color.textPrimary)
                    .font(DT.Font.body(14, weight: .bold))
            }
        }
        .padding(DT.Space.md)
        .background(DT.Color.textPrimary.opacity(0.05))
        .cornerRadius(DT.Radius.md)
    }
}

#if DEBUG
#Preview("SearchDefault - Dark") {
    SearchDefaultView(viewModel: SearchDefaultViewModel(repository: MockHomeRepository()))
        .preferredColorScheme(.dark)
}
#endif
