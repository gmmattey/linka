import Foundation
import XCTest
import NetworkCore
@testable import MeasurementHistory

final class MeasurementHistoryTests: XCTestCase {
    func testSaveIsIdempotentByMeasurementID() async throws {
        let id = UUID()
        let repository = InMemoryMeasurementHistoryRepository()

        try await repository.save(makeMeasurement(id: id, download: 100))
        try await repository.save(makeMeasurement(id: id, download: 200))

        let count = try await repository.totalCount()
        let stored = try await repository.measurement(id: id)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(stored?.downloadMbps, 200)
    }

    func testQueryFiltersSortsAndPaginates() async throws {
        let repository = InMemoryMeasurementHistoryRepository()
        let base = Date(timeIntervalSince1970: 1_000)

        try await repository.save(makeMeasurement(
            measuredAt: base,
            download: 100,
            connectionKind: .wifi
        ))
        try await repository.save(makeMeasurement(
            measuredAt: base.addingTimeInterval(100),
            download: 200,
            connectionKind: .cellular
        ))
        try await repository.save(makeMeasurement(
            measuredAt: base.addingTimeInterval(200),
            download: 300,
            connectionKind: .wifi
        ))

        let query = MeasurementQuery(
            measuredFrom: base,
            connectionKinds: [.wifi],
            offset: 1,
            limit: 1,
            sortOrder: .newestFirst
        )
        let result = try await repository.measurements(matching: query)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.downloadMbps, 100)
    }

    func testRetentionKeepsNewestEntries() async throws {
        let repository = InMemoryMeasurementHistoryRepository(
            retentionPolicy: HistoryRetentionPolicy(maximumEntries: 2)
        )
        let base = Date()

        try await repository.save(makeMeasurement(
            measuredAt: base.addingTimeInterval(-200),
            download: 100
        ))
        try await repository.save(makeMeasurement(
            measuredAt: base.addingTimeInterval(-100),
            download: 200
        ))
        try await repository.save(makeMeasurement(
            measuredAt: base,
            download: 300
        ))

        let result = try await repository.measurements(matching: .all)
        XCTAssertEqual(result.map(\.downloadMbps), [300, 200])
    }

    func testInvalidMeasurementIsRejected() async {
        let repository = InMemoryMeasurementHistoryRepository()
        let invalid = NetworkMeasurement(downloadMbps: -10)

        do {
            try await repository.save(invalid)
            XCTFail("Expected invalidMeasurement")
        } catch let error as MeasurementHistoryError {
            guard case .invalidMeasurement(let violations) = error else {
                XCTFail("Unexpected history error: \(error)")
                return
            }
            XCTAssertTrue(violations.contains("downloadMbps"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Issue #51 — Mac com `CoreWLAN` confirmando banda: o repositório
    /// aceita e preserva `wifiBandGHz` junto de `connectionKind == .wifi`.
    func testSavingWifiMeasurementWithBandSucceeds() async throws {
        let repository = InMemoryMeasurementHistoryRepository()
        let measurement = makeMeasurement(
            connectionKind: .wifi,
            wifiBandGHz: 5.0
        )

        try await repository.save(measurement)

        let stored = try await repository.measurement(id: measurement.id)
        XCTAssertEqual(stored?.wifiBandGHz, 5.0)
    }

    /// Issue #51 — iPhone (sempre) ou Mac sem `CoreWLAN` confirmando nada:
    /// ausência de banda é o estado normal, não impede salvar.
    func testSavingWifiMeasurementWithoutBandSucceeds() async throws {
        let repository = InMemoryMeasurementHistoryRepository()
        let measurement = makeMeasurement(
            connectionKind: .wifi,
            wifiBandGHz: nil
        )

        try await repository.save(measurement)

        let stored = try await repository.measurement(id: measurement.id)
        XCTAssertNil(stored?.wifiBandGHz)
    }

    /// Issue #51 — banda Wi-Fi persistida junto de uma interface que não é
    /// Wi-Fi seria um metadado enganoso; o contrato bloqueia isso na
    /// gravação, não só na validação isolada (`NetworkCoreTests`).
    func testSavingNonWifiMeasurementWithBandIsRejected() async {
        let repository = InMemoryMeasurementHistoryRepository()
        let measurement = makeMeasurement(
            connectionKind: .cellular,
            wifiBandGHz: 5.0
        )

        do {
            try await repository.save(measurement)
            XCTFail("Expected invalidMeasurement")
        } catch let error as MeasurementHistoryError {
            guard case .invalidMeasurement(let violations) = error else {
                XCTFail("Unexpected history error: \(error)")
                return
            }
            XCTAssertTrue(violations.contains("wifiBandGHz"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFileRepositoryPersistsAcrossInstances() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let measurement = makeMeasurement(download: 512)
        let writer = FileMeasurementHistoryRepository(fileURL: fileURL)
        try await writer.save(measurement)

        let reader = FileMeasurementHistoryRepository(fileURL: fileURL)
        let restored = try await reader.measurement(id: measurement.id)

        XCTAssertEqual(restored, measurement)
    }

    func testFileRepositoryPersistsDeletion() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let measurement = makeMeasurement(download: 512)
        let writer = FileMeasurementHistoryRepository(fileURL: fileURL)
        try await writer.save(measurement)
        try await writer.delete(id: measurement.id)

        let reader = FileMeasurementHistoryRepository(fileURL: fileURL)
        let restored = try await reader.measurement(id: measurement.id)
        let count = try await reader.totalCount()
        XCTAssertNil(restored)
        XCTAssertEqual(count, 0)
    }

    func testCorruptedFileFailsClosed() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        let repository = FileMeasurementHistoryRepository(fileURL: fileURL)

        do {
            _ = try await repository.totalCount()
            XCTFail("Expected corruptedStore")
        } catch let error as MeasurementHistoryError {
            XCTAssertEqual(error, .corruptedStore)
        }
    }

    func testUnsupportedStoreVersionFailsClosed() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data("{\"schemaVersion\":99,\"measurements\":[]}".utf8)
        try data.write(to: fileURL)

        let repository = FileMeasurementHistoryRepository(fileURL: fileURL)

        do {
            _ = try await repository.totalCount()
            XCTFail("Expected unsupportedStoreVersion")
        } catch let error as MeasurementHistoryError {
            XCTAssertEqual(error, .unsupportedStoreVersion(99))
        }
    }

    /// Issue #51, nota do plano — um documento de store gravado antes do
    /// campo `wifiBandGHz` existir (sem esse campo no JSON) precisa
    /// continuar carregando: opcional com default `nil` não exige bump de
    /// `schemaVersion`, nem no contrato do documento nem no da medição.
    func testFileRepositoryLoadsLegacyDocumentWithoutWifiBandField() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let legacyDocument = """
        {
            "schemaVersion": 1,
            "measurements": [
                {
                    "schemaVersion": 1,
                    "id": "4A5F9B63-E4F4-4D90-904F-3E618FC92C32",
                    "measuredAt": 700000000.0,
                    "outcome": "complete",
                    "downloadMbps": 512.4,
                    "uploadMbps": 104.8,
                    "latencyMs": 11.7,
                    "connectionKind": "wifi",
                    "serverIdentifier": "cloudflare"
                }
            ]
        }
        """
        try Data(legacyDocument.utf8).write(to: fileURL)

        let repository = FileMeasurementHistoryRepository(fileURL: fileURL)
        let count = try await repository.totalCount()
        let restored = try await repository.measurement(
            id: UUID(uuidString: "4A5F9B63-E4F4-4D90-904F-3E618FC92C32")!
        )

        XCTAssertEqual(count, 1)
        XCTAssertNil(restored?.wifiBandGHz)
        XCTAssertEqual(restored?.connectionKind, .wifi)
    }

    /// Issue #50 — `durationMs` é fato genuinamente disponível-e-descartado
    /// antes desta issue: comprova que sobrevive ao ciclo completo de
    /// persistência em disco (`FileMeasurementHistoryRepository`), mesmo
    /// padrão de `testFileRepositoryPersistsAcrossInstances`. Não muda
    /// nada na persistência em si — `Codable` sintetizado já preserva
    /// qualquer campo opcional novo; este teste só comprova isso
    /// explicitamente para `durationMs`.
    func testFileRepositoryPersistsDurationMs() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 512,
            uploadMbps: 100,
            latencyMs: 12,
            durationMs: 12_300,
            connectionKind: .wifi
        )
        let writer = FileMeasurementHistoryRepository(fileURL: fileURL)
        try await writer.save(measurement)

        let reader = FileMeasurementHistoryRepository(fileURL: fileURL)
        let restored = try await reader.measurement(id: measurement.id)

        XCTAssertEqual(restored, measurement)
        XCTAssertEqual(restored?.durationMs, 12_300)
    }

    func testFileRepositoryPersistsWiFiContextLocally() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 512,
            uploadMbps: 100,
            latencyMs: 12,
            connectionKind: .wifi,
            wifiContext: WiFiNetworkContext(
                ssid: "Casa",
                accessPointIdentifier: "derived-ap",
                securityType: .personal
            )
        )
        let writer = FileMeasurementHistoryRepository(fileURL: fileURL)
        try await writer.save(measurement)

        let restored = try await FileMeasurementHistoryRepository(fileURL: fileURL).measurement(id: measurement.id)

        XCTAssertEqual(restored?.wifiContext, measurement.wifiContext)
    }

    func testMeasurementCSVExporterOutputsHeaderAndRowsWithEscaping() {
        let m1 = NetworkMeasurement(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            measuredAt: Date(timeIntervalSince1970: 1_700_000_000),
            outcome: .complete,
            downloadMbps: 123.45,
            uploadMbps: 67.89,
            latencyMs: 14.2,
            jitterMs: 1.5,
            packetLossPercent: 0.0,
            dnsResolutionMs: 8.0,
            connectionKind: .wifi,
            wifiBandGHz: 5.0,
            networkIdentifier: "Provedor, SP",
            devicePlatform: "macOS"
        )

        let csv = MeasurementCSVExporter.generateCSV(from: [m1])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}ID,Data/Hora,Tipo de Conexao"))
        XCTAssertTrue(csv.contains("11111111-1111-1111-1111-111111111111"))
        XCTAssertTrue(csv.contains("Wi-Fi"))
        XCTAssertTrue(csv.contains("123.45"))
        XCTAssertTrue(csv.contains("67.89"))
        XCTAssertTrue(csv.contains("14.2"))
        XCTAssertTrue(csv.contains("1.5"))
        XCTAssertTrue(csv.contains("\"Provedor, SP\""))
        XCTAssertTrue(csv.contains("macOS"))

        let data = MeasurementCSVExporter.generateCSVData(from: [m1])
        XCTAssertFalse(data.isEmpty)
    }

    private func makeMeasurement(
        id: UUID = UUID(),
        measuredAt: Date = Date(),
        download: Double = 100,
        connectionKind: NetworkConnectionKind? = .wifi,
        wifiBandGHz: Double? = nil
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            id: id,
            measuredAt: measuredAt,
            outcome: .complete,
            downloadMbps: download,
            uploadMbps: 50,
            latencyMs: 15,
            connectionKind: connectionKind,
            wifiBandGHz: wifiBandGHz
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("measurement-history-tests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history.json")
    }
}
