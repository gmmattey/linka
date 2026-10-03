import XCTest
@testable import LinkaEntitlements

final class LinkaEntitlementsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testResolverGrantsAdvancedWiFiWithoutPurchaseDuringPromotionAndKeepsAds() {
        let date = LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(-60)
        let snapshot = LinkaEntitlementSnapshotResolver.resolve(at: date, promotionSupported: true)
        XCTAssertEqual(snapshot.source, .promotion)
        XCTAssertEqual(snapshot.validUntil, LinkaTemporaryFreeOffer.endsAt)
        XCTAssertTrue(LinkaEntitlementPolicy.hasAccess(to: .advancedWiFiDiagnostics, snapshot: snapshot, at: date))
        XCTAssertTrue(LinkaEntitlementPolicy.shouldShowAds(for: snapshot, at: date))
    }

    func testResolverPrefersVerifiedPurchaseDuringPromotion() {
        let date = LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(-60)
        let purchase = LinkaEntitlementSnapshot.plus(status: .active, source: .subscription,
                                                   validUntil: date.addingTimeInterval(3600))
        let snapshot = LinkaEntitlementSnapshotResolver.resolve(verifiedPurchase: purchase, at: date,
                                                               promotionSupported: true)
        XCTAssertEqual(snapshot, purchase)
        XCTAssertTrue(LinkaEntitlementPolicy.hasAccess(to: .advancedWiFiDiagnostics, snapshot: snapshot, at: date))
        XCTAssertFalse(LinkaEntitlementPolicy.shouldShowAds(for: snapshot, at: date))
    }

    func testResolverReturnsFreeAfterPromotionWithoutPurchase() {
        let date = LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(1)
        let snapshot = LinkaEntitlementSnapshotResolver.resolve(at: date, promotionSupported: true)
        XCTAssertEqual(snapshot, .free)
        XCTAssertFalse(LinkaEntitlementPolicy.hasAccess(to: .advancedWiFiDiagnostics, snapshot: snapshot, at: date))
    }

    func testResolverDoesNotPromoteUnsupportedPlatforms() {
        let date = LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(-60)
        XCTAssertEqual(LinkaEntitlementSnapshotResolver.resolve(at: date, promotionSupported: false), .free)
        #if os(macOS)
        XCTAssertEqual(LinkaEntitlementSnapshotResolver.resolve(at: date), .free)
        #endif
    }

    func testResolverDoesNotTreatExpiredPurchaseAsPaidPlus() {
        let date = LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(-60)
        let purchase = LinkaEntitlementSnapshot.plus(status: .active, source: .subscription, validUntil: date)
        let snapshot = LinkaEntitlementSnapshotResolver.resolve(verifiedPurchase: purchase, at: date,
                                                               promotionSupported: true)
        XCTAssertEqual(snapshot.source, .promotion)
        XCTAssertTrue(LinkaEntitlementPolicy.shouldShowAds(for: snapshot, at: date))
    }

    func testFreeAlwaysAllowsSpeedTestAndHistoryAndDeniesPremium() {
        XCTAssertTrue(
            LinkaEntitlementPolicy.hasAccess(
                to: .speedTest,
                snapshot: .free,
                at: now
            )
        )
        XCTAssertTrue(
            LinkaEntitlementPolicy.hasAccess(
                to: .history,
                snapshot: .free,
                at: now
            )
        )

        for capability in [
            LinkaCapability.insights,
            .assist,
            .appleIntegrations,
            .advancedWiFiDiagnostics,
            .expertMode,
            .usageDiagnostics
        ] {
            let decision = LinkaEntitlementPolicy.decision(
                for: capability,
                snapshot: .free,
                at: now
            )
            XCTAssertFalse(decision.isGranted)
            XCTAssertEqual(decision.reason, .planDoesNotIncludeCapability)
        }
    }

    func testTemporaryFreeOfferHasAnInclusiveEndDate() {
        let duringOffer = LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(-1)
        XCTAssertTrue(LinkaTemporaryFreeOffer.isWithinOfferPeriod(at: duringOffer))
        XCTAssertTrue(LinkaTemporaryFreeOffer.isWithinOfferPeriod(at: LinkaTemporaryFreeOffer.endsAt))
        XCTAssertFalse(LinkaTemporaryFreeOffer.isWithinOfferPeriod(at: LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(1)))
    }

    func testPromotionKeepsPremiumFeaturesButIsEligibleForAds() {
        let promotion = LinkaEntitlementSnapshot.plus(
            status: .active,
            source: .promotion,
            validUntil: now.addingTimeInterval(60)
        )

        XCTAssertTrue(LinkaEntitlementPolicy.hasAccess(to: .assist, snapshot: promotion, at: now))
        XCTAssertEqual(LinkaEntitlementPolicy.adEligibility(for: promotion, at: now), .eligibleFree)
        XCTAssertTrue(LinkaEntitlementPolicy.shouldShowAds(for: promotion, at: now))
    }

    func testPaidPlusIsNotEligibleForAds() {
        let paid = LinkaEntitlementSnapshot.plus(
            status: .active,
            source: .subscription,
            validUntil: now.addingTimeInterval(60)
        )

        XCTAssertEqual(LinkaEntitlementPolicy.adEligibility(for: paid, at: now), .paidPlus)
        XCTAssertFalse(LinkaEntitlementPolicy.shouldShowAds(for: paid, at: now))
    }

    func testUnresolvedPlusDoesNotRequestAds() {
        let snapshot = LinkaEntitlementSnapshot.plus(status: .unknown, source: .subscription)
        XCTAssertEqual(LinkaEntitlementPolicy.adEligibility(for: snapshot, at: now), .unresolvedEntitlement)
    }

    func testExpiredPaidPlusReturnsToAds() {
        let snapshot = LinkaEntitlementSnapshot.plus(status: .active, source: .subscription, validUntil: now)
        XCTAssertTrue(LinkaEntitlementPolicy.shouldShowAds(for: snapshot, at: now))
    }

    func testActivePlusAllowsPremiumCapabilities() {
        let snapshot = LinkaEntitlementSnapshot.plus(
            status: .active,
            source: .subscription,
            validUntil: now.addingTimeInterval(3_600)
        )

        for capability in LinkaCapability.allCases {
            XCTAssertTrue(
                LinkaEntitlementPolicy.hasAccess(
                    to: capability,
                    snapshot: snapshot,
                    at: now
                )
            )
        }
    }

    func testUnknownInactiveAndExpiredFailClosedForPremium() {
        let cases: [(LinkaEntitlementStatus, LinkaAccessReason)] = [
            (.unknown, .unknownEntitlement),
            (.inactive, .inactiveEntitlement),
            (.expired, .expiredEntitlement)
        ]

        for (status, reason) in cases {
            let snapshot = LinkaEntitlementSnapshot.plus(
                status: status,
                source: .subscription
            )
            let decision = LinkaEntitlementPolicy.decision(
                for: .insights,
                snapshot: snapshot,
                at: now
            )
            XCTAssertFalse(decision.isGranted)
            XCTAssertEqual(decision.reason, reason)
        }
    }

    func testExpirationDateOverridesActiveStatus() {
        let snapshot = LinkaEntitlementSnapshot.plus(
            status: .active,
            source: .subscription,
            validUntil: now.addingTimeInterval(-1)
        )

        let decision = LinkaEntitlementPolicy.decision(
            for: .assist,
            snapshot: snapshot,
            at: now
        )

        XCTAssertFalse(decision.isGranted)
        XCTAssertEqual(decision.reason, .expiredEntitlement)
    }

    func testTrialPromotionAndLifetimeCanGrantPlus() {
        let sources: [LinkaEntitlementSource] = [.trial, .promotion, .lifetime]

        for source in sources {
            let snapshot = LinkaEntitlementSnapshot.plus(
                status: .active,
                source: source,
                validUntil: source == .lifetime ? nil : now.addingTimeInterval(3_600)
            )

            XCTAssertTrue(
                LinkaEntitlementPolicy.hasAccess(
                    to: .insights,
                    snapshot: snapshot,
                    at: now
                )
            )
        }
    }

    func testInvalidSnapshotFailsClosedForPremiumButKeepsSpeedTest() {
        let invalid = LinkaEntitlementSnapshot(
            plan: .plus,
            status: .active,
            source: .free
        )

        let premiumDecision = LinkaEntitlementPolicy.decision(
            for: .insights,
            snapshot: invalid,
            at: now
        )
        XCTAssertFalse(premiumDecision.isGranted)
        XCTAssertEqual(premiumDecision.reason, .invalidSnapshot)

        let speedDecision = LinkaEntitlementPolicy.decision(
            for: .speedTest,
            snapshot: invalid,
            at: now
        )
        XCTAssertTrue(speedDecision.isGranted)
        XCTAssertEqual(speedDecision.reason, .includedInFree)
    }

    func testLifetimeCannotCarryExpirationDate() {
        let invalid = LinkaEntitlementSnapshot.plus(
            status: .active,
            source: .lifetime,
            validUntil: now.addingTimeInterval(3_600)
        )

        let decision = LinkaEntitlementPolicy.decision(
            for: .appleIntegrations,
            snapshot: invalid,
            at: now
        )

        XCTAssertFalse(decision.isGranted)
        XCTAssertEqual(decision.reason, .invalidSnapshot)
    }

    func testStaticProviderUsesCentralPolicy() async {
        let provider = StaticLinkaEntitlementProvider(
            snapshot: .plus(
                status: .active,
                source: .promotion,
                validUntil: now.addingTimeInterval(60)
            )
        )

        let activeAccess = await provider.hasAccess(to: .assist, at: now)
        let expiredAccess = await provider.hasAccess(
            to: .assist,
            at: now.addingTimeInterval(61)
        )

        XCTAssertTrue(activeAccess)
        XCTAssertFalse(expiredAccess)
    }
}

// MARK: - StoreKitEntitlementProvider

@MainActor
final class StoreKitEntitlementProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)

    func testIsEntitledOnlyForActivePlus() {
        XCTAssertFalse(StoreKitEntitlementProvider.isEntitled(.free))
        XCTAssertFalse(
            StoreKitEntitlementProvider.isEntitled(
                .plus(status: .expired, source: .subscription, validUntil: now)
            )
        )
        XCTAssertTrue(
            StoreKitEntitlementProvider.isEntitled(
                .plus(status: .active, source: .subscription, validUntil: now.addingTimeInterval(60))
            )
        )
    }

    func testProductStartsNilBeforeAnyLoadResolves() {
        let now = self.now
        let provider = StoreKitEntitlementProvider(now: { now })
        XCTAssertEqual(provider.productState, .loading)
        XCTAssertEqual(provider.snapshot, .free)
    }

    func testTemporaryFreeOfferStartsAsPromotionWithoutStoreKitPurchase() {
        let provider = StoreKitEntitlementProvider(now: {
            LinkaTemporaryFreeOffer.endsAt.addingTimeInterval(-1)
        })

        #if os(iOS)
        XCTAssertEqual(provider.snapshot.plan, .plus)
        XCTAssertEqual(provider.snapshot.status, .active)
        XCTAssertEqual(provider.snapshot.source, .promotion)
        XCTAssertEqual(provider.snapshot.validUntil, LinkaTemporaryFreeOffer.endsAt)
        #else
        XCTAssertEqual(provider.snapshot, .free)
        #endif
    }

    func testLoadProductWithAnUnknownIDResolvesToNilProductAndStopsLoading() async {
        let unknownProductID = "com.linka.does.not.exist.\(UUID().uuidString)"
        let provider = StoreKitEntitlementProvider(
            productID: unknownProductID
        )

        await provider.loadProduct()

        XCTAssertEqual(provider.productState, .unavailable)
    }

    func testHandleUserCancelledKeepsFreeSnapshotAndReportsCancellation() async throws {
        let provider = StoreKitEntitlementProvider()

        let outcome = try await provider.handle(.userCancelled)

        XCTAssertEqual(outcome, .userCancelled)
        XCTAssertEqual(provider.snapshot, .free)
    }

    func testHandlePendingKeepsFreeSnapshotAndReportsPending() async throws {
        let provider = StoreKitEntitlementProvider()

        let outcome = try await provider.handle(.pending)

        XCTAssertEqual(outcome, .pending)
        XCTAssertEqual(provider.snapshot, .free)
    }

    #if DEBUG
    func testDebugForcePlusAndResetRoundTrip() {
        let provider = StoreKitEntitlementProvider()
        XCTAssertEqual(provider.snapshot, .free)

        provider.debugForcePlus()
        XCTAssertEqual(provider.snapshot.plan, .plus)
        XCTAssertEqual(provider.snapshot.status, .active)
        XCTAssertEqual(provider.snapshot.source, .promotion)

        provider.debugResetToFree()
        XCTAssertEqual(provider.snapshot, .free)
    }
    #endif

    func testRefreshSnapshotFailsAndIsNotEntitledWithoutAnyKnownPurchase() async {
        let provider = StoreKitEntitlementProvider()

        await provider.refreshSnapshot()

        XCTAssertEqual(provider.snapshot, .free)
        XCTAssertFalse(StoreKitEntitlementProvider.isEntitled(provider.snapshot))
    }

    func testLinkaStoreErrorCasesAreEquatableAndCarryTheirProductID() {
        XCTAssertEqual(LinkaStoreError.productNotFound("a"), .productNotFound("a"))
        XCTAssertNotEqual(LinkaStoreError.productNotFound("a"), .productNotFound("b"))
        XCTAssertNotEqual(LinkaStoreError.productNotFound("a"), .verificationFailed)
        XCTAssertEqual(LinkaStoreError.verificationFailed, .verificationFailed)
    }

    func testPurchaseThrowsProductNotFoundForAnUnknownProductID() async {
        let unknownProductID = "com.linka.does.not.exist.\(UUID().uuidString)"
        let provider = StoreKitEntitlementProvider(
            productID: unknownProductID
        )

        do {
            _ = try await provider.purchase()
            XCTFail("esperava que purchase() lançasse LinkaStoreError.productNotFound")
        } catch let error as LinkaStoreError {
            XCTAssertEqual(error, .productNotFound(unknownProductID))
        } catch {
            XCTFail("esperava LinkaStoreError, recebeu \(error)")
        }
    }
}
