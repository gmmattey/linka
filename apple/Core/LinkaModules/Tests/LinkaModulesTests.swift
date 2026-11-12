import XCTest
import CloudKit
@testable import LinkaModules
import LinkaEntitlements
import MeasurementHistoryCloudKit
import NetworkAssist
import NetworkInsights

/// Dublê de `MeasurementRemoteStore` que nunca toca `CKContainer` — usado
/// só para testar `LinkaMeasurementHistory.makeRepository` (PR #93 R2,
/// achado 2) sem derrubar o processo de `swift test`: instanciar
/// `CKContainer` fora de um binário assinado com o entitlement de iCloud
/// crasha o processo, inclusive em CI (`.github/workflows/swift-modules-ci.yml`
/// roda `swift test` puro para este pacote).
private actor NeverCallsCloudKitRemoteStore: MeasurementRemoteStore {
    func accountStatus() async -> CKAccountStatus { .noAccount }
    func ensureZoneExists() async throws {}
    func upload(_ records: [CKRecord]) async throws {}
    func deleteRemote(recordIDs: [CKRecord.ID]) async throws {}
    func fetchChanges(since token: Data?) async throws -> MeasurementRemoteChangeSet {
        MeasurementRemoteChangeSet(changedRecords: [], deletedRecordIDs: [], newChangeToken: nil)
    }
}

final class LinkaModulesTests: XCTestCase {
    func testFreeTierIncludesSpeedTestAndHistory() {
        XCTAssertEqual(LinkaAccessPolicy.capabilities(for: .free), [.speedTest, .history])
        XCTAssertTrue(LinkaAccessPolicy.hasAccess(to: .speedTest, on: .free))
        XCTAssertTrue(LinkaAccessPolicy.hasAccess(to: .history, on: .free))
        XCTAssertFalse(LinkaAccessPolicy.hasAccess(to: .insights, on: .free))
        XCTAssertFalse(LinkaAccessPolicy.hasAccess(to: .assist, on: .free))
        XCTAssertFalse(LinkaAccessPolicy.hasAccess(to: .appleIntegrations, on: .free))
    }

    func testPlusTierIncludesAllCapabilities() {
        XCTAssertEqual(
            LinkaAccessPolicy.capabilities(for: .plus),
            Set(LinkaCapability.allCases)
        )
    }

    // MARK: - LinkaMeasurementHistory.makeRepository (PR #93 R2, achado 2)

    func testMakeRepositoryReturnsSameInstanceAcrossRepeatedCalls() async throws {
        // Antes desta correção, cada chamada criava um
        // `SyncingHistoryRepository` novo — e o `init` desse tipo dispara
        // `syncNow()` sozinho — então chamar `makeRepository` várias vezes
        // (como `SpeedTestViewModel.loadLastTest()`/`startTest()` faziam a
        // cada instância) disparava um `syncNow()` redundante por chamada.
        // Mesma instância para o mesmo `fileURL` == `init` roda uma vez só.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("linka-history-singleton-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let entitlements = StaticLinkaEntitlementProvider(
            snapshot: .plus(status: .active, source: .subscription)
        )
        let remote = NeverCallsCloudKitRemoteStore()

        let first = LinkaMeasurementHistory.makeRepository(fileURL: tempURL, entitlements: entitlements, remote: remote)
        let second = LinkaMeasurementHistory.makeRepository(fileURL: tempURL, entitlements: entitlements, remote: remote)
        let third = LinkaMeasurementHistory.makeRepository(fileURL: tempURL, entitlements: entitlements, remote: remote)

        // Mesma instância nas três chamadas: o `init` de
        // `SyncingMeasurementHistoryRepository` (que dispara `syncNow()`
        // sozinho) roda uma única vez, não uma por chamada de
        // `makeRepository` — era exatamente isto que faltava antes da
        // correção (`SpeedTestViewModel.loadLastTest()`/`startTest()`
        // chamavam o factory a cada instância).
        XCTAssertTrue(first === second)
        XCTAssertTrue(first === third)
    }

    func testMakeRepositoryReturnsDifferentInstancesForDifferentFileURLs() async throws {
        let tempURLA = FileManager.default.temporaryDirectory
            .appendingPathComponent("linka-history-singleton-test-a-\(UUID().uuidString).json")
        let tempURLB = FileManager.default.temporaryDirectory
            .appendingPathComponent("linka-history-singleton-test-b-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tempURLA)
            try? FileManager.default.removeItem(at: tempURLB)
        }

        let entitlements = StaticLinkaEntitlementProvider(
            snapshot: .plus(status: .active, source: .subscription)
        )
        let remote = NeverCallsCloudKitRemoteStore()

        let repoA = LinkaMeasurementHistory.makeRepository(fileURL: tempURLA, entitlements: entitlements, remote: remote)
        let repoB = LinkaMeasurementHistory.makeRepository(fileURL: tempURLB, entitlements: entitlements, remote: remote)

        XCTAssertFalse(repoA === repoB)
    }

    func testHistoryCompatibilityUsesStandaloneRepository() async throws {
        let older = NetworkMeasurement(
            measuredAt: Date(timeIntervalSince1970: 100),
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20
        )
        let newer = NetworkMeasurement(
            measuredAt: Date(timeIntervalSince1970: 200),
            outcome: .complete,
            downloadMbps: 200,
            uploadMbps: 50,
            latencyMs: 20
        )
        let store = InMemoryHistoryStore()

        try await store.save(older)
        try await store.save(newer)

        let measurements = try await store.measurements(
            matching: .init(limit: 2)
        )
        XCTAssertEqual(measurements.map(\.id), [newer.id, older.id])
    }

    func testInsightProviderCalculatesRelativeDeltaWithoutDiagnosis() async {
        let baseline = NetworkMeasurement(
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20
        )
        let current = NetworkMeasurement(
            downloadMbps: 120,
            uploadMbps: 40,
            latencyMs: 30
        )

        let comparison = await BasicInsightProvider().compare(
            current: current,
            against: baseline
        )

        XCTAssertEqual(comparison.delta.downloadPercent ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(comparison.delta.uploadPercent ?? 0, -20, accuracy: 0.001)
        XCTAssertEqual(comparison.delta.latencyPercent ?? 0, 50, accuracy: 0.001)
    }

    func testUnconfiguredAssistTransportFailsClosed() async {
        let context = AssistContext(
            question: "Minha velocidade mudou?",
            currentMeasurement: NetworkMeasurement(downloadMbps: 100)
        )
        let provider = TransportBackedAssistProvider(
            transport: UnconfiguredAssistTransport()
        )

        do {
            _ = try await provider.answer(context)
            XCTFail("Expected AssistError.notConfigured")
        } catch let error as AssistError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCompleteMeasurementRequiresCoreMetrics() {
        let complete = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 500,
            uploadMbps: 100,
            latencyMs: 12
        )

        XCTAssertTrue(NetworkMeasurementContract.isValid(complete))
    }

    func testPartialMeasurementNeedsAtLeastOneMeasuredMetric() {
        XCTAssertFalse(NetworkMeasurementContract.isValid(NetworkMeasurement()))
        XCTAssertTrue(NetworkMeasurementContract.isValid(NetworkMeasurement(latencyMs: 18)))
    }

    // MARK: - EntitlementGatedNetworkInsightsAnalyzer

    func testEntitlementGatedInsightsDeniesFreePlan() {
        let gated = EntitlementGatedNetworkInsightsAnalyzer(
            wrapping: BasicNetworkInsightsAnalyzer(),
            snapshot: .free
        )

        XCTAssertThrowsError(
            try gated.summarize([NetworkMeasurement(downloadMbps: 100)])
        ) { error in
            XCTAssertEqual(error as? NetworkInsightsError, .notEntitled)
        }
    }

    func testEntitlementGatedInsightsDelegatesForActivePlus() throws {
        let gated = EntitlementGatedNetworkInsightsAnalyzer(
            wrapping: BasicNetworkInsightsAnalyzer(),
            snapshot: .plus(status: .active, source: .subscription)
        )

        let summary = try gated.summarize([
            NetworkMeasurement(downloadMbps: 100),
            NetworkMeasurement(downloadMbps: 120)
        ])

        XCTAssertEqual(summary.measurementCount, 2)
    }

    // MARK: - EntitlementGatedNetworkAssistProvider

    func testEntitlementGatedAssistDeniesFreePlanWithoutCallingTheWrappedProvider() async {
        let gated = EntitlementGatedNetworkAssistProvider(
            wrapping: NetworkAssistService(transport: UnconfiguredNetworkAssistTransport()),
            snapshot: { .free }
        )

        let context = NetworkAssistContext(
            question: "Minha conexão está boa?",
            currentMeasurement: NetworkMeasurement(downloadMbps: 100)
        )

        do {
            _ = try await gated.answer(context)
            XCTFail("Expected NetworkAssistError.notEntitled")
        } catch let error as NetworkAssistError {
            // .notEntitled, não .notConfigured — o gate de plano roda antes
            // do transport, então a ausência de transport nunca é observada
            // para um usuário sem direito ao Assist.
            XCTAssertEqual(error, .notEntitled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEntitlementGatedAssistDelegatesForActivePlus() async {
        let gated = EntitlementGatedNetworkAssistProvider(
            wrapping: NetworkAssistService(transport: UnconfiguredNetworkAssistTransport()),
            snapshot: { .plus(status: .active, source: .subscription) }
        )

        let context = NetworkAssistContext(
            question: "Minha conexão está boa?",
            currentMeasurement: NetworkMeasurement(downloadMbps: 100)
        )

        do {
            _ = try await gated.answer(context)
            XCTFail("Expected NetworkAssistError.notConfigured (delegated to the wrapped transport)")
        } catch let error as NetworkAssistError {
            // Plano Plus passa pelo gate; o erro observado é o do transport
            // real (não configurado neste teste), confirmando delegação.
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - EntitlementGatedNetworkAssistProvider.streamAnswer (issue #69)

    func testEntitlementGatedStreamAnswerDeniesFreePlanWithoutObservingAnyEvent() async {
        let gated = EntitlementGatedNetworkAssistProvider(
            wrapping: NetworkAssistService(transport: UnconfiguredNetworkAssistTransport()),
            snapshot: { .free }
        )

        let context = NetworkAssistContext(
            question: "Minha conexão está boa?",
            currentMeasurement: NetworkMeasurement(downloadMbps: 100)
        )

        do {
            // O gate roda antes de qualquer evento (`.progress`/
            // `.textDelta`/`.completed`) — um plano free nunca observa
            // sequer o bridge não-streaming do transport por baixo.
            for try await _ in gated.streamAnswer(context) {
                XCTFail("No event expected for a plan without Assist access")
            }
            XCTFail("Expected NetworkAssistError.notEntitled")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .notEntitled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEntitlementGatedStreamAnswerDelegatesForActivePlus() async {
        let gated = EntitlementGatedNetworkAssistProvider(
            wrapping: NetworkAssistService(transport: UnconfiguredNetworkAssistTransport()),
            snapshot: { .plus(status: .active, source: .subscription) }
        )

        let context = NetworkAssistContext(
            question: "Minha conexão está boa?",
            currentMeasurement: NetworkMeasurement(downloadMbps: 100)
        )

        do {
            for try await _ in gated.streamAnswer(context) {
                XCTFail("Unconfigured transport should never yield an event")
            }
            XCTFail("Expected NetworkAssistError.notConfigured (delegated to the wrapped provider)")
        } catch let error as NetworkAssistError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
