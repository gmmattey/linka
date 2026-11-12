import XCTest
@testable import NetworkCore

final class NetworkCoreTests: XCTestCase {
    func testLoadResponsivenessRoundTripsAndProjectsDirectionalMedians() throws {
        let latency = LatencyEvidenceSummary(medianMs: 12, p95Ms: 20, maximumMs: 25, sampleCount: 8, timeoutCount: 1, warmupDurationMs: 2_000)
        let phase = LoadPhaseEvidence(latency: latency, usefulDurationMs: 10_000, bytesTransferred: 4_000_000, averageMbps: 80, saturation: .sustained)
        let evidence = LoadResponsivenessEvidence(
            environmentIdentifier: "cloudflare-speedtest-v1",
            integrity: .valid,
            baseline: LatencyEvidenceSummary(medianMs: 8, p95Ms: 9, maximumMs: 10, sampleCount: 8, timeoutCount: 0, warmupDurationMs: 200),
            download: phase,
            upload: phase
        )
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 40,
            latencyMs: 8,
            loadedLatencyMs: 12,
            loadedLatencyUploadMs: 12,
            loadResponsiveness: evidence
        )

        let decoded = try JSONDecoder().decode(NetworkMeasurement.self, from: JSONEncoder().encode(measurement))
        XCTAssertEqual(decoded, measurement)
        XCTAssertTrue(NetworkMeasurementContract.isValid(decoded))
    }

    func testLoadResponsivenessRejectsMismatchedScalarProjection() {
        let latency = LatencyEvidenceSummary(medianMs: 12, p95Ms: 12, maximumMs: 12, sampleCount: 5, timeoutCount: 0, warmupDurationMs: 2_000)
        let phase = LoadPhaseEvidence(latency: latency, usefulDurationMs: 10_000, bytesTransferred: 1, averageMbps: 1, saturation: .sustained)
        let evidence = LoadResponsivenessEvidence(environmentIdentifier: "cloudflare-speedtest-v1", integrity: .valid, baseline: latency, download: phase, upload: phase)
        let measurement = NetworkMeasurement(latencyMs: 12, loadedLatencyMs: 11, loadedLatencyUploadMs: 12, loadResponsiveness: evidence)
        XCTAssertTrue(NetworkMeasurementContract.violations(for: measurement).contains("loadedLatencyMs"))
    }

    func testAdvancedWiFiDiagnosticsRoundTripsWithoutRawIdentifiers() throws {
        let diagnostics = AdvancedWiFiDiagnostics(
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ssid: "Casa",
            accessPointIdentifier: "local-derived-id",
            wifiStandard: "Wi-Fi 6",
            rxRateMbps: 720,
            txRateMbps: 866,
            rssiDbm: -54,
            noiseDbm: -92,
            channelNumber: 44,
            bandGHz: 5,
            snrDb: 38
        )
        let measurement = NetworkMeasurement(
            latencyMs: 12,
            connectionKind: .wifi,
            advancedWiFiDiagnostics: diagnostics
        )
        let decoded = try JSONDecoder().decode(NetworkMeasurement.self, from: JSONEncoder().encode(measurement))
        XCTAssertEqual(decoded.advancedWiFiDiagnostics, diagnostics)
        let json = String(decoding: try JSONEncoder().encode(measurement), as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("bssid"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("hardwareMac"))
    }

    func testAdvancedWiFiDiagnosticsDerivesOnlyDocumentedFacts() {
        XCTAssertEqual(AdvancedWiFiDiagnostics.bandGHz(forChannel: 11), 2.4)
        XCTAssertEqual(AdvancedWiFiDiagnostics.bandGHz(forChannel: 44), 5)
        XCTAssertNil(AdvancedWiFiDiagnostics.bandGHz(forChannel: 201))
        XCTAssertEqual(AdvancedWiFiDiagnostics.snrDb(rssiDbm: -54, noiseDbm: -92), 38)
        XCTAssertNil(AdvancedWiFiDiagnostics.snrDb(rssiDbm: nil, noiseDbm: -92))
    }

    func testAdvancedWiFiDiagnosticsRequiresTemporalAndSSIDConfidence() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(20)
        let eligible = AdvancedWiFiDiagnostics(capturedAt: start.addingTimeInterval(-30), ssid: "Casa")
        XCTAssertTrue(eligible.isEligible(forMeasurementStartedAt: start, endedAt: end, nativeSSID: "Casa"))
        XCTAssertFalse(eligible.isEligible(forMeasurementStartedAt: start, endedAt: end, nativeSSID: "Trabalho"))
        let stale = AdvancedWiFiDiagnostics(capturedAt: start.addingTimeInterval(-31))
        XCTAssertFalse(stale.isEligible(forMeasurementStartedAt: start, endedAt: end, nativeSSID: nil))
    }

    func testWiFiContextRoundTripsAndLegacyJSONRemainsCompatible() throws {
        let context = WiFiNetworkContext(
            ssid: "Casa",
            accessPointIdentifier: "derived-id",
            securityType: .personal,
            bandGHz: 5,
            rssiDbm: -51,
            linkSpeedMbps: 866
        )
        let original = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 500,
            uploadMbps: 100,
            latencyMs: 12,
            connectionKind: .wifi,
            wifiContext: context
        )

        let decoded = try JSONDecoder().decode(NetworkMeasurement.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.wifiContext, context)
    }

    func testWiFiContextRequiresWiFiConnection() {
        let measurement = NetworkMeasurement(
            latencyMs: 15,
            connectionKind: .cellular,
            wifiContext: WiFiNetworkContext(ssid: "Casa")
        )
        XCTAssertTrue(NetworkMeasurementContract.violations(for: measurement).contains("wifiContext"))
    }

    func testWiFiContextResolveRejectsSSIDChangeAndAllowsRoaming() {
        let start = WiFiNetworkContext(ssid: "Casa", accessPointIdentifier: "ap-1", securityType: .personal)
        let changed = WiFiNetworkContext(ssid: "Trabalho", accessPointIdentifier: "ap-2", securityType: .personal)
        XCTAssertNil(WiFiNetworkContext.resolve(start: start, end: changed, connectionKind: .wifi))

        let roaming = WiFiNetworkContext(ssid: "Casa", accessPointIdentifier: "ap-2", securityType: .personal)
        let resolved = WiFiNetworkContext.resolve(start: start, end: roaming, connectionKind: .wifi)
        XCTAssertEqual(resolved?.ssid, "Casa")
        XCTAssertNil(resolved?.accessPointIdentifier)
    }

    func testWiFiContextResolveRejectsInterfaceTransition() {
        let context = WiFiNetworkContext(ssid: "Casa")
        XCTAssertNil(WiFiNetworkContext.resolve(start: context, end: context, connectionKind: nil))
    }

    func testCompleteMeasurementRequiresCoreMetrics() {
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 500,
            uploadMbps: 100,
            latencyMs: 12
        )

        XCTAssertTrue(NetworkMeasurementContract.isValid(measurement))
    }

    func testPartialMeasurementRequiresAtLeastOneMetric() {
        XCTAssertFalse(NetworkMeasurementContract.isValid(NetworkMeasurement()))
        XCTAssertTrue(NetworkMeasurementContract.isValid(NetworkMeasurement(latencyMs: 15)))
    }

    func testInvalidRangesAreRejected() {
        let measurement = NetworkMeasurement(
            downloadMbps: -1,
            packetLossPercent: 101
        )

        let violations = NetworkMeasurementContract.violations(for: measurement)
        XCTAssertTrue(violations.contains("downloadMbps"))
        XCTAssertTrue(violations.contains("packetLossPercent"))
    }

    func testWifiBandRequiresWifiConnectionKind() {
        let bandWithoutWifi = NetworkMeasurement(
            latencyMs: 15,
            connectionKind: .cellular,
            wifiBandGHz: 5.0
        )
        XCTAssertTrue(NetworkMeasurementContract.violations(for: bandWithoutWifi).contains("wifiBandGHz"))

        let bandWithNilKind = NetworkMeasurement(
            latencyMs: 15,
            connectionKind: nil,
            wifiBandGHz: 5.0
        )
        XCTAssertTrue(NetworkMeasurementContract.violations(for: bandWithNilKind).contains("wifiBandGHz"))

        let validBand = NetworkMeasurement(
            latencyMs: 15,
            connectionKind: .wifi,
            wifiBandGHz: 5.0
        )
        XCTAssertTrue(NetworkMeasurementContract.isValid(validBand))
    }

    func testWifiBandMustBePositiveAndFinite() {
        let negative = NetworkMeasurement(
            latencyMs: 15,
            connectionKind: .wifi,
            wifiBandGHz: -1
        )
        XCTAssertTrue(NetworkMeasurementContract.violations(for: negative).contains("wifiBandGHz"))

        let nan = NetworkMeasurement(
            latencyMs: 15,
            connectionKind: .wifi,
            wifiBandGHz: .nan
        )
        XCTAssertTrue(NetworkMeasurementContract.violations(for: nan).contains("wifiBandGHz"))
    }

    /// Ausência de banda é o estado normal (issue #51 — sempre o caso no
    /// iPhone, e no Mac quando `CoreWLAN` não confirma nada): não é
    /// violação de contrato.
    func testWifiConnectionWithoutBandIsValid() {
        let measurement = NetworkMeasurement(
            latencyMs: 15,
            connectionKind: .wifi,
            wifiBandGHz: nil
        )
        XCTAssertTrue(NetworkMeasurementContract.isValid(measurement))
    }

    /// Um registro antigo (schema v1, sem `wifiBandGHz` no JSON) precisa
    /// continuar decodificando sem quebrar — o campo novo é opcional com
    /// default `nil`, sem exigir bump de `schemaVersion` (nota do plano #51).
    func testDecodesLegacyJSONWithoutWifiBandField() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "id": "4A5F9B63-E4F4-4D90-904F-3E618FC92C32",
            "measuredAt": "2026-08-01T12:00:00Z",
            "outcome": "complete",
            "downloadMbps": 512.4,
            "uploadMbps": 104.8,
            "latencyMs": 11.7,
            "connectionKind": "wifi",
            "serverIdentifier": "cloudflare"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: Data(legacyJSON.utf8))

        XCTAssertNil(decoded.wifiBandGHz)
        XCTAssertEqual(decoded.connectionKind, .wifi)
        XCTAssertTrue(NetworkMeasurementContract.isValid(decoded))
    }

    func testMeasurementRoundTripsThroughJSON() throws {
        let original = NetworkMeasurement(
            id: UUID(uuidString: "4A5F9B63-E4F4-4D90-904F-3E618FC92C32")!,
            measuredAt: Date(timeIntervalSince1970: 1_786_428_000),
            outcome: .complete,
            downloadMbps: 512.4,
            uploadMbps: 104.8,
            latencyMs: 11.7,
            connectionKind: .wifi,
            serverIdentifier: "cloudflare"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testWifiBandRoundTripsThroughJSON() throws {
        let original = NetworkMeasurement(
            id: UUID(uuidString: "4A5F9B63-E4F4-4D90-904F-3E618FC92C32")!,
            measuredAt: Date(timeIntervalSince1970: 1_786_428_000),
            outcome: .complete,
            downloadMbps: 512.4,
            uploadMbps: 104.8,
            latencyMs: 11.7,
            connectionKind: .wifi,
            wifiBandGHz: 5.0,
            serverIdentifier: "cloudflare"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.wifiBandGHz, 5.0)
    }

    /// Issue #50: `durationMs` já existia no contrato, mas nada preenchia
    /// no ponto de construção do registro salvo. Este teste comprova que o
    /// campo, uma vez populado, sobrevive ao round-trip como qualquer outro
    /// fato — mesmo padrão de `testWifiBandRoundTripsThroughJSON`.
    func testDurationRoundTripsThroughJSON() throws {
        let original = NetworkMeasurement(
            id: UUID(uuidString: "4A5F9B63-E4F4-4D90-904F-3E618FC92C32")!,
            measuredAt: Date(timeIntervalSince1970: 1_786_428_000),
            outcome: .complete,
            downloadMbps: 512.4,
            uploadMbps: 104.8,
            latencyMs: 11.7,
            durationMs: 12_300,
            connectionKind: .wifi,
            serverIdentifier: "cloudflare"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.durationMs, 12_300)
    }

    /// Um registro antigo (sem `durationMs` no JSON, campo que nunca foi
    /// preenchido antes da issue #50) precisa continuar decodificando sem
    /// quebrar — mesmo padrão de `testDecodesLegacyJSONWithoutWifiBandField`.
    func testDecodesLegacyJSONWithoutDurationField() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "id": "4A5F9B63-E4F4-4D90-904F-3E618FC92C32",
            "measuredAt": "2026-08-01T12:00:00Z",
            "outcome": "complete",
            "downloadMbps": 512.4,
            "uploadMbps": 104.8,
            "latencyMs": 11.7,
            "connectionKind": "wifi",
            "serverIdentifier": "cloudflare"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: Data(legacyJSON.utf8))

        XCTAssertNil(decoded.durationMs)
        XCTAssertTrue(NetworkMeasurementContract.isValid(decoded))
    }

    /// Issue #128: `loadedLatencyUploadMs` é o novo campo aditivo (paridade
    /// de upload para `loadedLatencyMs`). Round-trip comprova que, uma vez
    /// populado, sobrevive à serialização — mesmo padrão de
    /// `testWifiBandRoundTripsThroughJSON`/`testDurationRoundTripsThroughJSON`.
    func testLoadedLatencyUploadRoundTripsThroughJSON() throws {
        let original = NetworkMeasurement(
            id: UUID(uuidString: "4A5F9B63-E4F4-4D90-904F-3E618FC92C32")!,
            measuredAt: Date(timeIntervalSince1970: 1_786_428_000),
            outcome: .complete,
            downloadMbps: 512.4,
            uploadMbps: 104.8,
            latencyMs: 11.7,
            loadedLatencyMs: 18.2,
            loadedLatencyUploadMs: 21.6,
            connectionKind: .wifi,
            serverIdentifier: "cloudflare"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.loadedLatencyUploadMs, 21.6)
    }

    /// Um registro antigo (sem `loadedLatencyUploadMs` no JSON, campo que
    /// não existia antes da issue #128) precisa continuar decodificando sem
    /// quebrar — mesmo padrão de `testDecodesLegacyJSONWithoutWifiBandField`/
    /// `testDecodesLegacyJSONWithoutDurationField`. `schemaVersion`
    /// permanece `1`: campo aditivo, opcional, `nil` por padrão, não exige
    /// bump de versão de schema.
    func testDecodesLegacyJSONWithoutLoadedLatencyUploadField() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "id": "4A5F9B63-E4F4-4D90-904F-3E618FC92C32",
            "measuredAt": "2026-08-01T12:00:00Z",
            "outcome": "complete",
            "downloadMbps": 512.4,
            "uploadMbps": 104.8,
            "latencyMs": 11.7,
            "loadedLatencyMs": 18.2,
            "connectionKind": "wifi",
            "serverIdentifier": "cloudflare"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: Data(legacyJSON.utf8))

        XCTAssertNil(decoded.loadedLatencyUploadMs)
        XCTAssertEqual(decoded.loadedLatencyMs, 18.2)
        XCTAssertTrue(NetworkMeasurementContract.isValid(decoded))
    }

    /// `loadedLatencyUploadMs` segue a mesma regra de faixa válida das
    /// demais métricas de latência — negativo é violação de contrato.
    func testLoadedLatencyUploadMustBeNonNegative() {
        let measurement = NetworkMeasurement(
            latencyMs: 15,
            loadedLatencyUploadMs: -1
        )
        XCTAssertTrue(NetworkMeasurementContract.violations(for: measurement).contains("loadedLatencyUploadMs"))
    }

    /// Expert Mode: `dnsResolutionMs` é o novo campo aditivo (tempo de
    /// resolução DNS do host do teste). Round-trip comprova que, uma vez
    /// populado, sobrevive à serialização — mesmo padrão de
    /// `testLoadedLatencyUploadRoundTripsThroughJSON`.
    func testDNSResolutionRoundTripsThroughJSON() throws {
        let original = NetworkMeasurement(
            id: UUID(uuidString: "4A5F9B63-E4F4-4D90-904F-3E618FC92C32")!,
            measuredAt: Date(timeIntervalSince1970: 1_786_428_000),
            outcome: .complete,
            downloadMbps: 512.4,
            uploadMbps: 104.8,
            latencyMs: 11.7,
            dnsResolutionMs: 14.3,
            connectionKind: .wifi,
            serverIdentifier: "cloudflare"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.dnsResolutionMs, 14.3)
    }

    /// Um registro antigo (sem `dnsResolutionMs` no JSON, campo que não
    /// existia antes do Expert Mode) precisa continuar decodificando sem
    /// quebrar — mesmo padrão de
    /// `testDecodesLegacyJSONWithoutLoadedLatencyUploadField`.
    /// `schemaVersion` permanece `1`: campo aditivo, opcional, `nil` por
    /// padrão, não exige bump de versão de schema.
    func testDecodesLegacyJSONWithoutDNSResolutionField() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "id": "4A5F9B63-E4F4-4D90-904F-3E618FC92C32",
            "measuredAt": "2026-08-01T12:00:00Z",
            "outcome": "complete",
            "downloadMbps": 512.4,
            "uploadMbps": 104.8,
            "latencyMs": 11.7,
            "connectionKind": "wifi",
            "serverIdentifier": "cloudflare"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NetworkMeasurement.self, from: Data(legacyJSON.utf8))

        XCTAssertNil(decoded.dnsResolutionMs)
        XCTAssertTrue(NetworkMeasurementContract.isValid(decoded))
    }

    /// `dnsResolutionMs` segue a mesma regra de faixa válida das demais
    /// métricas de latência — negativo, infinito ou NaN é violação de
    /// contrato; ausência (`nil`, falha/timeout de resolução) não é.
    func testDNSResolutionMustBeFiniteAndNonNegative() {
        let negative = NetworkMeasurement(latencyMs: 15, dnsResolutionMs: -1)
        XCTAssertTrue(NetworkMeasurementContract.violations(for: negative).contains("dnsResolutionMs"))

        let infinite = NetworkMeasurement(latencyMs: 15, dnsResolutionMs: .infinity)
        XCTAssertTrue(NetworkMeasurementContract.violations(for: infinite).contains("dnsResolutionMs"))

        let nan = NetworkMeasurement(latencyMs: 15, dnsResolutionMs: .nan)
        XCTAssertTrue(NetworkMeasurementContract.violations(for: nan).contains("dnsResolutionMs"))

        let valid = NetworkMeasurement(latencyMs: 15, dnsResolutionMs: 14.3)
        XCTAssertFalse(NetworkMeasurementContract.violations(for: valid).contains("dnsResolutionMs"))
    }

    // MARK: - NetworkConnectionKind.resolve(start:end:) — issue #51

    /// Troca de rede durante o teste (início ≠ fim) deve persistir `nil`
    /// em vez de afirmar um tipo que não valeu para o teste inteiro.
    func testResolveReturnsNilWhenBothAreNil() {
        XCTAssertNil(NetworkConnectionKind.resolve(start: nil, end: nil))
    }

    func testResolveReturnsNilWhenStartIsNil() {
        XCTAssertNil(NetworkConnectionKind.resolve(start: nil, end: .wifi))
    }

    func testResolveReturnsNilWhenEndIsNil() {
        XCTAssertNil(NetworkConnectionKind.resolve(start: .wifi, end: nil))
    }

    func testResolveReturnsCommonKindWhenBothMatch() {
        XCTAssertEqual(NetworkConnectionKind.resolve(start: .wifi, end: .wifi), .wifi)
        XCTAssertEqual(NetworkConnectionKind.resolve(start: .cellular, end: .cellular), .cellular)
        XCTAssertEqual(NetworkConnectionKind.resolve(start: .ethernet, end: .ethernet), .ethernet)
        XCTAssertEqual(NetworkConnectionKind.resolve(start: .other, end: .other), .other)
    }

    func testResolveReturnsNilWhenKindsDiverge() {
        XCTAssertNil(NetworkConnectionKind.resolve(start: .wifi, end: .cellular))
        XCTAssertNil(NetworkConnectionKind.resolve(start: .cellular, end: .wifi))
        XCTAssertNil(NetworkConnectionKind.resolve(start: .ethernet, end: .other))
        XCTAssertNil(NetworkConnectionKind.resolve(start: .wifi, end: .ethernet))
    }
}
