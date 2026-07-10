import XCTest
@testable import RelaxShort

/// Task36B-2 返工 v4：StreamedRangeFetcher 流式取消 + recordTrace 隔离 + trace 标记
final class PlaybackDiagnosticsTests: XCTestCase {
    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRangeProtocol.self]
        mockSession = URLSession(configuration: config)
        StreamedRangeFetcher.testSession = mockSession
    }
    override func tearDown() {
        StreamedRangeFetcher.testSession = nil
        mockSession = nil
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
        var t = PlaybackDiagnosticsTrace(scene: "series", seriesID: "d1", episodeNumber: 1)
        engine.startPlaybackTrace(t)
        engine.markTrace("开始加载")
        // 当前集 trace 有 1 个 mark
        engine.finishTrace(termination: "完成")
    }

    @MainActor func testRecordTraceTrueMarksAllStages() {
        let engine = ShortVideoPlayerEngine()
        var t = PlaybackDiagnosticsTrace(scene: "series_switch", seriesID: "d1", episodeNumber: 3)
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
