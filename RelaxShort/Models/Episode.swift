import Foundation

/// 剧集模型 — 对应短剧中每一集视频内容
struct Episode: Codable, Identifiable {
    /// 剧集唯一标识
    let id: String
    /// 所属短剧 ID
    let dramaId: String
    /// 集数序号（从 1 开始）
    let episodeNumber: Int
    /// 剧集标题
    let title: String
    /// 视频播放 URL（Task13 R3: 改为 var，支持播放页通过 episodePlay 接口更新）
    var videoURL: String
    /// 视频时长（秒）
    let duration: TimeInterval
    /// 是否锁定（需付费/VIP 解锁）
    let isLocked: Bool
    /// 解锁所需金币数 (v1 DramaBox 复刻)
    var unlockCoinPrice: Int? = nil

    // MARK: - Computed Properties
    
    /// 格式化时长显示，如 "03:25"
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// 解锁条件描述
    var lockDescription: String {
        isLocked ? "需解锁观看" : "免费观看"
    }
}
