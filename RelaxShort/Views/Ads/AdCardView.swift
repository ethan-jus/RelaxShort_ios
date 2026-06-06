import SwiftUI

// MARK: - Ad Card View

/// 瀑布流中插入的「赞助内容」广告卡片
///
/// 用于 MasonryWaterfall 和 MarketingGrid 等瀑布流/网格布局中，
/// 每 8 个内容卡片后插入一个 AdCard
///
/// 特点：
/// - 全宽展示，与内容卡片区分
/// - 右上角标注「广告」小字
/// - 点击可展示原生广告详情
struct AdCardView: View {

    /// 广告索引序号（用于区分不同广告位）
    let adIndex: Int

    /// 点击广告后的回调（展示原生广告内容）
    var onTap: (() -> Void)?

    // MARK: - Computed

    /// 模拟的赞助内容文案
    private var sponsorTitle: String {
        let titles = [
            L10n.adSponsoredContent1,
            L10n.adSponsoredContent2,
            L10n.adSponsoredContent3,
            L10n.adSponsoredContent4
        ]
        return titles[adIndex % titles.count]
    }

    private var sponsorSubtitle: String {
        let subtitles = [
            L10n.adSponsoredSubtitle1,
            L10n.adSponsoredSubtitle2,
            L10n.adSponsoredSubtitle3,
            L10n.adSponsoredSubtitle4
        ]
        return subtitles[adIndex % subtitles.count]
    }

    // MARK: - Body

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: DT.Space.md) {
                // 左侧赞助内容封面
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: DT.Radius.md)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#2D1B69"),
                                    Color(hex: "#1a1a3e")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 80)

                    // "广告" 标签
                    Text(L10n.adLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DT.Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DT.Color.bgPrimary.opacity(0.7))
                        .cornerRadius(DT.Radius.sm)
                        .padding(DT.Space.xs)
                }

                // 右侧文字信息
                VStack(alignment: .leading, spacing: DT.Space.sm) {
                    HStack(spacing: DT.Space.xs) {
                        Text(L10n.adSponsoredLabel)
                            .font(DT.Font.small)
                            .foregroundColor(DT.brandPink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DT.brandPink.opacity(0.1))
                            .cornerRadius(DT.Radius.sm)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(DT.Font.body(10, weight: .bold))
                            .foregroundColor(DT.Color.textTertiary)
                    }

                    Text(sponsorTitle)
                        .font(DT.Font.body(13, weight: .medium))
                        .foregroundColor(DT.Color.textPrimary)
                        .lineLimit(2)

                    Text(sponsorSubtitle)
                        .font(DT.Font.small)
                        .foregroundColor(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(DT.Space.md)
            .background(DT.Color.bgCard)
            .cornerRadius(DT.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.md)
                    .stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NativeAdDetailView

/// 原生广告详情弹窗 — 点击 AdCard 后展示
struct NativeAdDetailView: View {
    let adIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景
            DT.Color.bgPrimary.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // 广告主图片占位
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#2D1B69"),
                                    Color(hex: "#1a1a3e"),
                                    Color(hex: "#16213e")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 220)

                    // 广告标签
                    Text(L10n.adLabel)
                        .font(DT.Font.small)
                        .foregroundColor(DT.Color.textTertiary)
                        .padding(.horizontal, DT.Space.sm)
                        .padding(.vertical, DT.Space.xs)
                        .background(DT.Color.bgPrimary.opacity(0.5))
                        .cornerRadius(DT.Radius.sm)
                        .padding(DT.Space.md)
                }

                VStack(alignment: .leading, spacing: DT.Space.md) {
                    // 标题 + 赞助标签
                    HStack {
                        Text(L10n.adSponsoredLabel)
                            .font(DT.Font.small)
                            .foregroundColor(DT.brandPink)
                            .padding(.horizontal, DT.Space.sm)
                            .padding(.vertical, DT.Space.xs)
                            .background(DT.brandPink.opacity(0.1))
                            .cornerRadius(DT.Radius.sm)

                        Spacer()
                    }

                    Text(L10n.adNativeDetailTitle)
                        .font(DT.Font.body(20, weight: .bold))
                        .foregroundColor(DT.Color.textPrimary)

                    Text(L10n.adNativeDetailBody)
                        .font(DT.Font.body(14))
                        .foregroundColor(DT.Color.textSecondary)
                        .lineSpacing(6)

                    // CTA 按钮
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text(L10n.adLearnMore)
                                .font(DT.Font.button)
                            Spacer()
                        }
                        .foregroundColor(DT.Color.textPrimary)
                        .frame(height: 48)
                        .background(DT.brandPink)
                        .cornerRadius(DT.Radius.md)
                    }
                    .padding(.top, DT.Space.md)
                }
                .padding(DT.Space.lg)

                Spacer()
            }
        }
        .overlay(alignment: .topLeading) {
            // 返回按钮
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(DT.Font.body(18, weight: .medium))
                    .foregroundColor(DT.Color.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(DT.Color.bgPrimary.opacity(0.3))
                    )
            }
            .padding(.top, 50)
            .padding(.leading, DT.Space.lg)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AdCardView") {
    VStack(spacing: 16) {
        AdCardView(adIndex: 0, onTap: {})
        AdCardView(adIndex: 1, onTap: {})
    }
    .padding()
    .background(DT.Color.bgPrimary)
    .preferredColorScheme(.dark)
}

#Preview("NativeAdDetailView") {
    NativeAdDetailView(adIndex: 0)
        .preferredColorScheme(.dark)
}
#endif
