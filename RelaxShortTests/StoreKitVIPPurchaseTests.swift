import Foundation
import StoreKitTest
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
    }

    @Test
    func memberContractMapsServerPlansBenefitsPromotionsAndLegalLinks() throws {
        let json = """
        {
          "background_posters": [],
          "member_only_dramas": [],
          "plans": [{
            "product_code": "vip_weekly",
            "store_product_id": "com.relaxshort.vip.weekly",
            "title_key": "member.plan.weekly",
            "detail_key": "member.plan.weekly_detail",
            "sort_order": 10,
            "promotion": {
              "campaign_code": "weekly_intro_3_periods",
              "offer_type": "introductory",
              "payment_mode": "pay_as_you_go",
              "period_unit": "week",
              "period_value": 1,
              "period_count": 3,
              "badge_key": "member.discount",
              "title_key": "member.promotion.weekly_intro",
              "starts_at_epoch_seconds": 1782864000,
              "ends_at_epoch_seconds": 1788220799
            }
          }],
          "benefits": [{
            "code": "unlimited",
            "icon": "infinity",
            "title_key": "member.benefit.unlimited",
            "detail_key": "member.benefit.unlimited_detail"
          }],
          "legal_links": {
            "terms_url": "https://www.relaxshort.com/terms-placeholder",
            "privacy_url": "https://www.relaxshort.com/privacy-placeholder"
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(MemberResponseDTO.self, from: Data(json.utf8))

        let content = RealMemberRepository.map(dto: dto)

        #expect(content.plans.map(\.productID) == [.vipWeekly])
        #expect(content.plans.first?.promotion?.campaignCode == "weekly_intro_3_periods")
        #expect(content.benefits.map(\.id) == ["unlimited"])
        #expect(content.legalLinks?.termsURL.host == "www.relaxshort.com")
    }

    @Test
    func serverPromotionRequiresActiveWindowAndAppleOffer() {
        let promotion = MemberPromotion(
            campaignCode: "weekly_intro_3_periods",
            offerType: .introductory,
            paymentMode: .payAsYouGo,
            periodUnit: .week,
            periodValue: 1,
            periodCount: 3,
            badgeKey: "member.discount",
            titleKey: "member.promotion.weekly_intro",
            startsAt: Date(timeIntervalSince1970: 100),
            endsAt: Date(timeIntervalSince1970: 200)
        )

        #expect(promotion.canDisplay(
            at: Date(timeIntervalSince1970: 150),
            hasMatchingStoreOffer: true
        ))
        #expect(!promotion.canDisplay(
            at: Date(timeIntervalSince1970: 201),
            hasMatchingStoreOffer: true
        ))
        #expect(!promotion.canDisplay(
            at: Date(timeIntervalSince1970: 150),
            hasMatchingStoreOffer: false
        ))
    }

    @Test
    func serverPromotionMustMatchStoreKitPaymentTerms() {
        let promotion = MemberPromotion(
            campaignCode: "weekly_intro_3_periods",
            offerType: .introductory,
            paymentMode: .payAsYouGo,
            periodUnit: .week,
            periodValue: 1,
            periodCount: 3,
            badgeKey: "member.discount",
            titleKey: "member.promotion.weekly_intro",
            startsAt: Date(timeIntervalSince1970: 100),
            endsAt: Date(timeIntervalSince1970: 200)
        )
        let expectedOffer = VIPIntroductoryOfferDisplay(
            displayPrice: "$12.99",
            paymentMode: .payAsYouGo,
            periodUnit: .week,
            periodValue: 1,
            periodCount: 3
        )
        let freeTrial = VIPIntroductoryOfferDisplay(
            displayPrice: "$0",
            paymentMode: .freeTrial,
            periodUnit: .week,
            periodValue: 1,
            periodCount: 3
        )

        #expect(expectedOffer.matches(promotion))
        #expect(!freeTrial.matches(promotion))
    }

    @Test
    func weeklyLocalStoreKitUsesRealThreePeriodIntroductoryOffer() throws {
        let bundle = Bundle(for: StoreKitVIPPurchaseBundleToken.self)
        let url = try #require(bundle.url(forResource: "RelaxShort", withExtension: "storekit"))
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try #require(root["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        let weekly = try #require(subscriptions.first {
            $0["productID"] as? String == ProductID.vipWeekly.rawValue
        })
        let offer = try #require(weekly["introductoryOffer"] as? [String: Any])

        #expect(weekly["displayPrice"] as? String == "19.99")
        #expect(offer["displayPrice"] as? String == "12.99")
        #expect(offer["paymentMode"] as? String == "PayAsYouGo")
        #expect(offer["periodCount"] as? Int == 3)
    }

    @Test
    @MainActor
    func localStoreKitConfigurationLoadsInStoreKitTest() throws {
        let session = try SKTestSession(
            configurationFileNamed: "RelaxShort"
        )
        session.resetToDefaultState()
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

    @Test
    @MainActor
    func memberPriceDoesNotInventFallbackCurrencyBeforeStoreKitLoads() {
        let manager = StoreKitManager()

        #expect(manager.storeDisplayPrice(for: .vipWeekly) == nil)
    }

    @Test
    func memberPurchaseRequiresLegalLinksAndStorePrice() {
        #expect(!MemberPurchasePolicy.canPurchase(
            hasPlan: true,
            hasStorePrice: true,
            hasLegalLinks: false
        ))
        #expect(MemberPurchasePolicy.canPurchase(
            hasPlan: true,
            hasStorePrice: true,
            hasLegalLinks: true
        ))
    }

    @Test
    func restoreAndRefreshKeepVerifiedGracePeriodEntitlement() {
        #expect(StoreKitEntitlementPolicy.shouldKeepCurrentEntitlement(
            revocationDate: nil,
            expirationDate: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 200)
        ))
        #expect(!StoreKitEntitlementPolicy.shouldKeepCurrentEntitlement(
            revocationDate: Date(timeIntervalSince1970: 150),
            expirationDate: nil,
            now: Date(timeIntervalSince1970: 200)
        ))
    }
}

private final class StoreKitVIPPurchaseBundleToken {}
