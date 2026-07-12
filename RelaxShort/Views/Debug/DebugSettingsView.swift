import SwiftUI

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
    }

    private func refreshContext() {
        uiLanguage = UserDefaults.standard.string(forKey: "app_ui_language") ?? "-"
        contentLanguage = UserDefaults.standard.string(forKey: "app_content_language") ?? "-"
        countryCode = UserDefaults.standard.string(forKey: "app_country_code") ?? "-"
        matchedLanguage = UserDefaults.standard.string(forKey: "app_matched_language") ?? "-"
        fallbackReason = UserDefaults.standard.string(forKey: "app_fallback_reason") ?? "-"
    }
}

#if DEBUG
#Preview("Debug Settings") {
    DebugSettingsView()
}
#endif
#endif
