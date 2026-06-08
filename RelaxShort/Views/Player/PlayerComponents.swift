import SwiftUI
import AVFoundation

// MARK: - PlayerKit 播放器视图

struct ShortVideoPlayerView: View { let player: AVPlayer?; let coverURL: String; @ObservedObject var engine: ShortVideoPlayerEngine; @StateObject private var loader = ImageLoader()
    var body: some View { ZStack { Color.black; if let player { PLayerBridge(player: player) }; if showCover { coverView }; if engine.state == .preparing || engine.state == .waitingNetwork || engine.state == .recovering { ProgressView().tint(.white).scaleEffect(1.2) }; if engine.state == .pausedByUser { Image(systemName: "play.fill").font(.system(size: 36, weight: .medium)).foregroundColor(.white).frame(width: 72, height: 72).background(Circle().fill(Color.black.opacity(0.42))) }; if let t = engine.subtitleText, !t.isEmpty { VStack { Spacer(); Text(t).font(.system(size: 16, weight: .semibold)).foregroundColor(.white).shadow(color: .black.opacity(0.7), radius: 2).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 60) } } }.task { await loader.load(coverURL) } }
    private var showCover: Bool { if player == nil { return true }; if !engine.isReadyForDisplay { return true }; switch engine.state { case .idle, .preparing, .failed: return true; default: return false } }
    @ViewBuilder private var coverView: some View { if let i = loader.image { Image(uiImage: i).resizable().scaledToFill().clipped() } else { Rectangle().fill(LinearGradient(colors: [Color(hex: "#2D1B69"), Color(hex: "#1a1a3e")], startPoint: .topLeading, endPoint: .bottomTrailing)) } }
}
private struct PLayerBridge: UIViewRepresentable { let player: AVPlayer
    func makeUIView(context: Context) -> PBUIView { let v = PBUIView(); (v.layer as? AVPlayerLayer)?.player = player; (v.layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ v: PBUIView, context: Context) { if (v.layer as? AVPlayerLayer)?.player !== player { (v.layer as? AVPlayerLayer)?.player = player } }
}
private final class PBUIView: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self }; override func layoutSubviews() { super.layoutSubviews(); (layer as? AVPlayerLayer)?.frame = bounds } }

// MARK: - PlayerKit 字幕解析

actor SubtitleParser { func parse(url: URL, format: PlayerSubtitleFormat) -> [PlayerSubtitleCue] { guard let c = try? String(contentsOf: url, encoding: .utf8) else { return [] }; return format == .vtt ? parseVTT(c) : parseSRT(c) }
    private func parseSRT(_ c: String) -> [PlayerSubtitleCue] { var cues: [PlayerSubtitleCue] = []; for (idx, b) in c.components(separatedBy: "\n\n").enumerated() { let lines = b.components(separatedBy: "\n").filter { !$0.isEmpty }; guard lines.count >= 3 else { continue }; let parts = lines[1].components(separatedBy: " --> "); guard parts.count == 2, let s = parseTime(parts[0]), let e = parseTime(parts[1]) else { continue }; cues.append(PlayerSubtitleCue(index: idx, start: s, end: e, text: lines[2...].joined(separator: "\n"))) }; return cues }
    private func parseVTT(_ c: String) -> [PlayerSubtitleCue] { var cues: [PlayerSubtitleCue] = []; var s: TimeInterval = 0; var e: TimeInterval = 0; var txt: [String] = []; var idx = 0; for line in c.components(separatedBy: "\n") { let t = line.trimmingCharacters(in: .whitespaces); if t.isEmpty || t.hasPrefix("WEBVTT") || t.hasPrefix("Kind:") || t.hasPrefix("Language:") { continue }; if t.contains(" --> ") { if !txt.isEmpty { cues.append(PlayerSubtitleCue(index: idx, start: s, end: e, text: txt.joined(separator: "\n"))); idx &+= 1; txt = [] }; let p = t.components(separatedBy: " --> "); s = parseTime(p[0]) ?? 0; e = parseTime(p.count > 1 ? p[1] : p[0]) ?? 0 } else if Int(t) == nil { txt.append(t.stripTags()) } }; if !txt.isEmpty { cues.append(PlayerSubtitleCue(index: idx, start: s, end: e, text: txt.joined(separator: "\n"))) }; return cues }
    private func parseTime(_ r: String) -> TimeInterval? { let c = r.components(separatedBy: " ").first ?? r; let p = c.components(separatedBy: ":"); guard p.count == 3 else { return nil }; let sp = p[2].components(separatedBy: "."); guard let h = Double(p[0]), let m = Double(p[1]), let s = Double(sp[0]) else { return nil }; return h * 3600 + m * 60 + s + (sp.count > 1 ? (Double(sp[1]) ?? 0) / 1000 : 0) }
}
extension String { func stripTags() -> String { var t = self; for tag in ["<b>","</b>","<i>","</i>","<u>","</u>","<v>","</v>"] { t = t.replacingOccurrences(of: tag, with: "") }; if let r = try? NSRegularExpression(pattern: "<[^>]+>") { t = r.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "") }; return t } }

// MARK: - PlayerKit MP4 缓存

final class HTTPRangeMediaCache { static let shared = HTTPRangeMediaCache(); private let root: URL; private let maxSize: Int64 = 500_000_000; private var meta: [String: CM] = [:]; private let metaFile: URL; private let q = DispatchQueue(label: "com.rs.cache", qos: .utility)
    struct CM: Codable { var url: String = ""; var len: Int64?; var mime: String?; var ranges: [String] = []; var access: Date = Date() }
    init() { root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("PM"); metaFile = root.appendingPathComponent("m.json"); try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); load() }
    func cachedData(for url: URL, range: ClosedRange<Int64>) -> Data? { try? Data(contentsOf: file(key(url), range)) }
    func write(data: Data, for url: URL, range: ClosedRange<Int64>, len: Int64?, mime: String?) { let k = key(url); let f = file(k, range); q.async { try? data.write(to: f); self.upd(k, url: url, range: range, len: len, mime: mime) } }
    func hasCache(for url: URL) -> Bool { meta[key(url)]?.ranges.isEmpty == false }
    func pruneIfNeeded() { q.async { self.prune() } }
    private func key(_ u: URL) -> String { u.absoluteString.data(using: .utf8)?.base64EncodedString() ?? u.lastPathComponent }
    private func file(_ k: String, _ r: ClosedRange<Int64>) -> URL { root.appendingPathComponent("\(k)_\(r.lowerBound)_\(r.upperBound)") }
    private func upd(_ k: String, url: URL, range: ClosedRange<Int64>, len: Int64?, mime: String?) { var m = meta[k] ?? CM(); m.url = url.absoluteString; m.ranges.append("\(range.lowerBound)-\(range.upperBound)"); m.access = Date(); if let len { m.len = len }; if let mime { m.mime = mime }; meta[k] = m; save(); prune() }
    private func save() { if let d = try? JSONEncoder().encode(meta) { try? d.write(to: metaFile) } }
    private func load() { if let d = try? Data(contentsOf: metaFile) { meta = (try? JSONDecoder().decode([String: CM].self, from: d)) ?? [:] } }
    private func prune() { let sorted = meta.sorted { $0.value.access < $1.value.access }; var size = totalSize(); for (k, _) in sorted where size > maxSize { for f in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent.hasPrefix(k) { try? FileManager.default.removeItem(at: f) }; meta.removeValue(forKey: k); size = totalSize() }; save() }
    private func totalSize() -> Int64 { (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(0) { $0 + (Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)) } ?? 0 }
}

// MARK: - PlayerKit 资源加载代理

final class PlayerResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate { private let origURL: URL; private let cache = HTTPRangeMediaCache.shared; private var session: URLSession?
    init(originalURL: URL) { origURL = originalURL; super.init(); session = URLSession(configuration: .default) }
    func resourceLoader(_: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource r: AVAssetResourceLoadingRequest) -> Bool { guard let dr = r.dataRequest else { return false }; let range = dr.requestedOffset...(dr.requestedOffset + Int64(dr.requestedLength) - 1); if let d = cache.cachedData(for: origURL, range: range) { dr.respond(with: d); r.finishLoading(); return true }; let url = origURL; var req = URLRequest(url: url); req.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range"); session?.dataTask(with: req) { [weak self] d, resp, err in if let err { r.finishLoading(with: err); return }; guard let self, let d else { return }; self.cache.write(data: d, for: url, range: range, len: (resp as? HTTPURLResponse)?.expectedContentLength, mime: (resp as? HTTPURLResponse)?.mimeType); dr.respond(with: d); r.finishLoading() }.resume(); return true }
    func resourceLoader(_: AVAssetResourceLoader, didCancel _: AVAssetResourceLoadingRequest) {}
}

// MARK: - PlayerKit 指标

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

// MARK: - 兼容旧 PlayerComponents

struct VideoPlayerRepresentable: UIViewRepresentable { let player: AVPlayer; func makeUIView(context: Context) -> UIView { OldPUIView(player: player) }; func updateUIView(_ v: UIView, context: Context) { if let pv = v as? OldPUIView, pv.pl !== player { pv.pl = player } } }
private final class OldPUIView: UIView { var pl: AVPlayer { get { (layer as? AVPlayerLayer)?.player ?? AVPlayer() } set { (layer as? AVPlayerLayer)?.player = newValue } }; override class var layerClass: AnyClass { AVPlayerLayer.self }; init(player: AVPlayer) { super.init(frame: .zero); self.pl = player; (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill; backgroundColor = .black }; required init?(coder: NSCoder) { fatalError() } }

struct SubtitleRenderer: View { let text: String?; var body: some View { if let t = text, !t.isEmpty { VStack { Spacer(); Text(t).font(.system(size: 16, weight: .semibold)).foregroundColor(.white).shadow(color: .black.opacity(0.7), radius: 2).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 60) } } } }
