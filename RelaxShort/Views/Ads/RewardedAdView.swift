import SwiftUI

// MARK: - Rewarded Ad View

/// 激励广告半屏弹窗 — 用户主动选择观看广告以获得奖励
///
/// 支持两种模式：
/// - `.earnCoins` — 观看广告赚金币
/// - `.unlockEpisode` — 观看广告解锁剧集
///
/// 交互流程：
/// 1. 展示广告位占位 + 倒计时「还剩 XX 秒即可获得奖励」
/// 2. 倒计时结束 → 绿色对勾动画 + 奖励文案
struct RewardedAdView: View {

    // MARK: - Mode

    enum Mode {
        case earnCoins(amount: Int)
        case unlockEpisode(number: Int, title: String)

        var title: String {
            switch self {
            case .earnCoins(let amount):
                return L10n.adWatchAdForCoins(amount)
            case .unlockEpisode:
                return L10n.adWatchAdToUnlock
            }
        }

        var subtitle: String {
            switch self {
            case .earnCoins:
                return L10n.adRewardTip
            case .unlockEpisode:
                return L10n.adUnlockTip
            }
        }
    }

    // MARK: - State

    let mode: Mode
    let countdown: Int
    let totalDuration: Int
    /// 是否已完成（展示奖励）
    let isCompleted: Bool
    /// 是否失败
    let isFailed: Bool
    /// 结果文案
    let resultText: String?

    var onDismiss: (() -> Void)?
    /// 完成回调（倒计时结束，但用户仍需看到结果）
    var onComplete: (() -> Void)?

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── 半透明遮罩 ──
            DT.Color.bgPrimary.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if isCompleted || isFailed { onDismiss?() }
                }

            // ── 居中广告卡片 ──
            VStack(spacing: 0) {
                // 关闭按钮（右上角）
                closeButton
                    .frame(maxWidth: .infinity, alignment: .trailing)

                // 广告位占位区域
                adPlaceholderArea
                    .padding(.top, DT.Space.sm)

                // 标题
                Text(mode.title)
                    .font(DT.Font.body(18, weight: .bold))
                    .foregroundColor(DT.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, DT.Space.lg)

                // 副标题
                Text(mode.subtitle)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, DT.Space.sm)

                // 进度区域：倒计时 / 完成状态
                progressArea
                    .padding(.top, DT.Space.xl)
                    .padding(.bottom, DT.Space.lg)
            }
            .padding(DT.Space.lg)
            .background(DT.Color.bgModal)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl))
            .padding(.horizontal, 30)
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button {
            onDismiss?()
        } label: {
            Image(systemName: "xmark")
                .font(DT.Font.body(12, weight: .semibold))
                .foregroundColor(DT.Color.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(DT.Color.textPrimary.opacity(0.08))
                )
        }
    }

    // MARK: - Ad Placeholder

    private var adPlaceholderArea: some View {
        ZStack {
            // 广告位占位渐变
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1a1a2e"),
                            Color(hex: "#2D1B69"),
                            Color(hex: "#16213e")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 200)

            VStack(spacing: DT.Space.md) {
                // 广告图标
                if isCompleted {
                    // 完成：绿色对勾
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(DT.success)
                        .transition(.scale.combined(with: .opacity))
                } else if isFailed {
                    // 失败：叉号
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(DT.hotTag)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    // 倒计时中：播放图标
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(DT.Color.textPrimary.opacity(0.4))
                }

                // 广告标签
                Text(L10n.adLabel)
                    .font(DT.Font.small)
                    .foregroundColor(DT.Color.textTertiary)
                    .padding(.horizontal, DT.Space.sm)
                    .padding(.vertical, DT.Space.xs)
                    .background(DT.Color.textPrimary.opacity(0.08))
                    .cornerRadius(DT.Radius.sm)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .stroke(DT.Color.textPrimary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Progress Area

    @ViewBuilder
    private var progressArea: some View {
        if isCompleted {
            completedView
        } else if isFailed {
            failedView
        } else {
            countdownView
        }
    }

    // MARK: - Countdown

    private var countdownView: some View {
        VStack(spacing: DT.Space.md) {
            // 倒计时数字
            Text(L10n.adSecondsRemaining(countdown))
                .font(DT.Font.largeTitle(36))
                .foregroundColor(DT.Color.textPrimary)

            // 进度条
            GeometryReader { geo in
                let progress = CGFloat(totalDuration - countdown) / CGFloat(totalDuration)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DT.Color.textPrimary.opacity(0.1))
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [DT.brandPink, DT.brandPinkDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 4), height: 4)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 4)

            // 观看提示
            Text(L10n.adPleaseKeepWatching)
                .font(DT.Font.small)
                .foregroundColor(DT.Color.textTertiary)
        }
    }

    // MARK: - Completed

    private var completedView: some View {
        VStack(spacing: DT.Space.md) {
            // 成功文字
            if let text = resultText {
                Text(text)
                    .font(DT.Font.body(18, weight: .bold))
                    .foregroundColor(DT.success)
                    .multilineTextAlignment(.center)
            }

            // 确认按钮
            Button {
                onDismiss?()
            } label: {
                Text("Got it")
                    .font(DT.Font.button)
                    .foregroundColor(DT.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DT.brandPink)
                    .cornerRadius(DT.Radius.md)
            }
        }
    }

    // MARK: - Failed

    private var failedView: some View {
        VStack(spacing: DT.Space.md) {
            Text(L10n.adLoadFailed)
                .font(DT.Font.body(16, weight: .medium))
                .foregroundColor(DT.Color.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                onDismiss?()
            } label: {
                Text(L10n.generalOk)
                    .font(DT.Font.button)
                    .foregroundColor(DT.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DT.Color.textPrimary.opacity(0.12))
                    .cornerRadius(DT.Radius.md)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("RewardedAdView — Countdown") {
    RewardedAdView(
        mode: .earnCoins(amount: 30),
        countdown: 3,
        totalDuration: 3,
        isCompleted: false,
        isFailed: false,
        resultText: nil,
        onDismiss: {},
        onComplete: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("RewardedAdView — Completed") {
    RewardedAdView(
        mode: .earnCoins(amount: 30),
        countdown: 0,
        totalDuration: 3,
        isCompleted: true,
        isFailed: false,
        resultText: "你已获得30金币",
        onDismiss: {},
        onComplete: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("RewardedAdView — Unlock") {
    RewardedAdView(
        mode: .unlockEpisode(number: 5, title: "第5集"),
        countdown: 3,
        totalDuration: 3,
        isCompleted: false,
        isFailed: false,
        resultText: nil,
        onDismiss: {},
        onComplete: {}
    )
    .preferredColorScheme(.dark)
}
#endif
