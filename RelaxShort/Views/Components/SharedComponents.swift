import SwiftUI

// MARK: - Cover Image View
/// 封面图片异步加载组件，使用项目共享 ImageLoader 内存缓存
///
/// 加载中/失败均显示暗黑骨架占位，避免慢网或坏图时出现突兀色块。
///
/// 使用示例：
/// ```swift
/// CoverImageView(url: drama.coverURL)           // 2:3 竖版海报
/// CoverImageView(url: banner.imageName, aspectRatio: 16/9, cornerRadius: DT.Radius.lg)
/// ```
struct CoverImageView: View {
    let url: String
    var aspectRatio: CGFloat = DT.Layout.cardAspectRatio // 默认 2:3 竖版
    var cornerRadius: CGFloat = DB.posterRadius
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    @StateObject private var imageLoader = ImageLoader()

    var body: some View {
        ZStack {
            placeholderGradient

            if imageLoader.imageKey == url, let image = imageLoader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            }
        }
        .applySize(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            await imageLoader.load(url)
        }
    }
    
    /// 渐变占位背景
    private var placeholderGradient: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [DT.Color.bgCoverPlaceholderAltStart, DT.Color.bgCoverPlaceholderAltEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

// MARK: - Size Application Helper
private extension View {
    @ViewBuilder
    func applySize(width: CGFloat?, height: CGFloat?) -> some View {
        if let w = width, let h = height {
            self.frame(width: w, height: h)
        } else if let w = width {
            self.frame(width: w)
        } else if let h = height {
            self.frame(height: h)
        } else {
            self
        }
    }
}

// MARK: - Cover Image View for Banner
/// Banner 专用封面组件 — 16:9 比例，大圆角
struct BannerCoverImage: View {
    let url: String
    
    var body: some View {
        CoverImageView(
            url: url,
            aspectRatio: DT.Layout.bannerAspectRatio,
            cornerRadius: DT.Radius.lg
        )
    }
}

// MARK: - Continue Watching Section
struct ContinueWatchingSection: View {
    let dramas: [DramaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack {
                Text(L10n.youAreWatching)
                    .font(DT.Font.subtitle)
                    .foregroundColor(DT.Color.textPrimary)

                Spacer()

                Button(L10n.viewAll) {}
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
            }
            .padding(.horizontal, DT.Space.pageH)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Space.md) {
                    ForEach(dramas) { drama in
                        VStack(alignment: .leading, spacing: DT.Space.xs) {
                            ZStack(alignment: .bottom) {
                                CoverImageView(
                                    url: drama.coverURL,
                                    aspectRatio: DT.Layout.cardAspectRatio,
                                    cornerRadius: DB.posterRadius,
                                    width: 100,
                                    height: 140
                                )

                                if let progress = drama.progressPercentage {
                                    GeometryReader { geo in
                                        Rectangle()
                                            .fill(DT.brandPink)
                                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                                    }
                                    .frame(height: 3)
                                }
                            }

                            Text(drama.title)
                                .font(DT.Font.caption)
                                .fontWeight(.medium)
                                .foregroundColor(DT.Color.textPrimary)
                                .frame(width: 100)
                                .lineLimit(1)

                            Text("\(drama.currentEpisode)/\(drama.episodeCount)\(L10n.shortEpisodeCount)")
                                .font(DT.Font.small)
                                .foregroundColor(DT.Color.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
            }
        }
    }
}

// MARK: - Section Header
struct SectionHeaderView: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            // Decorative left bar
            Rectangle()
                .fill(DT.brandPink)
                .frame(width: 3, height: 16)
                .cornerRadius(1.5)

            Text(title)
                .font(DT.Font.sectionTitle)
                .foregroundColor(DT.Color.textPrimary)

            Spacer()

            Button(action: action) {
                HStack(spacing: 2) {
                    Text(L10n.more)
                        .font(DT.Font.caption)
                    Image(systemName: "chevron.right")
                        .font(DT.Font.small)
                }
                .foregroundColor(DT.Color.textSecondary)
            }
        }
    }
}

// MARK: - Ranking List View
struct RankingListView: View {
    let dramas: [DramaItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(dramas.enumerated()), id: \.element.id) { index, drama in
                RankingRow(index: index + 1, drama: drama)
            }
        }
    }
}

// MARK: - Ranking Row
struct RankingRow: View {
    let index: Int
    let drama: DramaItem

    private var rankColor: SwiftUI.Color {
        index <= 3 ? DT.brandGold : DT.Color.textSecondary
    }

    private var rankWeight: SwiftUI.Font.Weight {
        index <= 3 ? .heavy : .bold
    }

    var body: some View {
        HStack(spacing: DT.Space.md) {
            // Rank number
            Text("\(index)")
                .font(DT.Font.body(20, weight: rankWeight))
                .foregroundColor(rankColor)
                .frame(width: 32)

            // Cover
            CoverImageView(
                url: drama.coverURL,
                aspectRatio: DT.Layout.cardAspectRatio,
                cornerRadius: DB.posterRadius,
                width: 60,
                height: 80
            )

            // Info
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(drama.title)
                    .font(DT.Font.body(14))
                    .fontWeight(.semibold)
                    .foregroundColor(DT.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DT.Space.xs) {
                    ForEach(drama.tags, id: \.self) { tag in
                        Text(tag)
                            .font(DT.Font.small)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DT.Color.bgCard)
                            .cornerRadius(3)
                            .foregroundColor(DT.Color.textSecondary)
                    }
                }

                HStack(spacing: DT.Space.sm) {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill")
                            .font(DT.Font.small)
                        Text(drama.formattedViewCount)
                            .font(DT.Font.small)
                    }
                    .foregroundColor(DT.Color.textSecondary)

                    Text("\(L10n.totalEpisodesPrefix)\(drama.episodeCount)\(L10n.shortEpisodeCount)")
                        .font(DT.Font.small)
                        .foregroundColor(DT.Color.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(DT.Font.tabLabel)
                .foregroundColor(DT.Color.textTertiary)
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.vertical, DT.Space.sm)
        .contentShape(Rectangle())
    }
}

// MARK: - Badge Tag View (Task20: shared badge rendering)

/// Renders a single badge tag for player / recommend card overlays.
/// Uses feed-style styling with configurable foreground/background colors.
struct DramaBadgeTagView: View {
    let tag: L10n.BadgeTag
    let drama: DramaItem

    var body: some View {
        switch tag {
        case .vip:
            feedTag(L10n.badgeTagLabel(.vip), bg: .goldVipBadgeBg, fg: .goldVipBadgeFg)
        case .hot:
            feedTag(L10n.badgeTagLabel(.hot), bg: .white.opacity(0.12), fg: .white.opacity(0.85))
        case .trending:
            feedTag(L10n.badgeTagLabel(.trending), bg: .white.opacity(0.12), fg: .white.opacity(0.85))
        case .new:
            feedTag(L10n.badgeTagLabel(.new), bg: .white.opacity(0.12), fg: .white.opacity(0.85))
        case .category:
            let cat = L10n.categoryDisplayName(drama.category)
            if !cat.isEmpty {
                feedTag(cat, bg: .white.opacity(0.12), fg: .white.opacity(0.85))
            }
        }
    }

    private func feedTag(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private extension Color {
    static let goldVipBadgeBg = Color(red: 0.85, green: 0.72, blue: 0.38).opacity(0.25)
    static let goldVipBadgeFg = Color(red: 0.85, green: 0.72, blue: 0.38)
}
