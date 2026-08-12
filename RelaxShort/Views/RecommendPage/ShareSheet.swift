import SwiftUI
import UIKit

private enum ShareMetrics {
    static let detentHeight: CGFloat = 374
    static let cornerRadius: CGFloat = 24
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
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 42, height: 5)
                .padding(.top, 10)

            HStack {
                Text("share.title".localized)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white.opacity(0.66))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.055), in: Circle())
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, 7)

            HStack(spacing: 10) {
                RewardCoinBadge(size: 28, motion: .bounce)
                VStack(alignment: .leading, spacing: 3) {
                    Text("share.daily_reward".localized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("share.reward_exclusions".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.46))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 84)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Button {
                activityItems = [
                    "share.message".localizedFormat(dramaTitle),
                    shareURL
                ]
            } label: {
                Label("share.choose_app".localized, systemImage: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(DT.logoRed)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Button {
                UIPasteboard.general.url = shareURL
                statusText = "share.link_copied".localized
            } label: {
                Label("player.copy_link".localized, systemImage: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            if let statusText {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.52))
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "#111111"))
        .presentationBackground(Color(hex: "#111111"))
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
                                statusText = "share.reward_received".localized
                            }
                        } catch {
                            await MainActor.run {
                                statusText = "share.reward_pending".localized
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
