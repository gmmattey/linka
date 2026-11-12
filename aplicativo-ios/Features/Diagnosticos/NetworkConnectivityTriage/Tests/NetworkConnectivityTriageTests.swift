import XCTest
@testable import NetworkConnectivityTriage

final class NetworkConnectivityTriageTests: XCTestCase {
    func testUnavailablePathReportsOnlyTheObservedFact() {
        let report = ConnectivityTriageClassifier.classify(
            ConnectivityPathSnapshot(status: .unavailable, interface: .unknown)
        )
        XCTAssertEqual(report.outcome, .noNetworkPath)
        XCTAssertEqual(report.path.interface, .unknown)
    }

    func testSatisfiedPathWithSuccessfulProbeReportsReachability() {
        let report = ConnectivityTriageClassifier.classify(
            ConnectivityPathSnapshot(status: .satisfied, interface: .cellular),
            probes: [.success]
        )
        XCTAssertEqual(report.outcome, .internetReachable)
        XCTAssertEqual(report.path.interface, .cellular)
    }

    func testRequiresConnectionIsInconclusive() {
        let report = ConnectivityTriageClassifier.classify(
            ConnectivityPathSnapshot(status: .requiresConnection, interface: .wifi)
        )
        XCTAssertEqual(report.outcome, .inconclusive)
    }

    func testServiceUsesInjectedProvider() async {
        let service = NetworkConnectivityTriageService(
            pathProvider: StubPathProvider(value: ConnectivityPathSnapshot(status: .unavailable))
        )
        let report = try! await service.run()
        XCTAssertEqual(report.outcome, .noNetworkPath)
    }

    func testConsistentDNSFailuresAreReportedAsObservedResolutionFailure() {
        let report = ConnectivityTriageClassifier.classify(
            ConnectivityPathSnapshot(status: .satisfied),
            probes: [.dnsFailure, .dnsFailure]
        )
        XCTAssertEqual(report.outcome, .dnsResolutionUnavailable)
    }

    func testRedirectIsOnlyACaptivePortalSuspicion() {
        let report = ConnectivityTriageClassifier.classify(
            ConnectivityPathSnapshot(status: .satisfied),
            probes: [.redirected]
        )
        XCTAssertEqual(report.outcome, .captivePortalSuspected)
    }

    func testServiceClassifiesInjectedHTTPSOutcomesWithoutUsingRealNetwork() async throws {
        let service = NetworkConnectivityTriageService(
            pathProvider: StubPathProvider(value: ConnectivityPathSnapshot(status: .satisfied)),
            httpProbe: StubHTTPProbe(outcome: .timeout),
            endpoints: [URL(string: "https://example.invalid/health")!]
        )
        let report = try await service.run()
        XCTAssertEqual(report.outcome, .inconclusive)
    }

    func testRedirectDelegateCancelsDestinationRequest() {
        let delegate = RedirectBlockingDelegate()
        let session = URLSession(configuration: .ephemeral)
        let original = URL(string: "https://probe.linka.test/health")!
        let destination = URL(string: "https://portal.example.test/login")!
        let task = session.dataTask(with: URLRequest(url: original))
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: ["Location": destination.absoluteString])!
        let selectedRequest = RequestBox()

        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: destination)) {
            selectedRequest.value = $0
        }

        XCTAssertNil(selectedRequest.value)
        XCTAssertTrue(delegate.didBlockRedirect)
    }
}

private struct StubHTTPProbe: ConnectivityHTTPProbing {
    let outcome: ConnectivityHTTPProbeOutcome
    func probe(_ endpoint: URL) async throws -> ConnectivityHTTPProbeOutcome { outcome }
}

private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    var value: URLRequest? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}


private struct StubPathProvider: ConnectivityPathProviding {
    let value: ConnectivityPathSnapshot
    func snapshot() async -> ConnectivityPathSnapshot { value }
}
