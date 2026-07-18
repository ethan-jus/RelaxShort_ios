import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

// MARK: - Debug Settings View (DEBUG only)

#if DEBUG
/// 开发/调试面板：查看和修改 Real API 设置，运行冒烟测试。
/// 仅 DEBUG 构建可用，Release 不包含此文件。
struct DebugSettingsView: View {
    @State private var apiBaseURL = UserDefaults.standard.string(forKey: "api_base_url") ?? ""
    @State private var manualOverrideEnabled = UserDefaults.standard.bool(forKey: APIConfig.manualOverrideEnabledKey)
    @State private var effectiveBaseURL = APIConfig.baseURL
    @State private var uiLanguage = UserDefaults.standard.string(forKey: "app_ui_language") ?? "-"
    @State private var contentLanguage = UserDefaults.standard.string(forKey: "app_content_language") ?? "-"
    @State private var countryCode = UserDefaults.standard.string(forKey: "app_country_code") ?? "-"
    @State private var matchedLanguage = UserDefaults.standard.string(forKey: "app_matched_language") ?? "-"
    @State private var fallbackReason = UserDefaults.standard.string(forKey: "app_fallback_reason") ?? "-"
    @State private var adapterDiagnostics: [AdAdapterDiagnostic] = []
    @State private var attStatus = "-"
    @State private var canRequestAds = false
    @State private var privacyOptionsStatus = "-"
    @State private var isPresentingAdInspector = false
    @State private var adInspectorErrorMessage: String?

    @StateObject private var smokeRunner = RealAPISmokeRunner()

    var body: some View {
        NavigationView {
            Form {
                Section("API Config") {
                    Toggle("手动覆盖 Base URL", isOn: $manualOverrideEnabled)
                        .onChange(of: manualOverrideEnabled) { _, enabled in
                            UserDefaults.standard.set(enabled, forKey: APIConfig.manualOverrideEnabledKey)
                            effectiveBaseURL = APIConfig.baseURL
                        }
                    HStack {
                        Text("Base URL")
                        TextField("http://127.0.0.1:8080", text: $apiBaseURL)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .disabled(!manualOverrideEnabled)
                            .onSubmit {
                                UserDefaults.standard.set(apiBaseURL, forKey: "api_base_url")
                                UserDefaults.standard.set(true, forKey: APIConfig.manualOverrideEnabledKey)
                                manualOverrideEnabled = true
                                effectiveBaseURL = APIConfig.baseURL
                            }
                    }
                    Text("自动地址: \(APIConfig.automaticBaseURL)")
                        .font(.caption).foregroundColor(.secondary)
                    Text("关闭手动覆盖后，Debug 每次构建会自动使用 Mac 当前局域网地址。")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("Effective: \(effectiveBaseURL)")
                        .font(.caption).foregroundColor(.secondary)
                }

                Section("App Init Context") {
                    LabeledContent("UI Language", value: uiLanguage)
                    LabeledContent("Content Language", value: contentLanguage)
                    LabeledContent("Country", value: countryCode)
                    LabeledContent("Matched", value: matchedLanguage)
                    LabeledContent("Fallback", value: fallbackReason)
                }

                Section("Ad Diagnostics") {
                    LabeledContent("ATT", value: attStatus)
                    LabeledContent("UMP Ad Requests", value: canRequestAds ? "Allowed" : "Blocked")
                    LabeledContent("Privacy Options", value: privacyOptionsStatus)

                    if adapterDiagnostics.isEmpty {
                        Text("No adapter status. Mobile Ads may not be initialized yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(adapterDiagnostics) { diagnostic in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(diagnostic.isReady ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(diagnostic.displayName)
                                        .font(.caption)
                                        .bold()
                                    Text(diagnostic.className)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("\(diagnostic.detail) · \(diagnostic.latency, specifier: "%.3f")s")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Button("Refresh Ad Status") {
                        refreshAdDiagnostics()
                    }

                    Button {
                        presentAdInspector()
                    } label: {
                        if isPresentingAdInspector {
                            HStack {
                                ProgressView()
                                Text("Opening Ad Inspector...")
                            }
                        } else {
                            Text("Open Ad Inspector")
                        }
                    }
                    .disabled(isPresentingAdInspector)

                    Text("Ad Inspector requires this device to be registered as a test device.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section("Actions") {
                    Button("Save Base URL") {
                        if manualOverrideEnabled && !apiBaseURL.isEmpty {
                            UserDefaults.standard.set(apiBaseURL, forKey: "api_base_url")
                            UserDefaults.standard.set(true, forKey: APIConfig.manualOverrideEnabledKey)
                        } else {
                            UserDefaults.standard.removeObject(forKey: "api_base_url")
                            UserDefaults.standard.set(false, forKey: APIConfig.manualOverrideEnabledKey)
                            manualOverrideEnabled = false
                        }
                        effectiveBaseURL = APIConfig.baseURL
                        refreshContext()
                    }

                    Button("Run App Init") {
                        Task { await AppInitService.shared.initialize() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { refreshContext() }
                    }
                    .disabled(smokeRunner.isRunning)

                    Button("Run API Smoke Test") {
                        Task { await smokeRunner.run() }
                    }
                    .disabled(smokeRunner.isRunning)
                }

                if !smokeRunner.results.isEmpty {
                    Section("Smoke Results") {
                        if smokeRunner.isRunning {
                            HStack {
                                ProgressView()
                                Text("Running: \(smokeRunner.currentStep)...")
                                    .font(.caption)
                            }
                        }
                        ForEach(smokeRunner.results) { r in
                            HStack {
                                Circle().fill(r.status == .success ? Color.green : (r.status == .failure ? Color.red : Color.yellow))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.step).font(.caption).bold()
                                    Text(r.endpoint).font(.caption2).foregroundColor(.secondary)
                                    Text(r.summary).font(.caption2)
                                    if let err = r.errorMessage {
                                        Text(err).font(.caption2).foregroundColor(.red)
                                    }
                                }
                                Spacer()
                                Text("\(r.durationMs)ms").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Debug Settings")
        }
        .onAppear { refreshContext() }
        .alert(
            "广告诊断",
            isPresented: Binding(
                get: { adInspectorErrorMessage != nil },
                set: { if !$0 { adInspectorErrorMessage = nil } }
            )
        ) {
            Button("确定", role: .cancel) {
                adInspectorErrorMessage = nil
            }
        } message: {
            Text(adInspectorErrorMessage ?? "")
        }
    }

    private func refreshContext() {
        uiLanguage = UserDefaults.standard.string(forKey: "app_ui_language") ?? "-"
        contentLanguage = UserDefaults.standard.string(forKey: "app_content_language") ?? "-"
        countryCode = UserDefaults.standard.string(forKey: "app_country_code") ?? "-"
        matchedLanguage = UserDefaults.standard.string(forKey: "app_matched_language") ?? "-"
        fallbackReason = UserDefaults.standard.string(forKey: "app_fallback_reason") ?? "-"
        refreshAdDiagnostics()
    }

    private func refreshAdDiagnostics() {
        attStatus = Self.attStatusDescription
        canRequestAds = UMPConsentInformation.sharedInstance.canRequestAds
        privacyOptionsStatus = Self.privacyOptionsStatusDescription
        adapterDiagnostics = MobileAds.shared.initializationStatus.adapterStatusesByClassName
            .map { className, status in
                AdAdapterDiagnostic(
                    className: className,
                    displayName: Self.adapterDisplayName(for: className),
                    isReady: status.state == .ready,
                    detail: status.description,
                    latency: status.latency
                )
            }
            .sorted {
                if $0.displayName == $1.displayName {
                    return $0.className < $1.className
                }
                return $0.displayName < $1.displayName
            }
    }

    private func presentAdInspector() {
        guard let viewController = Self.topViewController() else {
            adInspectorErrorMessage = "无法找到可用于展示 Ad Inspector 的页面。"
            return
        }

        isPresentingAdInspector = true
        MobileAds.shared.presentAdInspector(from: viewController) { error in
            Task { @MainActor in
                isPresentingAdInspector = false
                if let error {
                    adInspectorErrorMessage = "Ad Inspector 无法打开：\(error.localizedDescription)"
                }
                refreshAdDiagnostics()
            }
        }
    }

    private static var attStatusDescription: String {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .notDetermined:
            return "Not Requested"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }

    private static var privacyOptionsStatusDescription: String {
        switch UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus {
        case .unknown:
            return "Unknown"
        case .required:
            return "Required"
        case .notRequired:
            return "Not Required"
        @unknown default:
            return "Unknown"
        }
    }

    private static func adapterDisplayName(for className: String) -> String {
        let lowercaseName = className.lowercased()
        if lowercaseName.contains("pangle") {
            return "Pangle"
        }
        if lowercaseName.contains("meta") || lowercaseName.contains("facebook") {
            return "Meta"
        }
        if lowercaseName.contains("google") || lowercaseName.contains("admob") {
            return "Google"
        }
        return className
    }

    private static func topViewController(from suppliedRoot: UIViewController? = nil) -> UIViewController? {
        let root = suppliedRoot ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}

private struct AdAdapterDiagnostic: Identifiable {
    var id: String { className }

    let className: String
    let displayName: String
    let isReady: Bool
    let detail: String
    let latency: TimeInterval
}

#if DEBUG
#Preview("Debug Settings") {
    DebugSettingsView()
}
#endif
#endif
