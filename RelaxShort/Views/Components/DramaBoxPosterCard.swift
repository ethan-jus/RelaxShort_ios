import SwiftUI

// MARK: - DramaBox Poster Card

/// DramaBox 风格剧集海报卡 — 竖版 2:3 + 角标 + 进度条
/// 可点击不小于 44pt
struct DramaBoxPosterCard: View {
    let drama: DramaItem
    var width: CGFloat = DB.posterWidth
    var showProgress: Bool = false
    var onTap: (() -> Void)? = nil

    private var height: CGFloat { width * 3 / 2 }

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Poster image
                ZStack(alignment: .topLeading) {
                    CoverImageView(
                        url: drama.coverURL,
                        aspectRatio: 2.0 / 3.0,
                        cornerRadius: DB.posterRadius,
                        width: width,
                        height: height
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))

                    // Badge overlay
                    if let badge = drama.badge {
                        badgeView(for: badge)
                            .padding(4)
                    }
                }
                .frame(width: width, height: height)

                // Progress bar
                if showProgress, let progress = drama.progressPercentage {
                    progressBar(progress: progress)
                        .frame(width: width)
                }

                // Title
                Text(drama.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)

                // Subtitle (category + episodes)
                HStack(spacing: 4) {
                    Text(drama.category)
                        .font(.system(size: 11))
                        .foregroundColor(DB.mutedText)
                    Text("·")
                        .foregroundColor(DB.mutedText)
                    Text("\(drama.episodeCount) EP")
                        .font(.system(size: 11))
                        .foregroundColor(DB.mutedText)
                }
                .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44)
    }

    @ViewBuilder
    private func badgeView(for badge: BadgeType) -> some View {
        switch badge {
        case .hot:
            Text("HOT")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DB.pink)
                .cornerRadius(DB.ctaRadius)
        case .new:
            Text("NEW")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue)
                .cornerRadius(DB.ctaRadius)
        case .vip:
            HStack(spacing: 2) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 7))
                Text("VIP")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DB.gold)
            .cornerRadius(DB.ctaRadius)
        }
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DB.divider)
                    .frame(height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(DB.pink)
                    .frame(width: geo.size.width * CGFloat(progress), height: 2)
            }
        }
        .frame(height: 2)
    }
}

#if DEBUG
struct DramaBoxPosterCard_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            DramaBoxPosterCard(drama: DramaItem(
                id: "1", title: "江南时节", coverURL: "",
                category: "现代言情", tags: [], viewCount: 5_500_000,
                episodeCount: 53, currentEpisode: 18,
                synopsis: "test", isHot: true, isTrending: false,
                rating: 9.1, badge: .hot
            ))
            DramaBoxPosterCard(drama: DramaItem(
                id: "2", title: "好一个乖乖女", coverURL: "",
                category: "总裁", tags: [], viewCount: 1_600_000,
                episodeCount: 70, currentEpisode: 35,
                synopsis: "test", isHot: true, isTrending: false,
                rating: 9.5, badge: .vip
            ), showProgress: true)
        }
        .padding()
        .background(DB.black)
        .preferredColorScheme(.dark)
    }
}
#endif
