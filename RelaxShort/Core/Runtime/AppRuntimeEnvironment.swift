import Foundation

/// 集中判断当前是否在 XCTest 宿主中运行，避免单元测试意外触发真实网络请求。
enum AppRuntimeEnvironment {
    static var isUnitTesting: Bool {
        isUnitTesting(environment: ProcessInfo.processInfo.environment)
    }

    static func isUnitTesting(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
