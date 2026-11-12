import XCTest
@testable import LinkaAppIntents
import LinkaEntitlements

final class LinkaAppIntentsTests: XCTestCase {
    func testExecutorRoutesRequestedAction() async throws {
        let executor = LinkaAppIntentExecutor { action in
            LinkaSystemActionResponse(action: action)
        }

        let response = try await executor.execute(.openHistory)

        XCTAssertEqual(response.action, .openHistory)
        XCTAssertNil(response.value)
    }

    func testExecutorRejectsMismatchedResponse() async {
        let executor = LinkaAppIntentExecutor { _ in
            LinkaSystemActionResponse(action: .startSpeedTest)
        }

        do {
            _ = try await executor.execute(.openHistory)
            XCTFail("Expected mismatched response to fail")
        } catch let error as LinkaAppIntentExecutionError {
            XCTAssertEqual(
                error,
                .mismatchedResponse(
                    expected: .openHistory,
                    actual: .startSpeedTest
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLatestResultRequiresNonEmptyValue() async {
        let executor = LinkaAppIntentExecutor { action in
            LinkaSystemActionResponse(action: action, value: "   ")
        }

        do {
            _ = try await executor.execute(.getLatestResult)
            XCTFail("Expected missing latest result value to fail")
        } catch let error as LinkaAppIntentExecutionError {
            XCTAssertEqual(error, .missingValue(action: .getLatestResult))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLatestResultAcceptsValue() async throws {
        let executor = LinkaAppIntentExecutor { action in
            LinkaSystemActionResponse(
                action: action,
                value: "487 Mbps de download, 92 Mbps de upload, 12 ms de latência"
            )
        }

        let response = try await executor.execute(.getLatestResult)

        XCTAssertEqual(response.action, .getLatestResult)
        XCTAssertEqual(
            response.value,
            "487 Mbps de download, 92 Mbps de upload, 12 ms de latência"
        )
    }

    func testNonValueActionsDoNotRequirePayload() async throws {
        let executor = LinkaAppIntentExecutor { action in
            LinkaSystemActionResponse(action: action)
        }

        for action in [
            LinkaSystemAction.startSpeedTest,
            .openLatestMeasurement,
            .openHistory,
            .openPurchase
        ] {
            let response = try await executor.execute(action)
            XCTAssertEqual(response.action, action)
        }
    }

    func testUnconfiguredExecutorFailsClosed() async {
        do {
            _ = try await LinkaAppIntentExecutor.unconfigured.execute(.startSpeedTest)
            XCTFail("Expected unconfigured executor to fail")
        } catch let error as LinkaAppIntentExecutionError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIntentOpenBehaviorMatchesAction() {
        XCTAssertTrue(StartSpeedTestIntent.openAppWhenRun)
        XCTAssertTrue(OpenLatestMeasurementIntent.openAppWhenRun)
        XCTAssertTrue(OpenHistoryIntent.openAppWhenRun)
        XCTAssertTrue(OpenPurchaseIntent.openAppWhenRun)
        XCTAssertFalse(GetLatestResultIntent.openAppWhenRun)
        XCTAssertFalse(MeasureNetworkSilentlyIntent.openAppWhenRun)
    }

    // MARK: - entitlementGated

    func testEntitlementGatedExecutorDeniesFreePlanWithoutCallingTheWrappedExecutor() async {
        let wrappedWasCalled = CallFlag()
        let wrapped = LinkaAppIntentExecutor { action in
            await wrappedWasCalled.markCalled()
            return LinkaSystemActionResponse(action: action)
        }
        let gated = LinkaAppIntentExecutor.entitlementGated(
            wrapping: wrapped,
            snapshot: { .free }
        )

        do {
            _ = try await gated.execute(.startSpeedTest)
            XCTFail("Expected LinkaAppIntentExecutionError.notEntitled")
        } catch let error as LinkaAppIntentExecutionError {
            XCTAssertEqual(error, .notEntitled(action: .startSpeedTest))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let wasCalled = await wrappedWasCalled.value
        XCTAssertFalse(wasCalled, "O executor real não deve rodar sem entitlement.")
    }

    func testEntitlementGatedExecutorDelegatesForActivePlus() async throws {
        let wrapped = LinkaAppIntentExecutor { action in
            LinkaSystemActionResponse(action: action)
        }
        let gated = LinkaAppIntentExecutor.entitlementGated(
            wrapping: wrapped,
            snapshot: { .plus(status: .active, source: .subscription) }
        )

        let response = try await gated.execute(.openHistory)

        XCTAssertEqual(response.action, .openHistory)
    }

    func testEntitlementGatedExecutorDeniesExpiredPlus() async {
        let wrapped = LinkaAppIntentExecutor { action in
            LinkaSystemActionResponse(action: action)
        }
        let gated = LinkaAppIntentExecutor.entitlementGated(
            wrapping: wrapped,
            snapshot: {
                .plus(
                    status: .active,
                    source: .subscription,
                    validUntil: Date(timeIntervalSince1970: 0)
                )
            }
        )

        do {
            _ = try await gated.execute(.openHistory)
            XCTFail("Expected LinkaAppIntentExecutionError.notEntitled")
        } catch let error as LinkaAppIntentExecutionError {
            XCTAssertEqual(error, .notEntitled(action: .openHistory))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor CallFlag {
    private(set) var value = false

    func markCalled() {
        value = true
    }
}
