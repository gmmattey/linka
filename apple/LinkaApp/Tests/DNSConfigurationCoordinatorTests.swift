import XCTest
import NetworkDNSBenchmark
@testable import LinkaApp

@MainActor
final class DNSConfigurationCoordinatorTests: XCTestCase {
    func testConnectionChangeCancelsDNSBenchmarkSession() {
        let coordinator = DNSBenchmarkCoordinator()
        coordinator.connectionDidChange()
        XCTAssertEqual(coordinator.state, .cancelled)
    }

    func testCreateReloadsAndOnlyReportsActiveAfterManagerConfirms() async {
        let fake = FakeDNSConfigurationManager(statuses: [.awaitingActivation(providerName: "Cloudflare")])
        let coordinator = DNSConfigurationCoordinator(manager: fake)

        await coordinator.create(provider: DNSProviderCatalog.all[0])

        XCTAssertEqual(fake.createdProviderID, "cloudflare")
        XCTAssertEqual(coordinator.status, .awaitingActivation(providerName: "Cloudflare"))
    }

    func testRemoveReloadsConfigurationStatus() async {
        let fake = FakeDNSConfigurationManager(statuses: [.none])
        let coordinator = DNSConfigurationCoordinator(manager: fake)

        await coordinator.remove()

        XCTAssertTrue(fake.didRemove)
        XCTAssertEqual(coordinator.status, .none)
    }

    func testConfigurationFailureNeverBecomesActive() async {
        let fake = FakeDNSConfigurationManager(error: TestError.failed)
        let coordinator = DNSConfigurationCoordinator(manager: fake)

        await coordinator.create(provider: DNSProviderCatalog.all[0])

        XCTAssertEqual(coordinator.status, .failed)
    }

    func testDeadlineTimeoutStopsUnderlyingResource() async {
        let recorder = StopRecorder()
        do {
            _ = try await DNSRequestDeadline.run(timeout: .milliseconds(1), onStop: {
                recorder.stop()
            }) {
                try await Task.sleep(for: .seconds(30))
                return Data()
            }
            XCTFail("Expected timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertGreaterThanOrEqual(recorder.stopCount, 1)
    }

    func testDeadlineCancellationStopsUnderlyingResource() async {
        let recorder = StopRecorder()
        let task = Task {
            try await DNSRequestDeadline.run(timeout: .seconds(30), onStop: {
                recorder.stop()
            }) {
                try await Task.sleep(for: .seconds(30))
                return Data()
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertGreaterThanOrEqual(recorder.stopCount, 1)
    }
}

private enum TestError: Error { case failed }

private final class StopRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func stop() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class FakeDNSConfigurationManager: DNSConfigurationManaging {
    var statuses: [DNSConfigurationStatus]
    var error: Error?
    var createdProviderID: String?
    var didRemove = false

    init(statuses: [DNSConfigurationStatus] = [], error: Error? = nil) {
        self.statuses = statuses
        self.error = error
    }

    func create(provider: DNSProvider) async throws {
        if let error { throw error }
        createdProviderID = provider.id
    }

    func status() async throws -> DNSConfigurationStatus {
        if let error { throw error }
        return statuses.isEmpty ? .none : statuses.removeFirst()
    }

    func remove() async throws {
        if let error { throw error }
        didRemove = true
    }
}
