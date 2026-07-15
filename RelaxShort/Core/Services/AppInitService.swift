import Foundation

// MARK: - App Init Service

/// 启动初始化服务：调用 `POST /api/v2/app/init` 获取语言/内容/广告决策，
/// 保存到 UserDefaults 供后续请求头使用。
/// 超时/失败不阻塞 App 进入主界面。
@MainActor
final class AppInitService {

    static let shared = AppInitService()

    private let client = APIClient.shared
    private let timeoutSeconds: UInt64 = 5

    private init() {}

    /// 已成功初始化标志
    private(set) var didInitialize = false

    /// 调用 app/init，结果写入 UserDefaults。失败时记录日志，不抛异常。
    func initialize() async {
        do {
            let dto: AppInitResponseDTO = try await withTimeout(seconds: timeoutSeconds) {
                try await self.client.requestData(.appInit)
            }
            apply(dto)
            didInitialize = true
            Logger.general.info("AppInitService: initialized ui=\(dto.uiLanguage) content=\(dto.contentLanguage) country=\(dto.countryCode)")
        } catch {
            guard Self.shouldReportFailure(error) else { return }
            Logger.general.warning("AppInitService: init failed (will retry on next launch): \(error.localizedDescription)")
        }
    }

    /// SwiftUI 生命周期或系统主动取消任务属于正常结束，不应伪装成启动失败。
    static func shouldReportFailure(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError, urlError.code == .cancelled { return false }
        return true
    }

    /// 将后端语言决策写入 UserDefaults
    private func apply(_ dto: AppInitResponseDTO) {
        UserDefaults.standard.set(dto.uiLanguage, forKey: "app_ui_language")
        UserDefaults.standard.set(dto.contentLanguage, forKey: "app_content_language")
        UserDefaults.standard.set(dto.countryCode, forKey: "app_country_code")
        if let matched = dto.matchedLanguage {
            UserDefaults.standard.set(matched, forKey: "app_matched_language")
        }
        UserDefaults.standard.set(dto.fallbackReason, forKey: "app_fallback_reason")
    }
}

// MARK: - Timeout Helper

/// 简单超时包装：在限制秒数内未完成则抛错
private func withTimeout<T>(seconds: UInt64, _ operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: LocalizedError {
    var errorDescription: String? { "App init 请求超时" }
}
