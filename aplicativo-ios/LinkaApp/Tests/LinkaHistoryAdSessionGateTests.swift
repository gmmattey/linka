import XCTest
@testable import LinkaApp

final class LinkaAdSessionGateTests: XCTestCase {
    func testDisabledConfigurationNeverStartsAnAdRequest() {
        var gate = LinkaAdSessionGate()

        XCTAssertFalse(gate.beginIfEligible(placement: .home, isEnabled: false, isEligibleForAds: true))
        XCTAssertFalse(gate.didAttempt)
    }

    func testPaidPlusNeverStartsAnAdRequest() {
        var gate = LinkaAdSessionGate()

        XCTAssertFalse(gate.beginIfEligible(placement: .history, isEnabled: true, isEligibleForAds: false))
        XCTAssertFalse(gate.didAttempt)
    }

    func testEligibleFreeHomeStartsAnAdRequestWithoutPriorMeasurement() {
        var gate = LinkaAdSessionGate()

        XCTAssertTrue(
            gate.beginIfEligible(
                placement: .home,
                isEnabled: true,
                isEligibleForAds: true
            )
        )
        XCTAssertTrue(gate.didAttempt)
        XCTAssertEqual(gate.placement, .home)
    }

    func testEligibleFreeStartsOnlyOnceAcrossPlacementsPerSession() {
        var gate = LinkaAdSessionGate()

        XCTAssertTrue(gate.beginIfEligible(placement: .home, isEnabled: true, isEligibleForAds: true))
        XCTAssertTrue(gate.didAttempt)
        XCTAssertEqual(gate.placement, .home)
        XCTAssertFalse(gate.beginIfEligible(placement: .history, isEnabled: true, isEligibleForAds: true))
    }

    func testMeasurementInvalidatesPendingConsentOrAdRequest() {
        var gate = LinkaAdRequestGate()
        let pendingRequest = gate.beginRequest()

        gate.invalidateForMeasurement()

        XCTAssertFalse(gate.canContinue(requestGeneration: pendingRequest))
    }

    func testOnlyTheCurrentRequestMayContinueAfterAnEarlierRequest() {
        var gate = LinkaAdRequestGate()
        let earlierRequest = gate.beginRequest()
        let currentRequest = gate.beginRequest()

        XCTAssertFalse(gate.canContinue(requestGeneration: earlierRequest))
        XCTAssertTrue(gate.canContinue(requestGeneration: currentRequest))
    }
}

#if os(iOS)
@MainActor
final class LinkaAdsCoordinatorMeasurementSuppressionTests: XCTestCase {
    func testMeasurementStartingWhileConsentPresentationIsPendingPreventsPresentationAndNativeLoad() async {
        let pause = ConsentPresentationPause()
        let recorder = AdFlowRecorder()
        let flowFinished = expectation(description: "ad flow finished")
        let coordinator = LinkaAdsCoordinator(
            dependencies: dependencies(
                pause: pause,
                recorder: recorder,
                adFlowDidFinish: { flowFinished.fulfill() }
            )
        )

        coordinator.prepareHomeAd(isEligibleForAds: true, isEntitlementResolved: true)
        await pause.waitUntilPresentationCheckpoint()

        coordinator.measurementDidStart()
        await pause.releasePresentation()
        await fulfillment(of: [flowFinished], timeout: 1)

        XCTAssertEqual(recorder.presentedSurfaces, [])
        XCTAssertEqual(recorder.nativeAdLoadStarts, 0)
    }

    func testMeasurementStartingWhilePrivacyOptionsArePendingPreventsSettingsPresentation() async {
        let pause = ConsentPresentationPause()
        let recorder = AdFlowRecorder()
        let coordinator = LinkaAdsCoordinator(dependencies: dependencies(pause: pause, recorder: recorder))
        await coordinator.refreshConsentInformation()

        let task = Task { @MainActor in
            await coordinator.presentPrivacyOptions()
        }
        await pause.waitUntilPresentationCheckpoint()

        coordinator.measurementDidStart()
        await pause.releasePresentation()
        await task.value

        XCTAssertEqual(recorder.presentedSurfaces, [])
        XCTAssertEqual(recorder.nativeAdLoadStarts, 0)
    }

    func testPaidEntitlementRevokesPendingConsent() async {
        let pause = ConsentPresentationPause()
        let recorder = AdFlowRecorder()
        let finished = expectation(description: "cancelled ad flow")
        let coordinator = LinkaAdsCoordinator(dependencies: dependencies(
            pause: pause, recorder: recorder, adFlowDidFinish: { finished.fulfill() }
        ))
        coordinator.prepareHomeAd(isEligibleForAds: true, isEntitlementResolved: true)
        await pause.waitUntilPresentationCheckpoint()
        coordinator.updateEligibility(isEligibleForAds: false, isEntitlementResolved: true)
        await pause.releasePresentation()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(recorder.presentedSurfaces.isEmpty)
        XCTAssertEqual(recorder.nativeAdLoadStarts, 0)
        XCTAssertNil(coordinator.nativeAd(for: .home))
    }

    func testPrivacyOptionsRemainAvailableAfterMeasurementEnds() async {
        let pause = ConsentPresentationPause()
        let recorder = AdFlowRecorder()
        await pause.releasePresentation()
        let coordinator = LinkaAdsCoordinator(dependencies: dependencies(pause: pause, recorder: recorder))
        await coordinator.refreshConsentInformation()
        coordinator.measurementDidStart()
        await coordinator.presentPrivacyOptions()
        XCTAssertTrue(recorder.presentedSurfaces.isEmpty)
        coordinator.measurementDidEnd()
        await coordinator.presentPrivacyOptions()
        XCTAssertEqual(recorder.presentedSurfaces, [.privacyOptions])
    }

    func testCancelledPreparationDoesNotConsumeAdAttempt() async {
        let pause = ConsentPresentationPause()
        let recorder = AdFlowRecorder()
        let firstFinished = expectation(description: "cancelled flow finishes")
        let secondFinished = expectation(description: "retry reaches consent")
        var finishedCount = 0
        var configuration = dependencies(pause: pause, recorder: recorder,
                                         adFlowDidFinish: {
            finishedCount += 1
            if finishedCount == 1 { firstFinished.fulfill() }
            else { secondFinished.fulfill() }
        })
        // No SDK initialization/request is allowed in this test.
        configuration.canRequestAds = { false }
        let coordinator = LinkaAdsCoordinator(dependencies: configuration)
        coordinator.prepareHomeAd(isEligibleForAds: true, isEntitlementResolved: true)
        await pause.waitUntilPresentationCheckpoint()
        coordinator.measurementDidStart()
        await pause.releasePresentation()
        await fulfillment(of: [firstFinished], timeout: 1)
        coordinator.measurementDidEnd()
        // The second flow must reach consent, proving cancellation did not
        // spend the request budget. Release remains open for this invocation.
        coordinator.prepareHistoryAd(isEligibleForAds: true, isEntitlementResolved: true, hasHistory: true)
        await fulfillment(of: [secondFinished], timeout: 1)
        XCTAssertEqual(recorder.presentedSurfaces, [.initialConsent])
        XCTAssertEqual(recorder.nativeAdLoadStarts, 0)
    }

    func testPromotionalEligibleFlowChecksActiveStateBeforeConsent() async {
        let pause = ConsentPresentationPause()
        let recorder = AdFlowRecorder()
        let finished = expectation(description: "flow finishes after consent")
        await pause.releasePresentation()
        var events: [String] = []
        var configuration = dependencies(pause: pause, recorder: recorder,
                                         adFlowDidFinish: { finished.fulfill() })
        configuration.isApplicationActive = {
            events.append("application active")
            return true
        }
        configuration.updateConsentInformation = {
            events.append("consent information")
            return true
        }
        configuration.canRequestAds = { false } // Never start the real SDK in unit tests.
        let coordinator = LinkaAdsCoordinator(dependencies: configuration)
        coordinator.prepareHomeAd(isEligibleForAds: true, isEntitlementResolved: true)
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(events, ["application active", "consent information"])
        XCTAssertEqual(recorder.presentedSurfaces, [.initialConsent])
    }

    func testInactiveApplicationDefersConsentAndAllowsRetryWhenActive() async {
        let pause = ConsentPresentationPause()
        let recorder = AdFlowRecorder()
        let deferred = expectation(description: "inactive flow deferred")
        let retried = expectation(description: "active flow completed")
        await pause.releasePresentation()
        var active = false
        var consentUpdates = 0
        var configuration = dependencies(pause: pause, recorder: recorder, adFlowDidFinish: {
            if active { retried.fulfill() } else { deferred.fulfill() }
        })
        configuration.isApplicationActive = { active }
        configuration.updateConsentInformation = { consentUpdates += 1; return true }
        configuration.canRequestAds = { false }
        let coordinator = LinkaAdsCoordinator(dependencies: configuration)
        coordinator.prepareHomeAd(isEligibleForAds: true, isEntitlementResolved: true)
        await fulfillment(of: [deferred], timeout: 1)
        XCTAssertEqual(consentUpdates, 0)
        active = true
        coordinator.prepareHomeAd(isEligibleForAds: true, isEntitlementResolved: true)
        await fulfillment(of: [retried], timeout: 1)
        XCTAssertEqual(consentUpdates, 1)
    }

    func testMeasurementStartedDuringConsentUpdatePreventsPresentation() async {
        let pause = ConsentPresentationPause()
        let recorder = AdFlowRecorder()
        let finished = expectation(description: "consent update invalidated")
        var consentUpdates = 0
        var configuration = dependencies(pause: pause, recorder: recorder,
                                         adFlowDidFinish: { finished.fulfill() })
        configuration.updateConsentInformation = {
            consentUpdates += 1
            await pause.reachPresentationCheckpoint()
            await pause.waitForRelease()
            return true
        }
        let coordinator = LinkaAdsCoordinator(dependencies: configuration)
        coordinator.prepareHomeAd(isEligibleForAds: true, isEntitlementResolved: true)
        await pause.waitUntilPresentationCheckpoint()
        coordinator.measurementDidStart()
        await pause.releasePresentation()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(consentUpdates, 1)
        XCTAssertTrue(recorder.presentedSurfaces.isEmpty)
        XCTAssertEqual(recorder.nativeAdLoadStarts, 0)
    }

    private func dependencies(
        pause: ConsentPresentationPause,
        recorder: AdFlowRecorder,
        adFlowDidFinish: @escaping @MainActor () -> Void = {}
    ) -> LinkaAdsCoordinatorDependencies {
        LinkaAdsCoordinatorDependencies(
            isEnabled: { true },
            isApplicationActive: { true },
            updateConsentInformation: { true },
            presentConsentSurface: { surface, permit in
                await pause.reachPresentationCheckpoint()
                await pause.waitForRelease()
                guard permit.allowsPresentation() else { return }
                recorder.presentedSurfaces.append(surface)
            },
            canRequestAds: { true },
            privacyOptionsRequired: { true },
            nativeAdLoadWillStart: {
                recorder.nativeAdLoadStarts += 1
            },
            adFlowDidFinish: adFlowDidFinish
        )
    }
}

@MainActor
private final class AdFlowRecorder {
    var presentedSurfaces: [LinkaAdConsentSurface] = []
    var nativeAdLoadStarts = 0
}

private actor ConsentPresentationPause {
    private var presentationWasReached = false
    private var wasReleased = false
    private var checkpointWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func reachPresentationCheckpoint() {
        presentationWasReached = true
        let waiters = checkpointWaiters
        checkpointWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilPresentationCheckpoint() async {
        guard !presentationWasReached else { return }
        await withCheckedContinuation { checkpointWaiters.append($0) }
    }

    func waitForRelease() async {
        guard !wasReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func releasePresentation() {
        wasReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
#endif
