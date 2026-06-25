import SwiftUI

// MARK: - Rank Card View (DramaBox Style)

/// DramaBox 风格排行榜卡片
/// 布局：左侧大号排名数字 | 封面 | 标题+标签 | 右侧热度
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
                rankNumber
                coverImage
                infoSection
                Spacer(minLength: DT.Space.sm)
                heatSection
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: DB.cardRadius)
                    .fill(DB.panel)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rank Number

    private var rankNumber: some View {
        Text("\(drama.rank)")
            .font(.system(size: 26, weight: rankWeight, design: .rounded))
            .foregroundColor(rankColor)
            .frame(width: 30, alignment: .center)
            .padding(.trailing, 10)
    }

    // MARK: - Cover Image

    private var coverImage: some View {
        CoverImageView(
            url: drama.coverURL,
            aspectRatio: 3.0 / 4.0,
            cornerRadius: DB.posterRadius,
            width: 58,
            height: 78
        )
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(drama.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(DT.Color.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Text(drama.category)
                    .font(.system(size: 14))
                    .foregroundColor(DT.Color.textSecondary)
                    .lineLimit(1)

                if !drama.tags.isEmpty {
                    ForEach(drama.tags.prefix(1), id: \.self) { tag in
                        Text(",")
                            .font(.system(size: 14))
                            .foregroundColor(DT.Color.textSecondary)
                        Text(tag)
                            .font(.system(size: 14))
                            .foregroundColor(DT.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .lineLimit(1)
        }
        .padding(.leading, 12)
    }

    private var heatSection: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text(drama.hot)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(width: 54, alignment: .trailing)
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
