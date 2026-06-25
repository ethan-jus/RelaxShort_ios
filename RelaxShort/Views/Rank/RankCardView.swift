import SwiftUI

// MARK: - Rank Card View (DramaBox Style)

/// DramaBox 风格排行榜卡片
/// 布局：左侧大号排名数字 | 60×80 封面 | 标题+标签+播放量 | 右箭头
/// 前三名排名数字使用金色
struct RankCardView: View {
    let drama: RankDrama
    var onTap: (() -> Void)?

    // MARK: - Rank Color

    private var rankColor: Color {
        drama.rank <= 3 ? DT.brandGold : DT.Color.textPrimary
    }

    private var rankWeight: Font.Weight {
        drama.rank <= 3 ? .heavy : .bold
    }

    // MARK: - Body

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 0) {
                // ① 排名数字
                rankNumber

                // ② 封面 60×80
                coverImage

                // ③ 剧集信息
                infoSection

                Spacer(minLength: DT.Space.sm)
            }
            .padding(.vertical, DT.Space.sm)
            .padding(.horizontal, DT.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DB.panel)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rank Number

    private var rankNumber: some View {
        Text("\(drama.rank)")
            .font(.system(size: 28, weight: rankWeight, design: .rounded))
            .foregroundColor(rankColor)
            .frame(width: 36, alignment: .center)
            .padding(.trailing, DT.Space.sm)
    }

    // MARK: - Cover Image

    private var coverImage: some View {
        CoverImageView(
            url: drama.coverURL,
            aspectRatio: 3.0 / 4.0,
            cornerRadius: DB.posterRadius,
            width: 60,
            height: 80
        )
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 标题 (最多2行)
            Text(drama.title)
                .font(DT.Font.body(15, weight: .medium))
                .foregroundColor(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 标签行
            HStack(spacing: 6) {
                // 分类标签
                Text(drama.category)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
                    .lineLimit(1)

                // tags
                if !drama.tags.isEmpty {
                    ForEach(drama.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(DT.Font.body(11))
                            .foregroundColor(DT.Color.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DT.Color.textPrimary.opacity(0.08))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer().frame(height: 2)

            // 热度
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(DT.Font.body(11))
                    .foregroundColor(DT.brandGold)
                Text(drama.hot)
                    .font(DT.Font.body(12))
                    .foregroundColor(DT.Color.textTertiary)
            }
        }
        .padding(.leading, DT.Space.md)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Rank Card") {
    VStack(spacing: 0) {
        RankCardView(drama: RankDrama(
            from: DramaItem(
                id: "1", title: "莫言春度芳菲尽", coverURL: "",
                category: "古代言情", tags: ["古装", "甜宠"],
                viewCount: 25300, episodeCount: 60, currentEpisode: 0,
                synopsis: "", isHot: true, isTrending: true, rating: 9.1
            ),
            rank: 1
        ))
        Divider()
        RankCardView(drama: RankDrama(
            from: DramaItem(
                id: "2", title: "影帝的心尖月光", coverURL: "",
                category: "现代言情", tags: ["娱乐圈"],
                viewCount: 18900, episodeCount: 38, currentEpisode: 0,
                synopsis: "", isHot: true, isTrending: false, rating: 9.3
            ),
            rank: 2
        ))
        Divider()
        RankCardView(drama: RankDrama(
            from: DramaItem(
                id: "4", title: "Breathe", coverURL: "",
                category: "总裁", tags: ["romance", "ceo"],
                viewCount: 12700, episodeCount: 70, currentEpisode: 0,
                synopsis: "", isHot: false, isTrending: false, rating: 9.3
            ),
            rank: 4
        ))
    }
    .background(DT.Color.bgPrimary)
}
#endif
