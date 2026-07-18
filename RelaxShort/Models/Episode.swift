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
    /// 当前用户是否通过金币或广告获得了永久解锁权益。
    var isUnlocked: Bool = false
    /// 解锁所需金币数 (v1 DramaBox 复刻)
    var unlockCoinPrice: Int? = nil
    /// VIP 专享集不能通过金币或广告绕过。
    var requiresVIP: Bool = false

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

enum EpisodeUnlockMethod: String, Codable {
    case coins
    case ads
}

struct EpisodeUnlockAccount: Equatable {
    let balance: Int
    let isVIP: Bool
}

struct EpisodeUnlockResult: Equatable {
    let unlocked: Bool
    let balanceAfter: Int?
}

struct ApplePurchaseReceipt: Equatable {
    let transactionID: String
    let productID: String
    let environment: String
    let appAccountToken: String?
    let coins: Int

    /// Xcode StoreKit Configuration 只用于本地开发；Sandbox/Production 必须由后端验单发货。
    var requiresBackendVerification: Bool {
        environment.caseInsensitiveCompare("XCODE") != .orderedSame
    }
}

struct EpisodeUnlockFlowState: Equatable {
    enum Selection: Equatable { case coins, vip }
    enum Presentation: Equatable { case primary, retention, lockedFrame }

    let episodeNumber: Int
    let coinCost: Int
    var balance: Int
    let vipOnly: Bool
    var selection: Selection
    var presentation: Presentation = .primary
    var isProcessing = false
    var errorMessage: String?
    private(set) var hasShownRetention = false

    init(episodeNumber: Int, coinCost: Int, balance: Int, vipOnly: Bool) {
        self.episodeNumber = episodeNumber
        self.coinCost = coinCost
        self.balance = balance
        self.vipOnly = vipOnly
        self.selection = vipOnly || balance < coinCost ? .vip : .coins
    }

    var canUnlockWithCoins: Bool { !vipOnly }
    var canUnlockWithAd: Bool { !vipOnly }
    var coinShortfall: Int { max(0, coinCost - balance) }
    var hasEnoughCoins: Bool { balance >= coinCost }
    var blocksPlaybackInteraction: Bool { true }
    var playbackTargetEpisode: Int { episodeNumber }

    var primaryButtonTitle: String {
        if selection == .vip { return "开通 VIP 并解锁" }
        return hasEnoughCoins ? "使用 \(coinCost) 金币解锁" : "充值并解锁"
    }

    mutating func close() {
        switch presentation {
        case .primary where !hasShownRetention:
            hasShownRetention = true
            presentation = .retention
        case .primary, .retention:
            presentation = .lockedFrame
        case .lockedFrame:
            break
        }
    }

    mutating func reopenFromRetention() {
        guard presentation == .retention else { return }
        presentation = .primary
    }
}
