import SwiftUI
import UIKit

private enum ShareMetrics {
    static let detentHeight: CGFloat = 390
    static let cornerRadius: CGFloat = 26
}

extension View {
    func shareSheetPresentationStyle() -> some View {
        presentationDetents([.height(ShareMetrics.detentHeight)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(ShareMetrics.cornerRadius)
    }
}

struct RewardDeepLink {
    let seriesID: String
    let episodeNumber: Int?

    static func dramaURL(seriesID: String, episodeNumber: Int?) -> URL {
        var components = URLComponents()
        components.scheme = "relaxshort"
        components.host = "series"
        components.path = "/\(seriesID)"
        if let episodeNumber {
            components.queryItems = [
                URLQueryItem(name: "episode", value: String(episodeNumber))
            ]
        }
        return components.url!
    }

    static func inviteURL(code: String) -> URL {
        var components = URLComponents()
        components.scheme = "relaxshort"
        components.host = "invite"
        components.path = "/\(code)"
        return components.url!
    }

    static func parse(_ url: URL) -> RewardDeepLink? {
        guard url.scheme?.lowercased() == "relaxshort",
              url.host?.lowercased() == "series" else {
            return nil
        }
        let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !id.isEmpty else { return nil }
        let episode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "episode" })?.value
            .flatMap(Int.init)
        return RewardDeepLink(seriesID: id, episodeNumber: episode)
    }

    static func parseInviteCode(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "relaxshort",
              url.host?.lowercased() == "invite" else {
            return nil
        }
        let code = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return code.isEmpty ? nil : code.uppercased()
    }
}

struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var rewardSummaryStore: RewardSummaryStore

    let dramaTitle: String
    let seriesID: String
    var episodeNumber: Int? = nil

    @State private var activityItems: [Any]?
    @State private var statusText: String?

    private let repository: CoinRewardRepositoryProtocol = RealCoinRewardRepository()

    private var shareURL: URL {
        RewardDeepLink.dramaURL(
            seriesID: seriesID,
            episodeNumber: episodeNumber
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Color.clear.frame(width: 40, height: 40)
                Spacer()
                Text("分享短剧")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)

            HStack(spacing: 10) {
                RewardCoinBadge(size: 28, motion: .bounce)
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日首次成功分享 +20 金币")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("取消、复制链接或保存到本地不计入奖励")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.46))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 68)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 22)
            .padding(.top, 18)

            Button {
                activityItems = [
                    "正在看《\(dramaTitle)》，点开直接续看：",
                    shareURL
                ]
            } label: {
                Label("选择好友或应用分享", systemImage: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(DT.logoRed)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)

            Button {
                UIPasteboard.general.url = shareURL
                statusText = "链接已复制"
            } label: {
                Label("复制链接", systemImage: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            if let statusText {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.52))
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "#1C1C1E"))
        .sheet(isPresented: Binding(
            get: { activityItems != nil },
            set: { if !$0 { activityItems = nil } }
        )) {
            if let activityItems {
                SystemActivitySheet(items: activityItems) { type, completed in
                    self.activityItems = nil
                    guard completed, let type, isRewardable(type) else { return }
                    Task {
                        do {
                            let state = try await repository.recordShare(
                                seriesID: seriesID,
                                episodeID: nil,
                                channel: type.rawValue,
                                idempotencyKey: "ios-share-\(UUID().uuidString)"
                            )
                            rewardSummaryStore.apply(state)
                            await MainActor.run {
                                statusText = "分享成功，奖励已自动到账"
                            }
                        } catch {
                            await MainActor.run {
                                statusText = "分享已完成，奖励状态稍后刷新"
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func isRewardable(_ type: UIActivity.ActivityType) -> Bool {
        ![
            .copyToPasteboard,
            .saveToCameraRoll,
            .print,
            .addToReadingList
        ].contains(type)
    }
}

struct SystemActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let completion: (UIActivity.ActivityType?, Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { type, completed, _, _ in
            completion(type, completed)
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

#if DEBUG
#Preview("Share Sheet") {
    ShareSheet(
        dramaTitle: "Mafia's Good Girl",
        seriesID: "1001",
        episodeNumber: 1
    )
    .environmentObject(RewardSummaryStore(repository: MockCoinRewardRepository()))
    .preferredColorScheme(.dark)
}
#endif
