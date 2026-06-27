import SwiftUI

/// Search 榜单的统一条目。前三名使用主题渐变，其余条目使用近黑背景。
struct SearchRankCardView: View {
    let item: RankDrama
    let theme: SearchRankTheme
    let onTap: () -> Void

    private var metadataText: String {
        ([item.category] + item.tags.prefix(1))
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                poster

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if !metadataText.isEmpty {
                        Text(metadataText)
                            .font(.system(size: 11))
                            .foregroundColor(DB.mutedText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(item.hot)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(10)
            .frame(height: 104)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            L10n.searchRankAccessibility(rank: item.rank, title: item.title)
        )
    }

    private var poster: some View {
        ZStack(alignment: .topLeading) {
            CoverImageView(
                url: item.coverURL,
                aspectRatio: 2.0 / 3.0,
                cornerRadius: DB.posterRadius,
                width: 64,
                height: 88
            )

            Text("\(item.rank)")
                .font(.system(size: item.rank <= 3 ? 16 : 12, weight: .bold))
                .foregroundColor(.white)
                .frame(
                    width: item.rank <= 3 ? 28 : 22,
                    height: item.rank <= 3 ? 24 : 20
                )
                .background(rankBadgeBackground)
        }
    }

    private var rankBadgeBackground: some View {
        LinearGradient(
            colors: [
                rankBadgeColor,
                rankBadgeColor.opacity(0.45)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: DB.posterRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        )
    }

    @ViewBuilder
    private var cardBackground: some View {
        if item.rank <= 3 {
            LinearGradient(
                colors: theme.topRankGradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            theme.regularCardColor
        }
    }

    private var rankBadgeColor: Color {
        switch item.rank {
        case 1:
            return DB.logoRed.opacity(0.9)
        case 2:
            return Color(hex: "#D97735").opacity(0.9)
        case 3:
            return Color(hex: "#B8923E").opacity(0.9)
        default:
            return .black.opacity(0.5)
        }
    }
}
