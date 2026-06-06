import SwiftUI

// MARK: - DS Loading View

/// 统一加载状态视图
/// 替换项目中所有 `ProgressView()` + 文字的组合
///
/// 用法：
/// ```swift
/// DSLoadingView()
/// DSLoadingView(message: "加载中...")
/// DSLoadingView(tint: .blue)
/// ```
struct DSLoadingView: View {
    var message: String? = nil
    var tint: SwiftUI.Color = DT.brandPink
    var scale: CGFloat = 1.2

    var body: some View {
        VStack(spacing: DT.Space.lg) {
            ProgressView()
                .tint(tint)
                .scaleEffect(scale)

            if let message = message {
                Text(message)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DS Tag View

/// 统一标签/徽章视图
/// 替换项目中所有临时的标签实现
///
/// 用法：
/// ```swift
/// DSTagView(text: "热门", style: .hot)
/// DSTagView(text: "VIP", style: .vip)
/// DSTagView(text: "推荐", style: .recommend)
/// ```
struct DSTagView: View {
    enum TagStyle {
        case hot       // 红色标签
        case vip        // 品牌粉色标签
        case recommend  // 品牌金色标签
        case `default`  // 默认灰色标签
        case custom(bg: SwiftUI.Color, textColor: SwiftUI.Color)

        var bgColor: SwiftUI.Color {
            switch self {
            case .hot:       return DT.hotTag.opacity(0.15)
            case .vip:        return DT.brandPink
            case .recommend:  return DT.brandGold.opacity(0.2)
            case .default:    return DT.Color.textSecondary.opacity(0.15)
            case .custom(let bg, _): return bg
            }
        }

        var textColor: SwiftUI.Color {
            switch self {
            case .hot:       return DT.hotTag
            case .vip:        return DT.Color.textPrimary
            case .recommend:  return DT.brandGold
            case .default:    return DT.Color.textSecondary
            case .custom(_, let text): return text
            }
        }
    }

    let text: String
    var style: TagStyle = .default
    var fontSize: SwiftUI.Font = DT.Font.small

    var body: some View {
        Text(text)
            .font(fontSize)
            .foregroundColor(style.textColor)
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, DT.Space.xs)
            .background(style.bgColor)
            .cornerRadius(DT.Radius.sm)
    }
}

// MARK: - DS Search Bar

/// 统一搜索栏组件
/// 替换项目中所有搜索栏实现
///
/// 用法：
/// ```swift
/// DSSearchBar(
///     text: $searchText,
///     placeholder: "搜索",
///     onSearch: { viewModel.submitSearch() },
///     onDismiss: { dismiss() }
/// )
/// ```
struct DSSearchBar: View {
    @Binding var text: String
    var placeholder: String = L10n.searchHint
    var showBackButton: Bool = true
    var showCancelButton: Bool = false
    var onSearch: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onCancel: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            // 返回按钮
            if showBackButton {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(DT.Font.subtitle)
                        .foregroundColor(DT.Color.textPrimary)
                        .frame(width: 32, height: 32)
                }
            }

            // 搜索输入框
            HStack(spacing: DT.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)

                TextField("", text: $text)
                    .font(DT.Font.bodyDefault)
                    .foregroundColor(DT.Color.textPrimary)
                    .focused($isFocused)
                    .tint(DT.brandPink)
                    .overlay(alignment: .leading) {
                        if text.isEmpty {
                            Text(placeholder)
                                .font(DT.Font.bodyDefault)
                                .foregroundColor(DT.Color.textTertiary)
                                .allowsHitTesting(false)
                        }
                    }
                    .onSubmit {
                        onSearch?()
                    }

                // 清除按钮
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DT.Font.caption)
                            .foregroundColor(DT.Color.textTertiary)
                    }
                }
            }
            .padding(.horizontal, DT.Space.md)
            .frame(height: DT.Layout.capsuleSearchHeight)
            .background(DT.Color.bgCard)
            .clipShape(Capsule())

            // 取消按钮
            if showCancelButton {
                Button {
                    text = ""
                    onCancel?()
                } label: {
                    Text(L10n.cancel)
                        .font(DT.Font.bodyDefault)
                        .foregroundColor(DT.Color.textSecondary)
                }
            }
        }
        .frame(height: 44)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - DS Tab Bar

/// 统一 Tab 切换栏组件
/// 替换项目中所有品类/tab 切换实现
///
/// 用法：
/// ```swift
/// DSTabBar(
///     tabs: ["精选", "排行榜"],
///     selectedIndex: $selectedIndex
/// )
/// ```
struct DSTabBar: View {
    let tabs: [String]
    @Binding var selectedIndex: Int
    var underlineColor: SwiftUI.Color = DT.brandPink
    var selectedColor: SwiftUI.Color = DT.Color.textPrimary
    var unselectedColor: SwiftUI.Color = DT.Color.textSecondary
    var font: SwiftUI.Font = DT.Font.largeTitle(24)

    var body: some View {
        HStack(spacing: DT.Space.xxl) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedIndex = index
                    }
                } label: {
                    VStack(spacing: DT.Space.xs) {
                        Text(tabs[index])
                            .foregroundColor(selectedIndex == index ? selectedColor : unselectedColor)
                            .font(selectedIndex == index ? font : DT.Font.largeTitle(22, weight: .regular))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(selectedIndex == index ? underlineColor : Color.clear)
                            .frame(width: 32, height: 4)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DSComponents_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DSLoadingView(message: "加载中...")
            DSTagView(text: "热门", style: .hot)
            DSTagView(text: "VIP", style: .vip)
            DSTagView(text: "推荐", style: .recommend)
            DSTagView(text: "标签", style: .default)
            DSSearchBar(text: .constant(""), showBackButton: true, showCancelButton: true)
            DSTabBar(tabs: ["精选", "排行榜"], selectedIndex: .constant(0))
        }
        .padding()
        .background(DT.Color.bgPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
