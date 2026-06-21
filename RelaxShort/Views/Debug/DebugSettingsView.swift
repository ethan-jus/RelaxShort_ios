import SwiftUI

// MARK: - Debug Settings View (DEBUG only)

#if DEBUG
/// 开发/调试面板：查看和修改 Real API 设置，运行冒烟测试。
/// 仅 DEBUG 构建可用，Release 不包含此文件。
struct DebugSettingsView: View {
    @State private var useRealAPI = UserDefaults.standard.bool(forKey: "use_real_api")
    @State private var apiBaseURL = UserDefaults.standard.string(forKey: "api_base_url") ?? ""
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
                Section("API Mode") {
                    Toggle("Use Real API", isOn: $useRealAPI)
                        .onChange(of: useRealAPI) { _, v in
                            UserDefaults.standard.set(v, forKey: "use_real_api")
                        }
                    HStack {
                        Text("Base URL")
                        TextField("http://127.0.0.1:8080", text: $apiBaseURL)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onSubmit {
                                UserDefaults.standard.set(apiBaseURL, forKey: "api_base_url")
                                effectiveBaseURL = APIConfig.baseURL
                            }
                    }
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
                    Button("Save Settings") {
                        UserDefaults.standard.set(useRealAPI, forKey: "use_real_api")
                        if !apiBaseURL.isEmpty {
                            UserDefaults.standard.set(apiBaseURL, forKey: "api_base_url")
                        }
                        effectiveBaseURL = APIConfig.baseURL
                        refreshContext()
                    }

                    Button("Reset to Mock") {
                        UserDefaults.standard.set(false, forKey: "use_real_api")
                        UserDefaults.standard.removeObject(forKey: "api_base_url")
                        useRealAPI = false
                        apiBaseURL = ""
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
