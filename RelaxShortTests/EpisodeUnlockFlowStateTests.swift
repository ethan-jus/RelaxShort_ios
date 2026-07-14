import Testing
@testable import RelaxShort

struct EpisodeUnlockFlowStateTests {
    @Test
    func coinCTAUsesBalanceAndCost() {
        var sufficient = EpisodeUnlockFlowState(episodeNumber: 4, coinCost: 30, balance: 40, vipOnly: false)
        #expect(sufficient.primaryButtonTitle == "使用 30 金币解锁")

        sufficient.balance = 18
        #expect(sufficient.primaryButtonTitle == "充值并解锁")
        #expect(sufficient.coinShortfall == 12)
    }

    @Test
    func selectingVIPChangesTheSinglePrimaryAction() {
        var state = EpisodeUnlockFlowState(episodeNumber: 4, coinCost: 30, balance: 18, vipOnly: false)
        state.selection = .vip
        #expect(state.primaryButtonTitle == "开通 VIP 并解锁")
    }

    @Test
    func vipOnlyContentCannotUseCoinsOrAds() {
        let state = EpisodeUnlockFlowState(episodeNumber: 4, coinCost: 30, balance: 100, vipOnly: true)
        #expect(state.selection == .vip)
        #expect(state.canUnlockWithCoins == false)
        #expect(state.canUnlockWithAd == false)
        #expect(state.primaryButtonTitle == "开通 VIP 并解锁")
    }

    @Test
    func closingPrimaryShowsRecoveryOnceThenLeavesLockedFrame() {
        var state = EpisodeUnlockFlowState(episodeNumber: 4, coinCost: 30, balance: 18, vipOnly: false)
        #expect(state.presentation == .primary)
        state.close()
        #expect(state.presentation == .recovery)
        #expect(state.blocksPlaybackInteraction)
        state.close()
        #expect(state.presentation == .lockedFrame)
        #expect(state.blocksPlaybackInteraction)
    }
}
