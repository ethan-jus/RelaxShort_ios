import SwiftUI

// MARK: - 规则弹窗视图
/// 从 CoinRewardView 右上角「规则」按钮触发
/// 半透明遮罩阻断背景交互 + 居中深灰圆角卡片 + 7 条可滚动规则
struct RulePopupView: View {
    @Binding var isPresented: Bool

    // MARK: - 规则内容（品牌名已从 DramaBox 替换为 RelaxShort）
    private let rulesText = """
    1. 活动最终解释权属于 RelaxShort。
    2. 用户每日只可签到一次。
    3. 如果用户因为未登录导致签到中断，签到进度将被重置回第一天。
    4. 奖励金币只可用来解锁剧集，您可以在钱包中查看历史记录。
    5. 金币在解锁剧集时会优先被使用，如果金额不够将会自动使用奖励金币。
    6. 除了金币和充值赠送的奖励金币是无限期的，从 2026/4/22 14:00(UTC+8) 起，其他奖励金币均存在 30 天有效期。
    7. 所有任务和签到会在太平洋时间 0 点刷新。
    """

    // MARK: - 动画
    private let animation: Animation = .easeInOut(duration: 0.2)

    var body: some View {
        ZStack {
            // 半透明遮罩 — 点击关闭
            DT.Color.bgPrimary
                .opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // 居中弹窗卡片
            VStack(spacing: 0) {
                // 标题栏：居中标题 + 右侧 ✕
                titleBar

                // 7 条规则 — 可滚动
                ScrollView(.vertical, showsIndicators: false) {
                    Text(rulesText)
                        .font(DT.Font.body(14))
                        .foregroundColor(DT.Color.textPrimary.opacity(0.85))
                        .lineSpacing(7)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, DT.Space.lg)
                }
            }
            .frame(width: UIApplication.screenSize.width * 0.85)
            .frame(maxHeight: 480)
            .background(DT.Color.bgModal)
            .cornerRadius(DT.Radius.xl)
            .shadow(color: DT.Color.bgPrimary.opacity(0.6), radius: 20, x: 0, y: 10)
            .transition(.scale.combined(with: .opacity))
        }
        .animation(animation, value: isPresented)
    }

    // MARK: - 标题栏
    private var titleBar: some View {
        ZStack(alignment: .trailing) {
            Text(L10n.rewardRules)
                .font(DT.Font.subtitle)
                .foregroundColor(DT.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(DT.Font.body(16, weight: .medium))
                    .foregroundColor(DT.Color.textPrimary.opacity(0.5))
                    .padding(10)
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, DT.Space.lg)
    }

    // MARK: - Helper
    private func dismiss() {
        withAnimation(animation) { isPresented = false }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        DT.Color.bgPrimary.ignoresSafeArea()
        RulePopupView(isPresented: .constant(true))
    }
    .preferredColorScheme(.dark)
}
