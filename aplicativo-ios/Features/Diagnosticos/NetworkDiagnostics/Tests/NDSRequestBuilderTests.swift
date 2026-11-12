import XCTest
@testable import NetworkDiagnostics
import NetworkCore

final class NDSRequestBuilderTests: XCTestCase {
    func testBuildRequestOmitsInconclusiveLoadedLatencyEnvelope() {
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20,
            loadedLatencyMs: 300,
            loadedLatencyUploadMs: 400,
            loadResponsiveness: LoadResponsivenessEvidence(
                environmentIdentifier: "cloudflare-speedtest-v1",
                integrity: .uploadInconclusive,
                baseline: nil,
                download: nil,
                upload: nil
            )
        )

        let request = NDSRequestBuilder().buildRequest(
            current: measurement,
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: true
        )
        XCTAssertNil(request.quality?.loadedLatencyMs)
        XCTAssertNil(request.quality?.loadedLatencyUploadMs)
        XCTAssertEqual(request.quality?.latencyMs, 20)
    }

    func testBuildRequest() throws {
        let builder = NDSRequestBuilder()
        let measurement = NetworkMeasurement(
            id: UUID(),
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20,
            connectionKind: .wifi
        )
        let hints = PlatformHints(wifi: PlatformHints.Wifi(rssiDbm: -50, linkSpeedMbps: 866))
        
        let request = builder.buildRequest(current: measurement, platformHints: hints, appVersion: "1.0.0", platformIdentifier: "ios", requestAI: true)
        
        XCTAssertEqual(request.sessionId, measurement.id.uuidString)
        XCTAssertEqual(request.platform, "ios")
        XCTAssertEqual(request.app?.version, "1.0.0")
        XCTAssertEqual(request.capabilities, ["connection", "wifi", "speed", "quality"])
        XCTAssertEqual(request.requestedOutputs, ["scoring", "ai"])
        XCTAssertEqual(request.connection?.type, "wifi")
        XCTAssertEqual(request.wifi?.rssiDbm, -50)
        XCTAssertEqual(request.speed?.downloadMbps, 100)

        let encoded = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["session_id"] as? String, measurement.id.uuidString)
        XCTAssertNil(json["sessionId"])
        XCTAssertEqual(json["requested_outputs"] as? [String], ["scoring", "ai"])
        XCTAssertNil(json["context"])

        let connectionJSON = try XCTUnwrap(json["connection"] as? [String: Any])
        XCTAssertEqual(connectionJSON["has_internet"] as? Bool, true)
        XCTAssertNil(connectionJSON["hasInternet"])

        let wifiJSON = try XCTUnwrap(json["wifi"] as? [String: Any])
        XCTAssertEqual(wifiJSON["rssi_dbm"] as? Double, -50)
        XCTAssertEqual(wifiJSON["link_speed_mbps"] as? Double, 866)
        XCTAssertNil(wifiJSON["rssiDbm"])
        XCTAssertNil(wifiJSON["linkSpeedMbps"])

        let speedJSON = try XCTUnwrap(json["speed"] as? [String: Any])
        XCTAssertEqual(speedJSON["download_mbps"] as? Double, 100)
        XCTAssertEqual(speedJSON["upload_mbps"] as? Double, 50)
        XCTAssertNil(speedJSON["downloadMbps"])
        XCTAssertNil(speedJSON["uploadMbps"])

        let qualityJSON = try XCTUnwrap(json["quality"] as? [String: Any])
        XCTAssertEqual(qualityJSON["latency_ms"] as? Double, 20)
        XCTAssertNil(qualityJSON["latencyMs"])
    }

    func testBuildRequest_forwardsOnlyProvidedDiagnosticContext() throws {
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20
        )
        let context = NDSRequest.DiagnosticContext(objective: "chamada de vídeo")

        let request = NDSRequestBuilder().buildRequest(
            current: measurement,
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: true,
            diagnosticContext: context
        )

        XCTAssertEqual(request.context, context)
    }

    func testBuildRequest_usesEffectiveLinkaLanguageTagInsteadOfDeviceLocale() throws {
        let request = NDSRequestBuilder().buildRequest(
            current: NetworkMeasurement(outcome: .complete, latencyMs: 20),
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: true,
            locale: "es-419"
        )

        XCTAssertEqual(request.locale, "es-419")
    }

    func testBuildRequest_defaultsLegacyCallersToPortugueseBrazil() throws {
        let request = NDSRequestBuilder().buildRequest(
            current: NetworkMeasurement(outcome: .complete, latencyMs: 20),
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: true
        )

        XCTAssertEqual(request.locale, "pt-BR")
    }

    /// `subcategory` (issue objective+subcategory guiado) só existe quando
    /// o app coletou a seleção guiada — precisa aparecer no JSON quando
    /// fornecido e ficar totalmente ausente (não `null`) quando não.
    func testBuildRequest_includesSubcategoryWhenProvided() throws {
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20
        )
        let context = NDSRequest.DiagnosticContext(objective: "JOGOS_COM_LAG", subcategory: "PING_ALTO")

        let request = NDSRequestBuilder().buildRequest(
            current: measurement,
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: true,
            diagnosticContext: context
        )

        XCTAssertEqual(request.context?.subcategory, "PING_ALTO")

        let encoded = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let contextJSON = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(contextJSON["subcategory"] as? String, "PING_ALTO")
    }

    func testBuildRequest_omitsSubcategoryWhenNil() throws {
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20
        )
        let context = NDSRequest.DiagnosticContext(objective: "JOGOS_COM_LAG")

        let request = NDSRequestBuilder().buildRequest(
            current: measurement,
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: true,
            diagnosticContext: context
        )

        XCTAssertNil(request.context?.subcategory)

        let encoded = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let contextJSON = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertNil(contextJSON["subcategory"])
    }

    func testBuildRequestNeverSendsSSIDOrBSSID() throws {
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20,
            connectionKind: .wifi,
            wifiContext: WiFiNetworkContext(ssid: "Casa", accessPointIdentifier: "derived-ap"),
            advancedWiFiDiagnostics: AdvancedWiFiDiagnostics(
                capturedAt: Date(),
                ssid: "Casa",
                accessPointIdentifier: "advanced-derived-ap",
                rssiDbm: -51,
                noiseDbm: -92,
                snrDb: 41
            )
        )
        let hints = PlatformHints(wifi: .init(ssid: "Casa", bssid: "AA:BB:CC:DD:EE:FF", rssiDbm: -51))

        let request = NDSRequestBuilder().buildRequest(
            current: measurement,
            platformHints: hints,
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: false
        )
        let data = try JSONEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("Casa"))
        XCTAssertFalse(json.contains("AA:BB:CC:DD:EE:FF"))
        XCTAssertFalse(json.contains("derived-ap"))
        XCTAssertFalse(json.contains("advanced-derived-ap"))
        XCTAssertFalse(json.contains("gateway_ip"))
        XCTAssertFalse(json.contains("gateway_admin_url"))
    }

    func testBuildRequest_forwardsHistoricalEvidenceAsCapability() throws {
        let measurement = NetworkMeasurement(
            outcome: .complete,
            downloadMbps: 100,
            uploadMbps: 50,
            latencyMs: 20
        )
        let historical = NDSRequest.Historical(
            avgDownload30d: 200,
            avgDownload7d: 150,
            tests30d: 8,
            tests7d: 3
        )

        let request = NDSRequestBuilder().buildRequest(
            current: measurement,
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: true,
            historical: historical
        )

        XCTAssertEqual(request.capabilities, ["speed", "quality", "historical"])
        XCTAssertEqual(request.historical, historical)

        let encoded = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let historicalJSON = try XCTUnwrap(json["historical"] as? [String: Any])
        XCTAssertEqual(historicalJSON["avg_download_30d"] as? Double, 200)
        XCTAssertEqual(historicalJSON["avg_download_7d"] as? Double, 150)
        XCTAssertEqual(historicalJSON["tests_30d"] as? Int, 8)
        XCTAssertEqual(historicalJSON["tests_7d"] as? Int, 3)
        XCTAssertNil(historicalJSON["avgDownload30d"])
        XCTAssertNil(historicalJSON["tests30d"])
    }

    /// Issue #129: `speed: {}` (objeto presente, campos vazios) é rejeitado
    /// pelo relay do NDS com RELAY_INVALID_REQUEST — confirmado testando o
    /// payload real contra o serviço em produção. Um teste que aborta antes
    /// do download/upload (`outcome: .partial`) tem as duas velocidades
    /// nil; a chave `speed` precisa ficar ausente, não virar objeto vazio.
    func testBuildRequest_omitsSpeedWhenBothDownloadAndUploadAreNil() throws {
        let measurement = NetworkMeasurement(
            outcome: .partial,
            latencyMs: 22
        )

        let request = NDSRequestBuilder().buildRequest(
            current: measurement,
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: false
        )

        XCTAssertNil(request.speed)

        let encoded = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["speed"])
    }

    /// Basta uma das duas velocidades existir para o objeto `speed` ser
    /// enviado — só as duas ausentes ao mesmo tempo omitem a chave.
    func testBuildRequest_includesSpeedWhenOnlyDownloadIsKnown() throws {
        let measurement = NetworkMeasurement(
            outcome: .partial,
            downloadMbps: 50,
            latencyMs: 22
        )

        let request = NDSRequestBuilder().buildRequest(
            current: measurement,
            platformHints: PlatformHints(),
            appVersion: nil,
            platformIdentifier: "ios",
            requestAI: false
        )

        XCTAssertEqual(request.speed?.downloadMbps, 50)
        XCTAssertNil(request.speed?.uploadMbps)
    }
}
