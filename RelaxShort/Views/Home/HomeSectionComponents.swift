import SwiftUI

private enum HomeSectionLayout {
    static let railSpacing: CGFloat = 10
    static let posterTitleHeight: CGFloat = 34
    static let posterMetaHeight: CGFloat = 16
    static let heroAutoAdvanceSeconds: UInt64 = 5
}

struct HomeCardBadgeView: View {
    let badge: PlacementBadge

    var body: some View {
        Text(badge.label)
            .font(.system(size: 10, weight: badge.code == "members_only" ? .medium : .semibold))
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: DB.posterRadius,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: DB.posterRadius
                )
            )
    }

    private var backgroundColor: Color {
        switch badge.tone {
        case .brand: return DB.logoRed
        case .violet: return Color(red: 0.43, green: 0.35, blue: 0.72)
        case .gold: return Color(red: 0.93, green: 0.82, blue: 0.60)
        case .neutral: return Color.black.opacity(0.68)
        }
    }

    private var foregroundColor: Color {
        badge.tone == .gold ? Color(red: 0.33, green: 0.22, blue: 0.08) : .white
    }
}

struct HomeHeroCarouselSection: View {
    let dramas: [DramaItem]
    @Binding var playerDrama: DramaItem?
    var containerW: CGFloat
    @State private var currentIndex = 0

    var body: some View {
        let horizontalPadding = DT.Space.pageH
        let w = containerW - horizontalPadding * 2
        let h = w * 0.5

        Button { playerDrama = dramas[safe: currentIndex] } label: {
            ZStack(alignment: .bottomLeading) {
                ZStack(alignment: .bottomTrailing) {
                    ForEach(Array(dramas.enumerated()), id: \.element.id) { index, drama in
                        CoverImageView(
                            url: drama.bannerCoverURL ?? drama.coverURL,
                            aspectRatio: w / h,
                            cornerRadius: DB.posterRadius,
                            width: w,
                            height: h
                        )
                        .opacity(index == currentIndex ? 1 : 0)
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: DB.posterRadius))
                    heroRailIndicator(count: dramas.count, currentIndex: currentIndex)
                        .padding(.bottom, 7)
                        .padding(.trailing, 14)
                }
                if let current = dramas[safe: currentIndex] {
                    Text(current.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(12)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, horizontalPadding)
        .task(id: dramas.map(\.id).joined(separator: "|")) {
            guard dramas.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: HomeSectionLayout.heroAutoAdvanceSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentIndex = (currentIndex + 1) % dramas.count
                }
            }
        }
        .onChange(of: dramas.map(\.id)) { _, _ in
            currentIndex = 0
        }
    }

    private func heroRailIndicator(count: Int, currentIndex: Int) -> some View {
        GeometryReader { geo in
            let clampedCount = max(count, 1)
            let segmentWidth = geo.size.width / CGFloat(clampedCount)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: segmentWidth, height: 4)
                    .offset(x: segmentWidth * CGFloat(min(currentIndex, clampedCount - 1)))
            }
        }
        .frame(width: min(containerW * 0.15, 64), height: 10)
    }
}

struct HomePosterRailSection: View {
    let title: String
    let dramas: [DramaItem]
    @Binding var playerDrama: DramaItem?
    var containerW: CGFloat

    var body: some View {
        let cardW = min(max(containerW * 0.3, 108), 140)
        let coverH = cardW * 1.5
        let itemH = coverH + HomeSectionLayout.posterTitleHeight + HomeSectionLayout.posterMetaHeight + 8

        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, DT.Space.pageH)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: HomeSectionLayout.railSpacing) {
                    ForEach(dramas) { drama in
                        Button { playerDrama = drama } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    CoverImageView(
                                        url: drama.coverURL,
                                        aspectRatio: 2.0 / 3.0,
                                        cornerRadius: DB.posterRadius,
                                        width: cardW,
                                        height: coverH
                                    )
                                    if let badge = drama.placementBadge {
                                        HomeCardBadgeView(badge: badge)
                                    }
                                }
                                Text(drama.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .frame(width: cardW, height: HomeSectionLayout.posterTitleHeight, alignment: .topLeading)
                                Text(drama.category)
                                    .font(.system(size: 11))
                                    .foregroundColor(DB.mutedText)
                                    .lineLimit(1)
                                    .frame(width: cardW, height: HomeSectionLayout.posterMetaHeight, alignment: .topLeading)
                            }
                            .frame(width: cardW, height: itemH, alignment: .top)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
            }
        }
    }
}

struct HomeDramaListSection: View {
    let title: String
    let dramas: [DramaItem]
    @Binding var playerDrama: DramaItem?
    var containerW: CGFloat

    var body: some View {
        let coverW = min(max(containerW * 0.27, 104), 116)
        let coverH = coverW * 1.5

        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, DT.Space.pageH)
            LazyVStack(spacing: 18) {
                ForEach(dramas) { drama in
                    Button { playerDrama = drama } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack(alignment: .topTrailing) {
                                CoverImageView(
                                    url: drama.coverURL,
                                    aspectRatio: 2.0 / 3.0,
                                    cornerRadius: DB.posterRadius,
                                    width: coverW,
                                    height: coverH
                                )
                                if let badge = drama.placementBadge {
                                    HomeCardBadgeView(badge: badge)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(drama.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                if !drama.synopsis.isEmpty {
                                    Text(drama.synopsis)
                                        .font(.system(size: 13))
                                        .foregroundColor(DB.mutedText)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 8) {
                                    Text(drama.category)
                                        .font(.system(size: 12))
                                        .foregroundColor(DB.mutedText)
                                    Text("\(drama.episodeCount) EP")
                                        .font(.system(size: 12))
                                        .foregroundColor(DB.mutedText)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DT.Space.pageH)
        }
    }
}
