import Foundation
import CryptoKit

/// 公开内容的持久化媒体缓存配置。VIP 离线下载不复用此目录。
enum PlayerMediaCacheSettings {
    static let enabledKey = "playerMediaCacheEnabled"
    static let maximumBytesKey = "playerMediaCacheMaximumBytes"
    static let defaultMaximumBytes: Int64 = 2 * 1024 * 1024 * 1024

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var maximumBytes: Int64 {
        let value = (UserDefaults.standard.object(forKey: maximumBytesKey) as? NSNumber)?.int64Value
            ?? defaultMaximumBytes
        return max(0, value)
    }
}

// MARK: - HTTP Range 媒体缓存

/// 公开 MP4 的 Range 磁盘缓存：按最近访问时间淘汰，默认上限 2GB。
final class HTTPRangeMediaCache {
    static let shared = HTTPRangeMediaCache()
    private let root: URL
    private let maxMergedRangeBytes: Int64 = 16_000_000
    private var meta: [String: CM] = [:]; private let metaFile: URL
    private let q = DispatchQueue(label: "com.rs.cache", qos: .utility)
    private let lock = NSLock()
    enum CacheHitSource: String { case exact, contained }
    struct CacheReadResult { let data: Data; let source: CacheHitSource }
    struct CacheMetadata { let len: Int64?; let mime: String? }
    struct CM: Codable { var url: String = ""; var len: Int64?; var mime: String?; var ranges: [String] = []; var access: Date = Date() }

    init() {
        root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("PlayerMediaCache")
        metaFile = root.appendingPathComponent("meta.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); load()
    }
    func cachedData(for url: URL, range: ClosedRange<Int64>) -> CacheReadResult? {
        guard PlayerMediaCacheSettings.isEnabled else { return nil }
        let k = key(url)
        lock.lock(); let cachedRanges = meta[k]?.ranges.compactMap { parseRange($0) } ?? []; lock.unlock()
        let f = file(k, range)
        // 精确匹配
        if let d = try? Data(contentsOf: f) {
            touch(k)
            return CacheReadResult(data: d, source: .exact)
        }
        // 子区间
        for cached in cachedRanges where cached.lowerBound <= range.lowerBound && cached.upperBound >= range.upperBound {
            let f2 = file(k, cached)
            if let full = try? Data(contentsOf: f2) {
                let offset = Int(range.lowerBound - cached.lowerBound)
                let length = Int(range.upperBound - range.lowerBound + 1)
                guard offset + length <= full.count else { continue }
                touch(k)
                return CacheReadResult(data: full.subdata(in: offset..<(offset + length)), source: .contained)
            }
        }
        return nil
    }

    private func parseRange(_ s: String) -> ClosedRange<Int64>? {
        let parts = s.components(separatedBy: "-")
        guard parts.count == 2, let lo = Int64(parts[0]), let hi = Int64(parts[1]), hi >= lo else { return nil }
        return lo...hi
    }
    func write(data: Data, for url: URL, range: ClosedRange<Int64>, len: Int64?, mime: String?) {
        guard PlayerMediaCacheSettings.isEnabled else { return }
        let k = key(url)
        q.async { [weak self] in
            self?.writeMerged(data: data, for: url, key: k, range: range, len: len, mime: mime)
        }
    }
    func hasCache(for url: URL) -> Bool {
        lock.lock()
        let result = meta[key(url)]?.ranges.isEmpty == false
        lock.unlock()
        return result
    }
    func leadingCachedBytes(for url: URL) -> Int64 {
        let ranges = cachedRanges(for: url).sorted { $0.lowerBound < $1.lowerBound }
        var expectedStart: Int64 = 0
        var bytes: Int64 = 0
        for range in ranges {
            guard range.lowerBound <= expectedStart else { break }
            guard range.upperBound >= expectedStart else { continue }
            bytes += range.upperBound - expectedStart + 1
            expectedStart = range.upperBound + 1
        }
        return bytes
    }
    func hasPlayableLeadCache(for url: URL, minimumBytes: Int64) -> Bool {
        let m = metadata(for: url)
        guard let len = m.len, len > 0 else { return false }
        return leadingCachedBytes(for: url) >= minimumBytes
    }
    func metadata(for url: URL) -> CacheMetadata {
        lock.lock()
        let m = meta[key(url)]
        lock.unlock()
        return CacheMetadata(len: m?.len, mime: m?.mime)
    }
    func pruneIfNeeded() { q.async { [weak self] in self?.prune() } }

    func clear() {
        q.sync {
            lock.lock()
            defer { lock.unlock() }
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            meta.removeAll()
        }
    }

    func totalCachedBytes() -> Int64 {
        q.sync {
            lock.lock()
            defer { lock.unlock() }
            return totalSize()
        }
    }
    /// 已缓存区间列表（debug 用）
    func cachedRanges(for url: URL) -> [ClosedRange<Int64>] {
        lock.lock(); let ranges = meta[key(url)]?.ranges.compactMap { parseRange($0) } ?? []; lock.unlock()
        return ranges
    }
    /// 缓存摘要（debug 用）
    func debugSummary(for url: URL) -> String {
        let ranges = cachedRanges(for: url)
        let totalCached = ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound + 1) }
        return "[cache] \(url.lastPathComponent): \(ranges.count) ranges, \(totalCached) bytes"
    }
    private func key(_ u: URL) -> String {
        SHA256.hash(data: Data(u.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func file(_ k: String, _ r: ClosedRange<Int64>) -> URL { root.appendingPathComponent("\(k)_\(r.lowerBound)_\(r.upperBound)") }
    private func writeMerged(data: Data, for url: URL, key k: String, range: ClosedRange<Int64>, len: Int64?, mime: String?) {
        guard !data.isEmpty, range.upperBound >= range.lowerBound else { return }
        let incomingLength = range.upperBound - range.lowerBound + 1
        guard incomingLength == Int64(data.count) else { return }

        let existingRanges = cachedRanges(for: url)
        var mergedRange = range
        var mergeable: [ClosedRange<Int64>] = []
        var changed = true

        while changed {
            changed = false
            for existing in existingRanges where !mergeable.contains(existing) {
                let candidate = min(mergedRange.lowerBound, existing.lowerBound)...max(mergedRange.upperBound, existing.upperBound)
                let candidateLength = candidate.upperBound - candidate.lowerBound + 1
                let existingLength = existing.upperBound - existing.lowerBound + 1
                guard rangesTouchOrOverlap(mergedRange, existing),
                      candidateLength <= maxMergedRangeBytes,
                      existingLength <= Int64(Int.max),
                      let existingData = try? Data(contentsOf: file(k, existing)),
                      existingData.count == Int(existingLength) else {
                    continue
                }
                mergedRange = candidate
                mergeable.append(existing)
                changed = true
            }
        }

        let mergedLength = mergedRange.upperBound - mergedRange.lowerBound + 1
        guard mergedLength <= maxMergedRangeBytes, mergedLength <= Int64(Int.max) else {
            let f = file(k, range)
            do {
                try data.write(to: f)
            } catch {
                return
            }
            update(k, url: url, range: range, len: len, mime: mime)
            return
        }

        var mergedData = Data(repeating: 0, count: Int(mergedLength))
        for existing in mergeable {
            guard let existingData = try? Data(contentsOf: file(k, existing)) else { continue }
            let start = Int(existing.lowerBound - mergedRange.lowerBound)
            mergedData.replaceSubrange(start..<(start + existingData.count), with: existingData)
        }

        let incomingStart = Int(range.lowerBound - mergedRange.lowerBound)
        mergedData.replaceSubrange(incomingStart..<(incomingStart + data.count), with: data)

        do {
            try mergedData.write(to: file(k, mergedRange))
        } catch {
            return
        }

        lock.lock()
        var m = meta[k] ?? CM(); m.url = url.absoluteString
        let removed = Set(mergeable.map(rangeString))
        m.ranges.removeAll { removed.contains($0) || $0 == rangeString(range) }
        let mergedString = rangeString(mergedRange)
        if !m.ranges.contains(mergedString) { m.ranges.append(mergedString) }
        m.ranges = normalizedRanges(m.ranges)
        m.access = Date(); if let len { m.len = len }; if let mime { m.mime = mime }; meta[k] = m
        saveLocked()
        lock.unlock()

        for oldRange in mergeable where oldRange != mergedRange {
            try? FileManager.default.removeItem(at: file(k, oldRange))
        }
        if range != mergedRange {
            try? FileManager.default.removeItem(at: file(k, range))
        }
        prune()
    }
    private func update(_ k: String, url: URL, range: ClosedRange<Int64>, len: Int64?, mime: String?) {
        lock.lock()
        var m = meta[k] ?? CM(); m.url = url.absoluteString
        let rs = rangeString(range)
        if !m.ranges.contains(rs) { m.ranges.append(rs) }
        m.ranges = normalizedRanges(m.ranges)
        m.access = Date(); if let len { m.len = len }; if let mime { m.mime = mime }; meta[k] = m
        saveLocked()
        lock.unlock()
        prune()
    }
    private func touch(_ k: String) {
        q.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if var m = self.meta[k] {
                m.access = Date()
                self.meta[k] = m
                self.saveLocked()
            }
            self.lock.unlock()
        }
    }
    private func rangeString(_ range: ClosedRange<Int64>) -> String {
        "\(range.lowerBound)-\(range.upperBound)"
    }
    private func rangesTouchOrOverlap(_ a: ClosedRange<Int64>, _ b: ClosedRange<Int64>) -> Bool {
        let aUpperTouches = a.upperBound == Int64.max ? Int64.max : a.upperBound + 1
        let bUpperTouches = b.upperBound == Int64.max ? Int64.max : b.upperBound + 1
        return a.lowerBound <= bUpperTouches && b.lowerBound <= aUpperTouches
    }
    private func normalizedRanges(_ ranges: [String]) -> [String] {
        ranges.compactMap(parseRange)
            .sorted { $0.lowerBound < $1.lowerBound }
            .map(rangeString)
    }
    private func saveLocked() { if let d = try? JSONEncoder().encode(meta) { try? d.write(to: metaFile) } }
    private func save() {
        lock.lock()
        saveLocked()
        lock.unlock()
    }
    private func load() {
        lock.lock()
        if let d = try? Data(contentsOf: metaFile) {
            meta = (try? JSONDecoder().decode([String: CM].self, from: d)) ?? [:]
        }
        lock.unlock()
    }
    private func prune() {
        lock.lock()
        let sorted = meta.sorted { $0.value.access < $1.value.access }; var size = totalSize()
        for (k, _) in sorted where size > PlayerMediaCacheSettings.maximumBytes {
            for f in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent.hasPrefix(k) { try? FileManager.default.removeItem(at: f) }
            meta.removeValue(forKey: k); size = totalSize()
        }
        saveLocked()
        lock.unlock()
    }
    private func totalSize() -> Int64 { (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(0) { $0 + (Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)) } ?? 0 }
}
