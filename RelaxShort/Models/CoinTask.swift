import Foundation

// MARK: - 赚金币任务模型

/// 福利中心任务项
struct CoinTask: Identifiable {
    let id = UUID()
    /// SF Symbol 图标名
    let iconName: String
    /// 任务标题
    let title: String
    /// 副标题（奖励说明）
    let subtitle: String
    /// 按钮文字
    let buttonText: String
}

/// 签到日数据
struct CheckInDay: Identifiable {
    let id = UUID()
    /// 显示标签（如"今天""第2天"）
    let label: String
    /// 奖励金币数文案
    let coins: String
    /// 是否已签到
    var checked: Bool
}
