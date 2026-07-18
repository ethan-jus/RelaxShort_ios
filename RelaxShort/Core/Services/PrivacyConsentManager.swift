import Foundation
import AppTrackingTransparency
import GoogleMobileAds
import PangleAdapter
import UserMessagingPlatform

/// 统一管理 UMP 同意流程和广告 SDK 启动时序。
///
/// ATT 的地区说明与系统弹窗由 AdMob 后台配置的 UMP IDFA message 驱动，
/// 客户端只在 UMP 明确允许请求广告后初始化 Mobile Ads。
@MainActor
final class PrivacyConsentManager: ObservableObject {
    static let shared = PrivacyConsentManager()

    @Published private(set) var isPrivacyOptionsRequired = false
    @Published private(set) var lastErrorMessage: String?

    private var didStartMobileAds = false
    private var isGatheringConsent = false

    private init() {}

    func gatherConsentAndStartAds() async {
        guard !isGatheringConsent else { return }
        isGatheringConsent = true
        defer { isGatheringConsent = false }

        let parameters = UMPRequestParameters()
        let updateError = await requestConsentInfoUpdate(with: parameters)
        refreshPrivacyOptionsRequirement()

        if let updateError {
            lastErrorMessage = updateError.localizedDescription
            Logger.store.warning("UMP consent update failed: \(updateError.localizedDescription)")
            startMobileAdsIfAllowed()
            return
        }

        do {
            if let formError = await loadAndPresentConsentFormIfRequired() {
                throw formError
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            Logger.store.warning("UMP consent form failed: \(error.localizedDescription)")
        }

        refreshPrivacyOptionsRequirement()
        startMobileAdsIfAllowed()
    }

    func presentPrivacyOptions() async {
        do {
            if let formError = await presentPrivacyOptionsForm() {
                throw formError
            }
            lastErrorMessage = nil
            refreshPrivacyOptionsRequirement()
        } catch {
            lastErrorMessage = error.localizedDescription
            Logger.store.warning("UMP privacy options failed: \(error.localizedDescription)")
        }
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    private func requestConsentInfoUpdate(
        with parameters: UMPRequestParameters
    ) async -> Error? {
        await withCheckedContinuation { continuation in
            UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(
                with: parameters
            ) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func loadAndPresentConsentFormIfRequired() async -> Error? {
        await withCheckedContinuation { continuation in
            UMPConsentForm.loadAndPresentIfRequired(from: nil) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func presentPrivacyOptionsForm() async -> Error? {
        await withCheckedContinuation { continuation in
            UMPConsentForm.presentPrivacyOptionsForm(from: nil) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func refreshPrivacyOptionsRequirement() {
        isPrivacyOptionsRequired =
            UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
    }

    private func startMobileAdsIfAllowed() {
        guard UMPConsentInformation.sharedInstance.canRequestAds else {
            Logger.store.info("UMP has not allowed ad requests")
            return
        }
        guard !didStartMobileAds else { return }
        didStartMobileAds = true

        let allowsTracking = ATTrackingManager.trackingAuthorizationStatus == .authorized
        GADMediationAdapterPangle.setPAConsent(allowsTracking ? 1 : 0)

        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "00008130-001128D23A2A001C"
        ]
        MobileAds.shared.start { _ in
            Task { @MainActor in
                Logger.store.info("AdMob SDK initialized after UMP consent")
                RealAdService.shared.isSDKReady = true
                await RealAdService.shared.prepareAds()
            }
        }
    }
}
