import Foundation

// MARK: - 播放器指标

struct PlayerMetrics { var ttffMs: Double = 0; var preloadHitCount = 0; var preloadMissCount = 0; var cacheHitCount = 0; var cacheMissCount = 0; var stallCount = 0; var stallDurationMs: Double = 0; var failedItemCount = 0; var recoveryCount = 0; var recoveryDurationMs: Double = 0; var canceledPreloadCount = 0; var currentSlotCount = 3; var memoryWarningCount = 0 }

struct PlayerMetricsLogger { var m = PlayerMetrics(); private let p = "[PlayerKit]"
    mutating func logTTFF(_ ms: Double) { m.ttffMs = ms; log("TTFF: \(String(format: "%.0f", ms))ms") }
    mutating func logPreloadHit() { m.preloadHitCount += 1 }
    mutating func logCacheHit() { m.cacheHitCount += 1; log("cache hit #\(m.cacheHitCount)") }
    mutating func logCacheMiss() { m.cacheMissCount += 1; log("cache miss #\(m.cacheMissCount)") }
    mutating func logStall(ms: Double) { m.stallCount += 1; m.stallDurationMs += ms; log("stall #\(m.stallCount)") }
    mutating func logFailed() { m.failedItemCount += 1 }
    mutating func logRecovery(ms: Double) { m.recoveryCount += 1; m.recoveryDurationMs += ms; log("recovery #\(m.recoveryCount)") }
    mutating func logCanceledPreload(_ n: Int) { m.canceledPreloadCount += n; log("canceled preload: \(n) total: \(m.canceledPreloadCount)") }
    mutating func logMemoryWarning() { m.memoryWarningCount += 1 }
    func summary() { log("summary: TTFF=\(String(format: "%.0f", m.ttffMs))ms cache:hit=\(m.cacheHitCount) miss=\(m.cacheMissCount) stalls=\(m.stallCount) failed=\(m.failedItemCount) recoveries=\(m.recoveryCount)") }
    private func log(_ msg: String) {
        #if DEBUG
        print("\(p) \(msg)")
        #endif
    }
}
