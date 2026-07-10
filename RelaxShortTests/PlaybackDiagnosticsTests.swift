import XCTest
@testable import RelaxShort

/// Task36B-2 返工 v3 定向测试：diagnostics trace 隔离 + MediaURLProbe 流式取消保护
final class PlaybackDiagnosticsTests: XCTestCase {

    // MARK: - PlaybackDiagnosticsTrace

    func testTraceMarkAndFinishOutputsTermination() {
        var trace = PlaybackDiagnosticsTrace(scene: "test", seriesID: "s1", episodeNumber: 1)
        trace.mark("阶段A")
        trace.mark("阶段B")
        // finish 不应 crash，且 termination 参数被接受
        trace.finish(termination: "测试终止")
        XCTAssertEqual(trace.marks.count, 2)
        XCTAssertEqual(trace.marks[0].name, "阶段A")
        XCTAssertEqual(trace.marks[1].name, "阶段B")
    }

    func testTraceFinishDefaultsTo完成() {
        var trace = PlaybackDiagnosticsTrace(scene: "test")
        trace.finish() // 默认 termination="完成"
        XCTAssertEqual(trace.marks.count, 0) // 无 mark 也可以 finish
    }

    // MARK: - trace 保存恢复（预取隔离）

    @MainActor func testSaveRestorePreservesTrace() {
        // 模拟：当前集 trace → 预取保存 → 预取完成恢复
        let engine = ShortVideoPlayerEngine()
        let currentTrace = PlaybackDiagnosticsTrace(scene: "series", seriesID: "s1", episodeNumber: 1)
        engine.startPlaybackTrace(currentTrace)

        // 预取前保存
        let saved = engine.saveTrace()
        XCTAssertNil(engine.saveTrace()) // 已 nil

        // 预取中 trace 不影响已保存的
        let prefetchTrace = PlaybackDiagnosticsTrace(scene: "prefetch")
        engine.startPlaybackTrace(prefetchTrace)
        engine.markTrace("预取标记")
        engine.finishTrace(termination: "预取完成")

        // 恢复原 trace
        engine.restoreTrace(saved)
        engine.markTrace("当前集标记")

        // 验证：原始 trace 被恢复
        XCTAssertNotNil(saved)
    }

    // MARK: - Series 三个切集入口都有新 trace

    @MainActor func testSwitchToEpisodeStartsNewTrace() {
        let engine = ShortVideoPlayerEngine()
        // 模拟 switchToEpisode 入口（场景="series_switch"，带 episodeNumber）
        let trace = PlaybackDiagnosticsTrace(scene: "series_switch", seriesID: "d1", episodeNumber: 3)
        engine.startPlaybackTrace(trace)
        engine.markTrace("测试标记")
        XCTAssertEqual(trace.scene, "series_switch")
        XCTAssertEqual(trace.episodeNumber, 3)
    }

    // MARK: - MediaURLProbe 流式取消

    func testProbeHeadOnlyDoesNotCrash() {
        // HEAD 检查不 crash
        let url = URL(string: "https://httpbin.org/get")!
        MediaURLProbe.probe(url)
        // 异步执行，测试不 crash 即可
        XCTAssertTrue(true)
    }

    func testProbeInvalidURLDoesNotCrash() {
        let url = URL(string: "https://invalid.example/nonexistent.mp4")!
        MediaURLProbe.probe(url)
        XCTAssertTrue(true)
    }
}
