import Foundation

// MARK: - WatchProgressReporter

/// 观看进度上报 actor，保证单会话串行，节流 heartbeat（15s/3s 增量），
/// 暂停/切集/退出/完成时强制发送 final report。
///
/// 注入 `now`/`uuid` 供测试使用；生产使用 ContinuousClock 和 UUID()。
///
/// ## Actor Reentrancy
/// Send 期间 actor 可重入。使用 session UUID + generation 保证：
/// - old final/observe response 返回后只更新它自己的 session。
/// - old response 不能覆盖或清掉新 session。
actor WatchProgressReporter {

    // MARK: - Session

    private struct Session {
        let id: UUID
        let seriesID: String
        let episodeID: String
        let sourceType: String?
        let quality: String?
        let contentLanguage: String?
        let subtitleLanguage: String?
        var generation: Int = 0
        /// 最近一次成功发送的 seconds
        var lastSentSeconds: Int = 0
        /// 最近一次成功发送的时刻
        var lastSentInstant: ContinuousClock.Instant?
        /// 最新 observe 传入的 seconds（不受节流限制）
        var latestSeconds: Int = 0
        /// 最新 observe 传入的 duration（不受节流限制）
        var latestDuration: Int = 0
        /// 已入发送队列、尚未完成的 heartbeat generation
        var pendingHeartbeatGeneration: Int?
        var finalized: Bool = false
    }

    // MARK: - State

    private var session: Session?
    private let repository: FavoritesRepositoryProtocol
    private let now: @Sendable () -> ContinuousClock.Instant
    private let uuidGenerator: @Sendable () -> UUID
    private let throttleInterval: Duration
    private let minProgressDelta: Int
    private var sendTail: (id: Int, task: Task<Bool, Never>)?
    private var nextSendID = 0

    // MARK: - Init

    init(
        repository: FavoritesRepositoryProtocol,
        throttleInterval: Duration = .seconds(15),
        minProgressDelta: Int = 3,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        uuidGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.repository = repository
        self.throttleInterval = throttleInterval
        self.minProgressDelta = minProgressDelta
        self.now = now
        self.uuidGenerator = uuidGenerator
    }

    // MARK: - Public API

    func begin(
        seriesID: String,
        episodeID: String,
        sourceType: String? = nil,
        quality: String? = nil,
        contentLanguage: String? = nil,
        subtitleLanguage: String? = nil
    ) {
        // 同一 active episode 的重复 begin 不重置 session
        if let s = session, s.episodeID == episodeID, !s.finalized { return }

        session = Session(
            id: uuidGenerator(),
            seriesID: seriesID,
            episodeID: episodeID,
            sourceType: sourceType,
            quality: quality,
            contentLanguage: contentLanguage,
            subtitleLanguage: subtitleLanguage
        )
    }

    func hasActiveSession() -> Bool {
        guard let s = session else { return false }
        return !s.finalized
    }

    /// 播放器进度快照。Actor 内部节流：15s 最多 1 次，增量不足 3s 不发送。
    /// 无论是否被节流，始终保存最新 seconds 和 duration。
    func observe(seconds: TimeInterval, duration: TimeInterval) async {
        guard var s = session, !s.finalized else { return }

        let currentInstant = now()
        let secs = Int(seconds)
        let total = Int(max(duration, 1))

        // 始终保存最新值，不受节流影响
        s.latestSeconds = secs
        s.latestDuration = total

        // 增量不足
        let delta = secs - s.lastSentSeconds
        guard delta >= minProgressDelta else {
            session = s
            return
        }

        // 节流
        if let last = s.lastSentInstant, currentInstant - last < throttleInterval {
            session = s
            return
        }
        // 前一个 heartbeat 尚未返回时只更新最新快照，不重复入队。
        guard s.pendingHeartbeatGeneration == nil else {
            session = s
            return
        }

        s.generation &+= 1
        let gen = s.generation
        let sessionID = s.id
        s.pendingHeartbeatGeneration = gen
        session = s

        let report = WatchProgressReport(
            seriesID: s.seriesID,
            episodeID: s.episodeID,
            progressSeconds: secs,
            totalDuration: total,
            completed: false,
            playSessionID: sessionID,
            finalReport: false,
            sourceType: s.sourceType,
            quality: s.quality,
            contentLanguage: s.contentLanguage,
            subtitleLanguage: s.subtitleLanguage
        )
        let queued = enqueue(report)
        let sent = await queued.task.value
        clearSendTail(ifLatest: queued.id)

        guard var cur = session,
              cur.id == sessionID,
              cur.pendingHeartbeatGeneration == gen else { return }
        cur.pendingHeartbeatGeneration = nil
        // 只在当前 session 仍活跃且成功发送后更新节流状态。
        if sent, !cur.finalized {
            cur.lastSentSeconds = secs
            cur.lastSentInstant = currentInstant
        }
        session = cur
    }

    /// 强制发送最终进度快照。
    /// - Parameter completed: 是否播放完成
    /// - Note: 使用最新保存的 seconds 和真实 duration；
    ///   completed=false 时不会伪造 1:1 比例导致后端误判完播。
    func finalize(completed: Bool) async {
        guard var s = session, !s.finalized else { return }
        s.finalized = true
        s.generation &+= 1
        let sessionID = s.id

        // 使用最新进度而非 lastSentSeconds
        let progressSecs = s.latestSeconds
        let totalDur = max(s.latestDuration, 1)

        session = s

        let report = WatchProgressReport(
            seriesID: s.seriesID,
            episodeID: s.episodeID,
            progressSeconds: progressSecs,
            totalDuration: totalDur,
            completed: completed,
            playSessionID: sessionID,
            finalReport: true,
            sourceType: s.sourceType,
            quality: s.quality,
            contentLanguage: s.contentLanguage,
            subtitleLanguage: s.subtitleLanguage
        )
        let queued = enqueue(report)
        _ = await queued.task.value
        clearSendTail(ifLatest: queued.id)

        // 只在 session 未被替换时清理（防范 actor reentrancy）
        if let cur = session, cur.id == sessionID {
            session = nil
        }
    }

    // MARK: - Private

    /// 所有 heartbeat/final 都串到同一条 task 链，保证请求开始与完成顺序一致。
    private func enqueue(_ report: WatchProgressReport) -> (id: Int, task: Task<Bool, Never>) {
        nextSendID &+= 1
        let id = nextSendID
        let previous = sendTail?.task
        let repository = repository
        let task = Task {
            _ = await previous?.value
            do {
                try await repository.reportProgress(report)
                return true
            } catch {
                Logger.viewModel.warning("WatchProgressReporter: send failed: \(error)")
                return false
            }
        }
        sendTail = (id, task)
        return (id, task)
    }

    private func clearSendTail(ifLatest id: Int) {
        if sendTail?.id == id {
            sendTail = nil
        }
    }
}
