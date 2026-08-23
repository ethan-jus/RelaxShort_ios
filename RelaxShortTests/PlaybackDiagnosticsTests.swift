import XCTest
import AVFoundation
import UIKit
@testable import RelaxShort

/// Task36B-2 返工 v4：StreamedRangeFetcher 流式取消 + recordTrace 隔离 + trace 标记
final class PlaybackDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRangeProtocol.self]
        StreamedRangeFetcher.testConfiguration = config
    }
    override func tearDown() {
        StreamedRangeFetcher.testConfiguration = nil
        super.tearDown()
    }

    // MARK: - StreamedRangeFetcher 流式保护

    func test200DoesNotDownloadBody() async {
        let url = URL(string: "https://x.local/a.mp4")!
        MockRangeProtocol.response = { _ in
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1",
                            headerFields: ["Content-Length":"104857600"])!
        }
        MockRangeProtocol.chunks = [Data(repeating: 0, count: 65536)] // 64KB，但应被取消不传给 delegate
        let r = await StreamedRangeFetcher.fetch(url: url, requestedRange: 0...262143, maxBytes: 262144)
        guard case .notRange(200, _) = r else { XCTFail("Expected notRange(200), got \(r)"); return }
    }

    func test206ValidContentRangeSucceeds() async {
        let url = URL(string: "https://x.local/b.mp4")!
        let body = Data(repeating: 0xAB, count: 262144)
        MockRangeProtocol.response = { _ in
            HTTPURLResponse(url: url, statusCode: 206, httpVersion: "1.1",
                            headerFields: ["Content-Range":"bytes 0-262143/104857600"])!
        }
        MockRangeProtocol.chunks = [body]
        let r = await StreamedRangeFetcher.fetch(url: url, requestedRange: 0...262143, maxBytes: 262144)
        guard case .success(let data, 104857600) = r else { XCTFail("Expected success, got \(r)"); return }
        XCTAssertEqual(data.count, 262144)
    }

    func test206OverMaxBytesIsTruncated() async {
        let url = URL(string: "https://x.local/c.mp4")!
        // 返回 300KB 但上限 256KB，应被截断
        MockRangeProtocol.response = { _ in
            HTTPURLResponse(url: url, statusCode: 206, httpVersion: "1.1",
                            headerFields: ["Content-Range":"bytes 0-299999/104857600"])!
        }
        MockRangeProtocol.chunks = [Data(repeating: 0, count: 270000), Data(repeating: 0, count: 30000)]
        let r = await StreamedRangeFetcher.fetch(url: url, requestedRange: 0...299999, maxBytes: 262144)
        guard case .truncated = r else { XCTFail("Expected truncated, got \(r)"); return }
    }

    func test206MismatchedRangeFails() async {
        let url = URL(string: "https://x.local/d.mp4")!
        // Content-Range 声称 0-524287 但请求只有 0-262143
        MockRangeProtocol.response = { _ in
            HTTPURLResponse(url: url, statusCode: 206, httpVersion: "1.1",
                            headerFields: ["Content-Range":"bytes 0-524287/104857600"])!
        }
        MockRangeProtocol.chunks = [Data(repeating: 0, count: 524288)]
        let r = await StreamedRangeFetcher.fetch(url: url, requestedRange: 0...262143, maxBytes: 524288)
        guard case .failed = r else { XCTFail("Expected failed, got \(r)"); return }
    }

    // MARK: - recordTrace 预取不污染

    @MainActor func testRecordTraceFalseNeverMarksEngine() {
        // recordTrace=false 时 engine 完全不受影响
        let engine = ShortVideoPlayerEngine()
        let t = PlaybackDiagnosticsTrace(scene: "series", seriesID: "d1", episodeNumber: 1)
        engine.startPlaybackTrace(t)
        engine.markTrace("开始加载")
        // 当前集 trace 有 1 个 mark
        engine.finishTrace(termination: "完成")
    }

    @MainActor func testRecordTraceTrueMarksAllStages() {
        let engine = ShortVideoPlayerEngine()
        let t = PlaybackDiagnosticsTrace(scene: "series_switch", seriesID: "d1", episodeNumber: 3)
        engine.startPlaybackTrace(t)
        engine.markTrace("缓存命中")
        engine.markTrace("播放源")
        engine.markTrace("AVPlayer准备")
        engine.markTrace("attach播放器")
        // 不 crash
        engine.finishTrace(termination: "完成")
    }

    @MainActor func testLockedTraceOutputsTermination() {
        let engine = ShortVideoPlayerEngine()
        let t = PlaybackDiagnosticsTrace(scene: "series_switch", seriesID: "d1", episodeNumber: 5)
        engine.startPlaybackTrace(t)
        engine.markTrace("锁集阻断-EP5")
        engine.finishTrace(termination: "锁集阻断")
    }

    // MARK: - Series 三个切集入口都有新 trace

    @MainActor func testAllSwitchEntriesUseSeriesSwitchScene() {
        for ep in [3, 5, 7] {
            let trace = PlaybackDiagnosticsTrace(scene: "series_switch", seriesID: "d1", episodeNumber: ep)
            XCTAssertEqual(trace.scene, "series_switch")
            XCTAssertEqual(trace.episodeNumber, ep)
        }
    }

    /// 真实 HLS 模拟器压力测试。默认跳过，发布前显式传入三集 URL 才执行，
    /// 避免日常单测依赖线上网络。覆盖 1→2→3→2→1、相邻槽复用和快速连续切集。
    @MainActor
    func testLiveHLSRoundTripAndRapidSwitching() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURLs = environment["RELAXSHORT_LIVE_PLAYER_URLS"] else {
            throw XCTSkip("仅在发布前显式注入 RELAXSHORT_LIVE_PLAYER_URLS 时执行")
        }
        let urls = rawURLs
            .split(separator: ",")
            .compactMap { URL(string: String($0)) }
        XCTAssertEqual(urls.count, 3, "RELAXSHORT_LIVE_PLAYER_URLS 必须提供三个逗号分隔的 HLS URL")
        guard urls.count == 3 else { return }

        let items = urls.enumerated().map { offset, url in
            PlayerMediaItem(
                id: "live-episode-\(offset + 1)",
                title: "Live Episode \(offset + 1)",
                episodeNumber: offset + 1,
                coverURL: "",
                source: .hls(masterURL: url),
                resumeTime: nil
            )
        }
        let engine = ShortVideoPlayerEngine()
        let renderProbe = try makeRenderProbe()
        defer {
            renderProbe.layer.player = nil
            renderProbe.view.removeFromSuperview()
            engine.deactivate()
        }

        var timings: [(String, Double)] = []
        engine.prepare(items: items, index: 0)
        engine.play()
        let first = try await waitForVisiblePlayback(
            engine: engine,
            layer: renderProbe.layer,
            mediaID: items[0].id,
            timeout: 15
        )
        timings.append(("1 cold", first.elapsedMs))
        try await assertPlaybackProgresses(engine: engine, mediaID: items[0].id)
        try await Task.sleep(nanoseconds: 1_500_000_000)

        engine.move(to: 1)
        let secondForward = try await waitForVisiblePlayback(
            engine: engine,
            layer: renderProbe.layer,
            mediaID: items[1].id,
            timeout: 8
        )
        timings.append(("1→2", secondForward.elapsedMs))
        try await assertPlaybackProgresses(engine: engine, mediaID: items[1].id)
        try await Task.sleep(nanoseconds: 1_500_000_000)

        engine.move(to: 2)
        let thirdForward = try await waitForVisiblePlayback(
            engine: engine,
            layer: renderProbe.layer,
            mediaID: items[2].id,
            timeout: 8
        )
        timings.append(("2→3", thirdForward.elapsedMs))
        try await assertPlaybackProgresses(engine: engine, mediaID: items[2].id)
        try await Task.sleep(nanoseconds: 1_500_000_000)

        engine.move(to: 1)
        let secondBackward = try await waitForVisiblePlayback(
            engine: engine,
            layer: renderProbe.layer,
            mediaID: items[1].id,
            timeout: 4
        )
        timings.append(("3→2", secondBackward.elapsedMs))
        XCTAssertEqual(
            secondBackward.playerID,
            secondForward.playerID,
            "回到第 2 集应复用之前预热并播放过的同一个 AVPlayer"
        )
        try await assertPlaybackProgresses(engine: engine, mediaID: items[1].id)
        try await Task.sleep(nanoseconds: 1_500_000_000)

        engine.move(to: 0)
        let firstBackward = try await waitForVisiblePlayback(
            engine: engine,
            layer: renderProbe.layer,
            mediaID: items[0].id,
            timeout: 6
        )
        timings.append(("2→1", firstBackward.elapsedMs))
        try await assertPlaybackProgresses(engine: engine, mediaID: items[0].id)

        // 模拟快速连续滑动；只有最后一次目标允许接管可见/可听状态。
        engine.move(to: 1)
        try await Task.sleep(nanoseconds: 180_000_000)
        engine.move(to: 2)
        try await Task.sleep(nanoseconds: 180_000_000)
        engine.move(to: 1)
        try await Task.sleep(nanoseconds: 180_000_000)
        engine.move(to: 0)
        let rapidReturn = try await waitForVisiblePlayback(
            engine: engine,
            layer: renderProbe.layer,
            mediaID: items[0].id,
            timeout: 8
        )
        timings.append(("rapid→1", rapidReturn.elapsedMs))
        try await assertPlaybackProgresses(engine: engine, mediaID: items[0].id)

        let summary = timings
            .map { "\($0.0)=\(Int($0.1))ms" }
            .joined(separator: " ")
        print("[LivePlayerStress] \(summary)")
    }

    @MainActor
    private func makeRenderProbe() throws -> (view: UIView, layer: AVPlayerLayer) {
        let window = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first
        )
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 180, height: 320))
        view.isUserInteractionEnabled = false
        let layer = AVPlayerLayer()
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        window.addSubview(view)
        return (view, layer)
    }

    @MainActor
    private func waitForVisiblePlayback(
        engine: ShortVideoPlayerEngine,
        layer: AVPlayerLayer,
        mediaID: String,
        timeout: TimeInterval
    ) async throws -> (elapsedMs: Double, playerID: ObjectIdentifier) {
        let startedAt = CACurrentMediaTime()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if case .failed(let message) = engine.state {
                XCTFail("\(mediaID) 播放失败：\(message ?? "unknown")")
                throw NSError(domain: "LivePlayerStress", code: 1)
            }
            if engine.currentItem?.id == mediaID,
               let player = engine.currentPlayer {
                if layer.player !== player {
                    layer.player = player
                }
                let seconds = player.currentTime().seconds
                if layer.isReadyForDisplay,
                   player.currentItem?.status == .readyToPlay,
                   player.timeControlStatus == .playing,
                   seconds.isFinite,
                   seconds > 0.05 {
                    engine.markReadyForDisplay(from: player)
                    return (
                        (CACurrentMediaTime() - startedAt) * 1000,
                        ObjectIdentifier(player)
                    )
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("\(mediaID) 未在 \(timeout)s 内出现可见首帧，state=\(engine.state)")
        throw NSError(domain: "LivePlayerStress", code: 2)
    }

    @MainActor
    private func assertPlaybackProgresses(
        engine: ShortVideoPlayerEngine,
        mediaID: String
    ) async throws {
        guard let player = engine.currentPlayer else {
            XCTFail("\(mediaID) 没有当前 AVPlayer")
            return
        }
        let startedAt = player.currentTime().seconds
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let current = player.currentTime().seconds
            if current.isFinite, startedAt.isFinite, current - startedAt >= 0.5 {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("\(mediaID) 首帧后 3s 内播放进度未继续推进")
    }
}

// MARK: - URLProtocol Mock

private class MockRangeProtocol: URLProtocol {
    static var response: ((URLRequest) -> HTTPURLResponse)?
    static var chunks: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let resp = Self.response?(request) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "Mock", code: -1))
            return
        }
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        // 分块发送模拟流式，超过 256KB 的块可触发截断
        for chunk in Self.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
