import SwiftUI

// MARK: - Right Action Bar

/// 右侧操作按钮栏 — 收藏/分享，半透明圆形背景
/// RecommendView 和 SeriesPlayerView 共用
struct RightActionBar: View {
    @Binding var isBookmarked: Bool
    let viewCount: String?
    var onBookmark: () -> Void
    var onShare: () -> Void
    var onEpisodes: (() -> Void)?

    var body: some View {
        VStack(spacing: 26) {
            // 收藏
            VStack(spacing: 4) {
                Button(action: onBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(isBookmarked ? DB.logoRed : .white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.black.opacity(0.18)))
                }

                Text("Save")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }

            // 选集（仅剧集播放页）
            if let onEpisodes = onEpisodes {
                VStack(spacing: 4) {
                    Button(action: onEpisodes) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.black.opacity(0.18)))
                    }

                    Text(L10n.tabEpisodes)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            // 分享
            VStack(spacing: 4) {
                Button(action: onShare) {
                    Image(systemName: "arrowshape.turn.up.forward")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.black.opacity(0.18)))
                }

                Text("Share")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}
