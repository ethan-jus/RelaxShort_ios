import AVFoundation
import Testing
@testable import RelaxShort

@Suite
struct AppStartupRegressionTests {
    @Test("纯视频播放不传入仅录放类别支持的 AirPlay 选项")
    func playbackAudioSessionUsesValidOptions() {
        #expect(AppAudioSessionConfiguration.category == .playback)
        #expect(AppAudioSessionConfiguration.mode == .moviePlayback)
        #expect(AppAudioSessionConfiguration.options.isEmpty)
    }

    @MainActor
    @Test("视图生命周期取消初始化任务不记录为启动失败")
    func cancellationIsNotReportedAsInitializationFailure() {
        #expect(!AppInitService.shouldReportFailure(CancellationError()))
        #expect(AppInitService.shouldReportFailure(URLError(.timedOut)))
    }
}
