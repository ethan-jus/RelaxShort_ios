import SwiftUI

// MARK: - Banner Carousel (v2)
/// 自动轮播 Banner + 品牌色角标 + 大标题叠加
/// ViewModel 管理轮播索引和自动播放 Timer
struct BannerCarouselView: View {
    let banners: [BannerItem]
    @StateObject private var viewModel = BannerCarouselViewModel()

    var body: some View {
        TabView(selection: $viewModel.currentIndex) {
            ForEach(Array(banners.enumerated()), id: \.element.id) { index, banner in
                BannerCardView(banner: banner)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 185)
        .cornerRadius(DT.Radius.lg)
        .padding(.horizontal, DT.Space.pageH)
        .onAppear {
            viewModel.startAutoScroll(itemCount: banners.count)
        }
        .onDisappear {
            viewModel.stopAutoScroll()
        }
    }
}

// MARK: - Banner Card (v2)
/// 效果代码对齐版：
/// - 背景图片填满
/// - 底部 → 中心渐变遮罩
/// - 左下角品牌色角标 "你正在追"
/// - 左下角大标题
struct BannerCardView: View {
    let banner: BannerItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Cover image
            BannerCoverImage(url: banner.imageName)
                .frame(height: 185)
                .frame(maxWidth: .infinity)
                .clipped()

            // Gradient mask: bottom → center
            LinearGradient(
                colors: [Color.black.opacity(0.5), .clear],
                startPoint: .bottom,
                endPoint: .center
            )

            // Text overlay: tag + title
            VStack(alignment: .leading, spacing: DT.Space.md) {
                // Brand tag "你正在追"
                Text(L10n.youAreWatching)
                    .font(DT.Font.small)
                    .foregroundColor(DT.Color.textPrimary)
                    .padding(.horizontal, DT.Space.sm)
                    .padding(.vertical, DT.Space.xs)
                    .background(DT.brandPink)
                    .cornerRadius(DT.Radius.sm)

                // Title
                Text(banner.title)
                    .foregroundColor(DT.Color.textPrimary)
                    .font(DT.Font.largeTitle)
            }
            .padding(DT.Space.lg)
        }
        .frame(height: 185)
        .cornerRadius(DT.Radius.lg)
    }
}
