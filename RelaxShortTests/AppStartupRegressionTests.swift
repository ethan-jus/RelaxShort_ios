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

    @Test("latest-wins 门禁只接受最后一次请求")
    func latestRequestGateRejectsStaleResponses() {
        var gate = LatestRequestGate()
        let stale = gate.begin()
        let latest = gate.begin()

        #expect(!gate.accepts(stale))
        #expect(gate.accepts(latest))
    }

    @MainActor
    @Test("国家事件仅在规范化代码实际变化时生成")
    func discoveryCountryChangeRequiresActualValueChange() {
        #expect(
            AppInitService.discoveryCountryChange(
                previousCountryCode: " us ",
                updatedCountryCode: "US"
            ) == nil
        )
        #expect(
            AppInitService.discoveryCountryChange(
                previousCountryCode: "US",
                updatedCountryCode: "ca"
            ) == DiscoveryCountryChange(
                previousCountryCode: "US",
                countryCode: "CA"
            )
        )
    }
}
