import SwiftUI

// MARK: - DramaBox Bottom TabBar

/// DramaBox 风格底部 TabBar — 独立组件，可替换当前 inline TabBar
/// 特点：纯黑底、小图标小文字、For You 页透明覆盖
struct DramaBoxBottomTabBar: View {
    @Binding var selectedTab: AppStore.Tab
    let transparent: Bool
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 8
    static let itemHitHeight: CGFloat = 44
    static let totalHeight: CGFloat = topPadding + itemHitHeight + bottomPadding

    init(
        selectedTab: Binding<AppStore.Tab>,
        transparent: Bool
    ) {
        self._selectedTab = selectedTab
        self.transparent = transparent
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppStore.Tab.allCases, id: \.rawValue) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
        .background(
            Group {
                if transparent {
                    Color.clear
                } else {
                    DB.black.ignoresSafeArea(edges: .bottom)
                }
            }
        )
    }

    private func tabButton(for tab: AppStore.Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.monochrome)

                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.itemHitHeight)
            .foregroundColor(
                isSelected ? DB.logoRed : .white.opacity(0.9)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
struct DramaBoxBottomTabBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            DramaBoxBottomTabBar(
                selectedTab: .constant(.forYou),
                transparent: true
            )
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
#endif
