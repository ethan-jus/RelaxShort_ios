import Foundation
import os

// MARK: - Logger

/// 统一日志系统 — 基于 os.Logger
/// 替换项目中所有 `print()` 调用，提供分类、级别、隐私保护
///
/// 用法：
/// ```swift
/// Logger.general.info("App launched")
/// Logger.network.error("Request failed: \(error)")
/// Logger.viewModel.warning("Empty data for category: \(category)")
/// ```
enum Logger {
    /// 通用/应用级日志
    static let general = os.Logger(subsystem: "com.relaxshort.app", category: "general")
    /// 网络请求日志
    static let network = os.Logger(subsystem: "com.relaxshort.app", category: "network")
    /// ViewModel 业务逻辑日志
    static let viewModel = os.Logger(subsystem: "com.relaxshort.app", category: "viewModel")
    /// 存储/持久化日志
    static let storage = os.Logger(subsystem: "com.relaxshort.app", category: "storage")
    /// UI 交互日志
    static let ui = os.Logger(subsystem: "com.relaxshort.app", category: "ui")
    /// 认证/登录日志
    static let auth = os.Logger(subsystem: "com.relaxshort.app", category: "auth")
    /// Store/金币/内购日志
    static let store = os.Logger(subsystem: "com.relaxshort.app", category: "store")
    /// 事件分析日志
    static let analytics = os.Logger(subsystem: "com.relaxshort.app", category: "analytics")
    /// 播放引擎和页面播放权日志
    static let player = os.Logger(subsystem: "com.relaxshort.app", category: "player")
}
