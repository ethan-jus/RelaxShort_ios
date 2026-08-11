import SwiftUI
import UIKit

enum AppUpdateMode: String, Codable {
    case optional
    case force
}

struct AppUpdatePresentation: Identifiable, Codable, Equatable {
    var id: String { "\(mode.rawValue)-\(latestVersionCode)" }
    let mode: AppUpdateMode
    let latestVersionCode: Int
    let latestVersionName: String
    let storeURL: String
    let releaseNotes: [String: String]

    var localizedReleaseNotes: String? {
        let current = AppLocalization.currentLanguage.rawValue
        let base = current.split(separator: "-").first.map(String.init)
        return releaseNotes[current]
            ?? base.flatMap { releaseNotes[$0] }
            ?? releaseNotes["en"]
            ?? releaseNotes.values.first
    }
}

/// 服务端版本策略的唯一客户端状态机：强制更新不可关闭，可选更新每个 Build 只提示一次。
@MainActor
final class AppUpdateCoordinator: ObservableObject {
    @Published private(set) var presentation: AppUpdatePresentation?
    @Published private(set) var storeOpenError: String?

    private let defaults: UserDefaults
    private let cachedForceKey = "app_update.cached_force_policy"
    private let dismissedOptionalBuildKey = "app_update.dismissed_optional_build"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreCachedForcePolicy()
    }

    func handle(_ update: UpdateInfoDTO?) {
        guard let update else { return }
        let currentBuild = Self.currentBuildNumber
        let targetBuild = update.latestVersionCode ?? max(currentBuild + 1, 1)
        let targetName = update.latestVersionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storeURL = update.storeUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = update.releaseNotes ?? [:]
        let type = update.updateType?.lowercased()

        let requiresUpdate = update.updateRequired == true || type == "force"
        if requiresUpdate, currentBuild < targetBuild {
            let policy = AppUpdatePresentation(
                mode: .force,
                latestVersionCode: targetBuild,
                latestVersionName: targetName?.isEmpty == false ? targetName! : "\(targetBuild)",
                storeURL: storeURL,
                releaseNotes: notes
            )
            cacheForcePolicy(policy)
            presentation = policy
            storeOpenError = nil
            return
        }

        // 一次成功的服务端结果可以解除本机旧的强制策略。
        clearCachedForcePolicy()
        if presentation?.mode == .force {
            presentation = nil
        }

        let recommendsUpdate = update.updateRecommended == true
            || type == "optional"
            || type == "recommend"
        guard recommendsUpdate,
              currentBuild < targetBuild,
              defaults.integer(forKey: dismissedOptionalBuildKey) != targetBuild else {
            return
        }

        presentation = AppUpdatePresentation(
            mode: .optional,
            latestVersionCode: targetBuild,
            latestVersionName: targetName?.isEmpty == false ? targetName! : "\(targetBuild)",
            storeURL: storeURL,
            releaseNotes: notes
        )
        storeOpenError = nil
    }

    func dismissOptional() {
        guard let presentation, presentation.mode == .optional else { return }
        defaults.set(presentation.latestVersionCode, forKey: dismissedOptionalBuildKey)
        self.presentation = nil
        storeOpenError = nil
    }

    func openStore() {
        guard let presentation,
              let url = URL(string: presentation.storeURL),
              url.scheme?.lowercased() == "https" else {
            storeOpenError = "app.update.store_unavailable".localized
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            Task { @MainActor in
                self?.storeOpenError = opened
                    ? nil
                    : "app.update.store_unavailable".localized
            }
        }
    }

    private func restoreCachedForcePolicy() {
        guard let data = defaults.data(forKey: cachedForceKey),
              let policy = try? JSONDecoder().decode(AppUpdatePresentation.self, from: data),
              policy.mode == .force else { return }
        if Self.currentBuildNumber < policy.latestVersionCode {
            presentation = policy
        } else {
            clearCachedForcePolicy()
        }
    }

    private func cacheForcePolicy(_ policy: AppUpdatePresentation) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        defaults.set(data, forKey: cachedForceKey)
    }

    private func clearCachedForcePolicy() {
        defaults.removeObject(forKey: cachedForceKey)
    }

    static var currentBuildNumber: Int {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Int(raw ?? "") ?? 0
    }
}

/// 品牌化更新门禁。强制模式没有关闭手势；可选模式允许“稍后”。
struct AppUpdatePromptView: View {
    let presentation: AppUpdatePresentation
    @ObservedObject var coordinator: AppUpdateCoordinator

    var body: some View {
        ZStack {
            Color.black.opacity(presentation.mode == .force ? 0.96 : 0.78)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 9) {
                    Text(
                        presentation.mode == .force
                            ? "app.update.force_title".localized
                            : "app.update.optional_title".localized
                    )
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                    Text(
                        (presentation.mode == .force
                            ? "app.update.force_message"
                            : "app.update.optional_message")
                            .localizedFormat(presentation.latestVersionName)
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                }

                if let notes = presentation.localizedReleaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                }

                if let error = coordinator.storeOpenError {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.38))
                        .multilineTextAlignment(.center)
                }

                Button(action: coordinator.openStore) {
                    Text("app.update.now".localized)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DT.logoRed, in: RoundedRectangle(cornerRadius: 12))
                }

                if presentation.mode == .optional {
                    Button(action: coordinator.dismissOptional) {
                        Text("app.update.later".localized)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.64))
                            .frame(height: 36)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 430)
            .background(Color(hex: "#111111"), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.8)
            )
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(true)
        .accessibilityAddTraits(presentation.mode == .force ? .isModal : [])
    }
}
