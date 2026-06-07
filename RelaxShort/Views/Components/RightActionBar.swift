import SwiftUI

// MARK: - 右侧操作栏

/// 右侧操作按钮栏 — 收藏、选集、分享
/// 推荐页和剧集播放页共用
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
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(isBookmarked ? DB.logoRed : .white)
                        .symbolRenderingMode(.monochrome)
                        .frame(width: 38, height: 36)
                        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)

                Text(viewCount ?? "4.5M")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }

            // 选集（仅剧集播放页）
            if let onEpisodes = onEpisodes {
                VStack(spacing: 4) {
                    Button(action: onEpisodes) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 36)
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)

                    Text(L10n.tabEpisodes)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            // 分享
            VStack(spacing: 4) {
                Button(action: onShare) {
                    Image(systemName: "arrowshape.turn.up.forward.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 36)
                        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)

                Text("Share")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }
}
