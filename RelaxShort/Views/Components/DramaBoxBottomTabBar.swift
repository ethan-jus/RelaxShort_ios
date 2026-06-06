import SwiftUI

// MARK: - DramaBox Bottom TabBar

/// DramaBox 风格底部 TabBar — 独立组件，可替换当前 inline TabBar
/// 特点：纯黑底、小图标小文字、For You 页透明覆盖
struct DramaBoxBottomTabBar: View {
    @Binding var selectedTab: AppStore.Tab
    let transparent: Bool
    let bottomInset: CGFloat

    init(
        selectedTab: Binding<AppStore.Tab>,
        transparent: Bool,
        bottomInset: CGFloat = 0
    ) {
        self._selectedTab = selectedTab
        self.transparent = transparent
        self.bottomInset = bottomInset
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppStore.Tab.allCases, id: \.rawValue) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.top, 8)
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
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.monochrome)

                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 35)
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
                transparent: true,
                bottomInset: 34
            )
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
#endif
