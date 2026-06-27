import SwiftUI

/// 右侧露出下一榜单的吸附式分页容器。
struct SearchRankingPager: View {
    @ObservedObject var viewModel: SearchDefaultViewModel
    let onDramaSelected: (DramaItem) -> Void

    @State private var scrollTarget: SearchRankTheme? = .topSearched

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = proxy.size.width * 0.04
            let pageSpacing = proxy.size.width * 0.025
            let pageWidth = proxy.size.width * 0.84
            let trailingInset = proxy.size.width - pageWidth

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: pageSpacing) {
                    ForEach(SearchRankTheme.allCases) { theme in
                        rankingPage(theme)
                            .frame(width: pageWidth)
                            .id(theme)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.leading, horizontalInset, for: .scrollContent)
            .contentMargins(
                .trailing,
                trailingInset,
                for: .scrollContent
            )
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $scrollTarget, anchor: .leading)
            .onChange(of: scrollTarget) { _, newValue in
                guard let newValue, newValue != viewModel.selectedTheme else {
                    return
                }
                viewModel.selectTheme(newValue)
            }
            .onChange(of: viewModel.selectedTheme) { _, newValue in
                guard scrollTarget != newValue else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    scrollTarget = newValue
                }
            }
        }
    }

    private func rankingPage(_ theme: SearchRankTheme) -> some View {
        Group {
            if viewModel.items(for: theme).isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                    Text(L10n.noSearchResults)
                        .font(.system(size: 14))
                }
                .foregroundColor(DB.mutedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.items(for: theme)) { item in
                            SearchRankCardView(
                                item: item,
                                theme: theme,
                                onTap: { onDramaSelected(item.drama) }
                            )
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
