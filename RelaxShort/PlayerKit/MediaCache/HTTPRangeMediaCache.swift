import Foundation

// MARK: - HTTP Range 媒体缓存

/// MP4 Range 缓存管理器：500MB LRU
final class HTTPRangeMediaCache {
    static let shared = HTTPRangeMediaCache()
    private let root: URL; private let maxSize: Int64 = 500_000_000
    private var meta: [String: CM] = [:]; private let metaFile: URL
    private let q = DispatchQueue(label: "com.rs.cache", qos: .utility)
    struct CM: Codable { var url: String = ""; var len: Int64?; var mime: String?; var ranges: [String] = []; var access: Date = Date() }

    init() {
        root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("PlayerMediaCache")
        metaFile = root.appendingPathComponent("meta.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); load()
    }
    func cachedData(for url: URL, range: ClosedRange<Int64>) -> Data? {
        let k = key(url)
        let ranges = meta[k]?.ranges.compactMap { parseRange($0) } ?? []
        // 精确匹配
        let f = file(k, range)
        if let d = try? Data(contentsOf: f) { return d }
        // 子区间：从已缓存的更大 range 中读取
        for cached in ranges where cached.lowerBound <= range.lowerBound && cached.upperBound >= range.upperBound {
            let f2 = file(k, cached)
            if let full = try? Data(contentsOf: f2) {
                let offset = Int(range.lowerBound - cached.lowerBound)
                let length = Int(range.upperBound - range.lowerBound + 1)
                guard offset + length <= full.count else { continue }
                return full.subdata(in: offset..<(offset + length))
            }
        }
        return nil
    }

    private func parseRange(_ s: String) -> ClosedRange<Int64>? {
        let parts = s.components(separatedBy: "-")
        guard parts.count == 2, let lo = Int64(parts[0]), let hi = Int64(parts[1]) else { return nil }
        return lo...hi
    }
    func write(data: Data, for url: URL, range: ClosedRange<Int64>, len: Int64?, mime: String?) {
        let k = key(url); let f = file(k, range)
        q.async { [weak self] in try? data.write(to: f); self?.update(k, url: url, range: range, len: len, mime: mime) }
    }
    func hasCache(for url: URL) -> Bool { meta[key(url)]?.ranges.isEmpty == false }
    func pruneIfNeeded() { q.async { [weak self] in self?.prune() } }
    private func key(_ u: URL) -> String { u.absoluteString.data(using: .utf8)?.base64EncodedString() ?? u.lastPathComponent }
    private func file(_ k: String, _ r: ClosedRange<Int64>) -> URL { root.appendingPathComponent("\(k)_\(r.lowerBound)_\(r.upperBound)") }
    private func update(_ k: String, url: URL, range: ClosedRange<Int64>, len: Int64?, mime: String?) {
        var m = meta[k] ?? CM(); m.url = url.absoluteString; m.ranges.append("\(range.lowerBound)-\(range.upperBound)"); m.access = Date(); if let len { m.len = len }; if let mime { m.mime = mime }; meta[k] = m; save(); prune()
    }
    private func save() { if let d = try? JSONEncoder().encode(meta) { try? d.write(to: metaFile) } }
    private func load() { if let d = try? Data(contentsOf: metaFile) { meta = (try? JSONDecoder().decode([String: CM].self, from: d)) ?? [:] } }
    private func prune() {
        let sorted = meta.sorted { $0.value.access < $1.value.access }; var size = totalSize()
        for (k, _) in sorted where size > maxSize {
            for f in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent.hasPrefix(k) { try? FileManager.default.removeItem(at: f) }
            meta.removeValue(forKey: k); size = totalSize()
        }; save()
    }
    private func totalSize() -> Int64 { (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(0) { $0 + (Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)) } ?? 0 }
}
