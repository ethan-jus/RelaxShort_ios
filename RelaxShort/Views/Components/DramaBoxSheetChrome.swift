import SwiftUI

// MARK: - DramaBox Sheet Chrome

/// DramaBox 风格通用底部弹层容器
/// 暗色遮罩 + 底部圆角卡片 + 顶部拖拽指示条 + 关闭按钮
struct DramaBoxSheetChrome<Content: View>: View {
    @Binding var isPresented: Bool
    let content: Content
    var showDragIndicator: Bool = true
    var heightFraction: CGFloat = 0.4

    init(
        isPresented: Binding<Bool>,
        showDragIndicator: Bool = true,
        heightFraction: CGFloat = 0.4,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.showDragIndicator = showDragIndicator
        self.heightFraction = min(0.95, max(0.2, heightFraction))
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Dimmed backdrop
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                // Sheet panel
                VStack(spacing: 0) {
                    // Drag indicator
                    if showDragIndicator {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                    }

                    content
                        .frame(maxWidth: .infinity)
                }
                .frame(
                    width: geo.size.width,
                    height: geo.size.height * heightFraction
                )
                .background(DB.panel)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: DB.sheetCornerRadius,
                        style: .continuous
                    )
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

#if DEBUG
struct DramaBoxSheetChrome_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DB.black.ignoresSafeArea()
            DramaBoxSheetChrome(
                isPresented: .constant(true),
                heightFraction: 0.35
            ) {
                VStack(spacing: 16) {
                    Text("Sheet Title")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("This is the sheet content area. It's a dark bottom sheet with DramaBox style.")
                        .font(.system(size: 14))
                        .foregroundColor(DB.mutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button {} label: {
                        Text("Action Button")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(DB.pink)
                            .cornerRadius(DB.ctaRadius)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
