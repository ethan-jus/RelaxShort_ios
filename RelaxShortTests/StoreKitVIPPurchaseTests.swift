import Foundation
import Testing
@testable import RelaxShort

@Suite(.serialized)
struct StoreKitVIPPurchaseTests {
    @Test
    func localStoreKitConfigurationProvidesAllVIPProducts() throws {
        let bundle = Bundle(for: StoreKitVIPPurchaseBundleToken.self)
        let url = try #require(bundle.url(forResource: "RelaxShort", withExtension: "storekit"))
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try #require(root["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        let configuredIDs = Set(subscriptions.compactMap { $0["productID"] as? String })
        let expectedIDs = Set(ProductID.supportedVIPSubscriptions.map(\.rawValue))

        #expect(configuredIDs == expectedIDs)
    }

    @Test
    func localStoreKitConfigurationProvidesAllCoinProducts() throws {
        let bundle = Bundle(for: StoreKitVIPPurchaseBundleToken.self)
        let url = try #require(bundle.url(forResource: "RelaxShort", withExtension: "storekit"))
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try #require(root["products"] as? [[String: Any]])
        let configuredIDs = Set(products.compactMap { $0["productID"] as? String })
        let expectedIDs = Set(ProductID.allCases.filter(\.isCoinPackage).map(\.rawValue))

        #expect(configuredIDs == expectedIDs)
    }

    @Test
    func memberCatalogUsesWeeklyMonthlyAndYearlyProducts() {
        #expect(ProductID.supportedVIPSubscriptions == [
            .vipWeekly,
            .vipMonthly,
            .vipYearly
        ])
        #expect(MemberDisplayConfig.plans.map(\.productID) == ProductID.supportedVIPSubscriptions)
    }

    @Test
    func purchaseStateTracksActiveSubscription() {
        var state = VIPPurchaseState()

        state.begin(productID: .vipMonthly)
        #expect(state.phase == .purchasing(.vipMonthly))
        #expect(state.isPurchasing)

        state.activate(productID: .vipMonthly)
        #expect(state.phase == .active(.vipMonthly))
        #expect(state.activeProductID == .vipMonthly)
        #expect(state.hasActiveSubscription)
        #expect(state.isPurchasing == false)
    }

    @Test
    func realAppleTransactionWaitsForServerDelivery() {
        var state = VIPPurchaseState()

        state.awaitServerVerification(productID: .vipMonthly)

        #expect(state.phase == .awaitingServerVerification(.vipMonthly))
        #expect(state.hasActiveSubscription == false)
    }

    @Test
    func onlyXcodeTransactionsCanGrantLocalVIP() {
        let local = ApplePurchaseReceipt(
            transactionID: "1", productID: ProductID.vipWeekly.rawValue,
            environment: "XCODE", appAccountToken: nil, coins: 0
        )
        let sandbox = ApplePurchaseReceipt(
            transactionID: "2", productID: ProductID.vipWeekly.rawValue,
            environment: "SANDBOX", appAccountToken: UUID().uuidString, coins: 0
        )
        let production = ApplePurchaseReceipt(
            transactionID: "3", productID: ProductID.vipWeekly.rawValue,
            environment: "PRODUCTION", appAccountToken: UUID().uuidString, coins: 0
        )

        #expect(local.requiresBackendVerification == false)
        #expect(sandbox.requiresBackendVerification)
        #expect(production.requiresBackendVerification)
    }

    @Test
    func cancelledPurchaseReturnsToIdleWithoutAnError() {
        var state = VIPPurchaseState()
        state.begin(productID: .vipWeekly)

        state.cancel()

        #expect(state.phase == .idle)
        #expect(state.errorMessage == nil)
    }

    @Test
    func pendingAndFailedPurchasesNeverGrantVIP() {
        var pending = VIPPurchaseState()
        pending.markPending(productID: .vipYearly)
        #expect(pending.phase == .pending(.vipYearly))
        #expect(pending.hasActiveSubscription == false)

        var failed = VIPPurchaseState()
        failed.fail(message: "Product unavailable")
        #expect(failed.phase == .failed("Product unavailable"))
        #expect(failed.errorMessage == "Product unavailable")
        #expect(failed.hasActiveSubscription == false)
    }

    @Test
    func missingStoreProductIsARealFailure() {
        let error = StoreKitPurchaseError.productUnavailable(.vipMonthly)
        #expect(error.errorDescription?.contains(ProductID.vipMonthly.rawValue) == true)
    }
}

private final class StoreKitVIPPurchaseBundleToken {}
