import XCTest
@testable import NetscopeEvidence
import NetworkCore

final class NetscopeEvidenceTests: XCTestCase {
    func test_projectsOnlyValidAllowlistedMeasurementFacts() {
        let measurement = NetworkMeasurement(
            downloadMbps: 500.5,
            uploadMbps: 80.25,
            latencyMs: 12,
            jitterMs: 1.5,
            packetLossPercent: 0,
            connectionKind: .wifi,
            wifiBandGHz: 5,
            wifiContext: WiFiNetworkContext(
                ssid: "Casa privada",
                accessPointIdentifier: "identificador-local",
                rssiDbm: -58,
                linkSpeedMbps: 1200,
                gatewayIP: "192.168.0.1",
                gatewayVendor: "Fabricante"
            ),
            networkIdentifier: "provedor",
            serverIdentifier: "servidor",
            location: MeasurementLocation(latitude: -23.55, longitude: -46.63)
        )

        let evidence = NetscopeMeasurementEvidenceProjector.project(measurement)

        XCTAssertEqual(evidence.downloadMbps, 500.5)
        XCTAssertEqual(evidence.uploadMbps, 80.25)
        XCTAssertEqual(evidence.latencyMs, 12)
        XCTAssertEqual(evidence.jitterMs, 1.5)
        XCTAssertEqual(evidence.packetLossPercent, 0)
        XCTAssertEqual(evidence.connectionKind, .wifi)
        XCTAssertEqual(evidence.wifiDetails, .init(band: .fiveGHz, linkSpeedMbps: 1200))

        let encoded = try! JSONEncoder().encode(evidence)
        let payload = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(payload.contains("\"band\":\"5ghz\""))
        XCTAssertTrue(payload.contains("\"link_speed_mbps\":1200"))
        XCTAssertFalse(payload.contains("rssi"))
        XCTAssertFalse(payload.contains("Casa privada"))
        XCTAssertFalse(payload.contains("identificador-local"))
        XCTAssertFalse(payload.contains("192.168.0.1"))
        XCTAssertFalse(payload.contains("provedor"))
        XCTAssertFalse(payload.contains("servidor"))
        XCTAssertFalse(payload.contains("latitude"))
    }

    func test_omitsAbsentMetricsAndWifiDetailsWithoutInventingZero() {
        let evidence = NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(connectionKind: .wifi))

        XCTAssertNil(evidence.downloadMbps)
        XCTAssertNil(evidence.uploadMbps)
        XCTAssertNil(evidence.latencyMs)
        XCTAssertNil(evidence.jitterMs)
        XCTAssertNil(evidence.packetLossPercent)
        XCTAssertEqual(evidence.connectionKind, .wifi)
        XCTAssertNil(evidence.wifiDetails)
    }

    func test_omitsInvalidNumbersIndividually() {
        let evidence = NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(
            downloadMbps: -.infinity,
            uploadMbps: 42,
            latencyMs: .nan,
            jitterMs: -0.1,
            packetLossPercent: 100.1,
            connectionKind: .wifi,
            wifiBandGHz: -.infinity,
            wifiContext: WiFiNetworkContext(rssiDbm: .nan, linkSpeedMbps: 0)
        ))

        XCTAssertNil(evidence.downloadMbps)
        XCTAssertEqual(evidence.uploadMbps, 42)
        XCTAssertNil(evidence.latencyMs)
        XCTAssertNil(evidence.jitterMs)
        XCTAssertNil(evidence.packetLossPercent)
        XCTAssertNil(evidence.wifiDetails)
    }

    func test_projectsEveryObservedConnectionKindAndUnknownRoute() {
        XCTAssertEqual(projectedKind(.wifi), .wifi)
        XCTAssertEqual(projectedKind(.cellular), .cellular)
        XCTAssertEqual(projectedKind(.ethernet), .ethernet)
        XCTAssertEqual(projectedKind(.other), .other)
        XCTAssertEqual(projectedKind(nil), .unknown)
    }

    func test_unknownRouteOmitsWifiDetailsEvenWhenWifiFieldsExist() {
        let evidence = NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(
            connectionKind: nil,
            wifiBandGHz: 5,
            wifiContext: WiFiNetworkContext(rssiDbm: -58, linkSpeedMbps: 1200)
        ))

        XCTAssertEqual(evidence.connectionKind, .unknown)
        XCTAssertNil(evidence.wifiDetails)
    }

    func test_routeTransitionProjectsAsUnknownInsteadOfChoosingEitherInterface() {
        let resolvedKind = NetworkConnectionKind.resolve(start: .wifi, end: .cellular)
        let evidence = NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(
            connectionKind: resolvedKind,
            wifiBandGHz: 5,
            wifiContext: WiFiNetworkContext(rssiDbm: -58, linkSpeedMbps: 1200)
        ))

        XCTAssertNil(resolvedKind)
        XCTAssertEqual(evidence.connectionKind, .unknown)
        XCTAssertNil(evidence.wifiDetails)
    }

    func test_wifiDetailsAreOmittedForNonWifiRoutes() {
        for kind in [NetworkConnectionKind.cellular, .ethernet, .other] {
            let measurement = NetworkMeasurement(
                connectionKind: kind,
                wifiBandGHz: 5,
                wifiContext: WiFiNetworkContext(rssiDbm: -58, linkSpeedMbps: 1200)
            )

            XCTAssertNil(NetscopeMeasurementEvidenceProjector.project(measurement).wifiDetails)
        }
    }

    func test_declaredContextStaysSeparateFromObservedEvidence() {
        let input = NetscopeLocalAnalysisInput(
            observedEvidence: NetscopeMeasurementEvidenceProjector.project(
                NetworkMeasurement(connectionKind: .ethernet)
            ),
            declaredContext: NetscopeDeclaredContext(objective: .gaming)
        )

        XCTAssertEqual(input.observedEvidence.connectionKind, .ethernet)
        XCTAssertNil(input.observedEvidence.wifiDetails)
        XCTAssertEqual(input.declaredContext.objective, .gaming)
    }

    func test_onlyWirePermittedBandsAreProjectedAndUnprovenBandIsOmitted() {
        XCTAssertEqual(projectedBand(2.4), .twoPointFourGHz)
        XCTAssertEqual(projectedBand(5), .fiveGHz)
        XCTAssertEqual(projectedBand(6), .sixGHz)
        XCTAssertNil(projectedBand(5.8))
        XCTAssertNil(projectedBand(.nan))
    }

    func test_zeroOrNegativeLinkSpeedIsOmittedRatherThanSentAsObserved() {
        for linkSpeed: Double in [0, -1] {
            let evidence = NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(
                connectionKind: .wifi,
                wifiContext: WiFiNetworkContext(linkSpeedMbps: linkSpeed)
            ))

            XCTAssertNil(evidence.wifiDetails)
        }
    }

    func test_wifiJSONExcludesRssiIdentifiersGatewayAndAdvancedDiagnostics() throws {
        let evidence = NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(
            connectionKind: .wifi,
            wifiBandGHz: 5,
            wifiContext: WiFiNetworkContext(
                ssid: "Casa privada",
                accessPointIdentifier: "local-ap-id",
                rssiDbm: -58,
                linkSpeedMbps: 1200,
                gatewayIP: "192.168.0.1",
                gatewayVendor: "Fabricante",
                gatewayAdminURL: "http://192.168.0.1"
            ),
            advancedWiFiDiagnostics: AdvancedWiFiDiagnostics(
                capturedAt: Date(timeIntervalSince1970: 1),
                wifiStandard: "802.11ax",
                rxRateMbps: 1300,
                txRateMbps: 900,
                noiseDbm: -95,
                channelNumber: 36,
                snrDb: 37
            )
        ))

        let payload = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        XCTAssertEqual(evidence.wifiDetails, .init(band: .fiveGHz, linkSpeedMbps: 1200))
        XCTAssertFalse(payload.contains("rssi"))
        XCTAssertFalse(payload.contains("Casa privada"))
        XCTAssertFalse(payload.contains("local-ap-id"))
        XCTAssertFalse(payload.contains("192.168.0.1"))
        XCTAssertFalse(payload.contains("Fabricante"))
        XCTAssertFalse(payload.contains("802.11ax"))
        XCTAssertFalse(payload.contains("1300"))
        XCTAssertFalse(payload.contains("900"))
        XCTAssertFalse(payload.contains("channelNumber"))
        XCTAssertFalse(payload.contains("snrDb"))
    }

    func test_v1RequestContainsRequiredFieldsAndOmitsAbsentMeasurementFacts() throws {
        let data = try NetscopeV1Codec.encodeRequest(
            input: NetscopeLocalAnalysisInput(
                observedEvidence: NetscopeMeasurementEvidence(
                    downloadMbps: 400,
                    uploadMbps: nil,
                    latencyMs: nil,
                    jitterMs: 2,
                    packetLossPercent: 0,
                    connectionKind: .wifi,
                    wifiDetails: .init(band: .fiveGHz, linkSpeedMbps: nil)
                ),
                declaredContext: .init(objective: .gaming)
            ),
            locale: "pt-BR",
            app: .init(version: "1.2.3", platform: .ios)
        )

        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["schema_version"] as? String, "1.0.0")
        XCTAssertEqual(payload["locale"] as? String, "pt-BR")
        XCTAssertEqual((payload["usage_context"] as? [String: Any])?["objective"] as? String, "gaming")
        XCTAssertEqual((payload["app"] as? [String: Any])?["version"] as? String, "1.2.3")
        XCTAssertEqual((payload["app"] as? [String: Any])?["platform"] as? String, "ios")
        XCTAssertEqual((payload["consent"] as? [String: Any])?["diagnostic_processing"] as? Bool, true)

        let measurement = try XCTUnwrap(payload["measurement"] as? [String: Any])
        XCTAssertEqual(measurement["download_mbps"] as? Double, 400)
        XCTAssertEqual(measurement["jitter_ms"] as? Double, 2)
        XCTAssertEqual(measurement["packet_loss_percent"] as? Double, 0)
        XCTAssertEqual(measurement["connection_kind"] as? String, "wifi")
        XCTAssertNil(measurement["upload_mbps"])
        XCTAssertNil(measurement["latency_ms"])
        XCTAssertEqual((measurement["wifi_details"] as? [String: Any])?["band"] as? String, "5ghz")
        XCTAssertNil((measurement["wifi_details"] as? [String: Any])?["link_speed_mbps"])
    }

    func test_v1RequestRequiresDeclaredObjectiveAndValidMetadata() {
        let input = NetscopeLocalAnalysisInput(
            observedEvidence: NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(connectionKind: .wifi))
        )

        XCTAssertThrowsError(try NetscopeV1Codec.encodeRequest(
            input: input,
            locale: "pt-BR",
            app: .init(version: "1", platform: .ios)
        )) { XCTAssertEqual($0 as? NetscopeV1Codec.Error, .missingUsageObjective) }
        XCTAssertThrowsError(try NetscopeV1Codec.encodeRequest(
            input: input,
            locale: "x",
            app: .init(version: "1", platform: .ios)
        )) { XCTAssertEqual($0 as? NetscopeV1Codec.Error, .invalidLocale) }
    }

    func test_v1RequestSanitizesManuallyConstructedEvidenceAtTheWireBoundary() throws {
        let data = try NetscopeV1Codec.encodeRequest(
            input: .init(
                observedEvidence: .init(
                    downloadMbps: -1,
                    uploadMbps: .infinity,
                    latencyMs: 0,
                    jitterMs: .nan,
                    packetLossPercent: 100.1,
                    connectionKind: .wifi,
                    wifiDetails: .init(band: nil, linkSpeedMbps: 0)
                ),
                declaredContext: .init(objective: .browsing)
            ),
            locale: "en",
            app: .init(version: "1", platform: .macos)
        )

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let measurement = try XCTUnwrap(root["measurement"] as? [String: Any])
        XCTAssertEqual(measurement["latency_ms"] as? Double, 0)
        XCTAssertNil(measurement["download_mbps"])
        XCTAssertNil(measurement["upload_mbps"])
        XCTAssertNil(measurement["jitter_ms"])
        XCTAssertNil(measurement["packet_loss_percent"])
        XCTAssertNil(measurement["wifi_details"])
    }

    func test_v1ResponseDecodesCompletedFixtureStrictly() throws {
        let response = try NetscopeV1Codec.decodeResponse(try fixture("analysis-response-completed"))

        XCTAssertEqual(response.status, .completed)
        XCTAssertEqual(response.requestID, "fixture-completed-001")
        XCTAssertEqual(response.declaredContext?.objective, .gaming)
        XCTAssertEqual(response.assessment?.confidence, .high)
        XCTAssertEqual(response.evidenceUsed?.count, 2)
        XCTAssertEqual(response.evidenceUsed?.first?.value, .number(12.5))
        XCTAssertEqual(response.evidenceUsed?.last?.value, .string("wifi"))
    }

    func test_v1ResponseValidationAcceptsOnlyCanonicalRequestEvidence() throws {
        let input = NetscopeLocalAnalysisInput(
            observedEvidence: .init(
                downloadMbps: 400,
                uploadMbps: nil,
                latencyMs: 12.5,
                jitterMs: nil,
                packetLossPercent: nil,
                connectionKind: .wifi,
                wifiDetails: .init(band: .fiveGHz, linkSpeedMbps: 1_200)
            ),
            declaredContext: .init(objective: .gaming)
        )
        let response = try NetscopeV1Codec.decodeResponse(try fixture("analysis-response-completed"))

        XCTAssertNoThrow(try NetscopeV1Codec.validateResponse(response, for: input))
    }

    func test_v1ResponseValidationRejectsMissingDivergentOrUnsupportedEvidence() throws {
        let input = NetscopeLocalAnalysisInput(
            observedEvidence: .init(
                downloadMbps: nil,
                uploadMbps: nil,
                latencyMs: 12.5,
                jitterMs: nil,
                packetLossPercent: nil,
                connectionKind: .wifi,
                wifiDetails: .init(band: .fiveGHz, linkSpeedMbps: 1_200)
            ),
            declaredContext: .init(objective: .gaming)
        )
        let completed = try fixture("analysis-response-completed")

        let missingMetric = try replacingEvidenceMetric("upload_mbps", at: 0, in: completed)
        XCTAssertValidationFails(missingMetric, for: input)

        let divergentMetric = try replacingEvidenceValue(13, at: 0, in: completed)
        XCTAssertValidationFails(divergentMetric, for: input)

        let unsupportedMetric = try replacingEvidenceMetric("dns_resolution_ms", at: 0, in: completed)
        XCTAssertValidationFails(unsupportedMetric, for: input)
    }

    func test_v1ResponseValidationRejectsWrongEvidenceTypeAndMismatchedObjective() throws {
        let input = NetscopeLocalAnalysisInput(
            observedEvidence: .init(
                downloadMbps: nil,
                uploadMbps: nil,
                latencyMs: 12.5,
                jitterMs: nil,
                packetLossPercent: nil,
                connectionKind: .wifi,
                wifiDetails: nil
            ),
            declaredContext: .init(objective: .gaming)
        )
        let completed = try fixture("analysis-response-completed")

        let wrongType = try replacingEvidenceValue("12.5", at: 0, in: completed)
        XCTAssertValidationFails(wrongType, for: input)

        let mismatchedObjective = try replacingDeclaredObjective("streaming", in: completed)
        XCTAssertValidationFails(mismatchedObjective, for: input)
    }

    func test_v1ResponseValidationUsesWireSanitizationInsteadOfRawEvidence() throws {
        let input = NetscopeLocalAnalysisInput(
            observedEvidence: .init(
                downloadMbps: nil,
                uploadMbps: nil,
                latencyMs: .nan,
                jitterMs: nil,
                packetLossPercent: nil,
                connectionKind: .wifi,
                wifiDetails: nil
            ),
            declaredContext: .init(objective: .gaming)
        )
        let response = try NetscopeV1Codec.decodeResponse(try fixture("analysis-response-completed"))

        XCTAssertThrowsError(try NetscopeV1Codec.validateResponse(response, for: input)) {
            XCTAssertEqual($0 as? NetscopeV1Codec.Error, .responseDoesNotMatchRequest)
        }
    }

    func test_v1ResponseDecodesUnavailableFixtureWithoutConclusion() throws {
        let response = try NetscopeV1Codec.decodeResponse(try fixture("analysis-response-unavailable"))

        XCTAssertEqual(response.status, .unavailable)
        XCTAssertNil(response.assessment)
        XCTAssertNil(response.evidenceUsed)
        XCTAssertEqual(response.limitations, ["A análise não está disponível agora."])
    }

    func test_v1ResponseDecodesInconclusiveFixtureWithoutAssessment() throws {
        let response = try NetscopeV1Codec.decodeResponse(try fixture("analysis-response-inconclusive"))

        XCTAssertEqual(response.status, .inconclusive)
        XCTAssertEqual(response.requestID, "fixture-inconclusive-001")
        XCTAssertEqual(response.declaredContext?.objective, .streaming)
        XCTAssertNil(response.assessment)
        XCTAssertEqual(response.evidenceUsed?.first?.metric, .packetLossPercent)
        XCTAssertEqual(response.evidenceUsed?.first?.value, .number(0))
        XCTAssertEqual(response.nextAction?.steps, ["Repita a medição em alguns minutos."])
    }

    func test_v1ResponseDecodesOutOfScopeFixtureWithoutConclusionOrEvidence() throws {
        let response = try NetscopeV1Codec.decodeResponse(try fixture("analysis-response-out-of-scope"))

        XCTAssertEqual(response.status, .outOfScope)
        XCTAssertEqual(response.requestID, "fixture-out-of-scope-001")
        XCTAssertNil(response.assessment)
        XCTAssertNil(response.evidenceUsed)
        XCTAssertEqual(response.limitations, ["A solicitação não pertence ao escopo desta análise."])
    }

    func test_v1ResponseRejectsExtraPropertyAndInvalidStatusCombinations() throws {
        let completed = try fixture("analysis-response-completed")
        let unavailable = try fixture("analysis-response-unavailable")

        XCTAssertThrowsError(try NetscopeV1Codec.decodeResponse(try adding("unexpected", value: true, to: completed)))
        XCTAssertThrowsError(try NetscopeV1Codec.decodeResponse(try adding("unexpected", value: true, toNested: "assessment", in: completed)))
        XCTAssertThrowsError(try NetscopeV1Codec.decodeResponse(try adding("assessment", value: [
            "title": "não permitido", "summary": "não permitido", "confidence": "low"
        ], to: unavailable)))
        XCTAssertThrowsError(try NetscopeV1Codec.decodeResponse(try removing("assessment", from: completed)))
        XCTAssertThrowsError(try NetscopeV1Codec.decodeResponse(Data("""
        {"schema_version":"1.0.0","request_id":"i","status":"inconclusive","assessment":{"title":"x","summary":"x","confidence":"low"},"limitations":["x"]}
        """.utf8)))
        XCTAssertThrowsError(try NetscopeV1Codec.decodeResponse(Data("""
        {"schema_version":"1.0.0","request_id":"i","status":"inconclusive","evidence_used":[],"limitations":["x"]}
        """.utf8)))
    }

    private func projectedBand(_ gigahertz: Double?) -> NetscopeMeasurementEvidence.WiFiDetails.Band? {
        NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(
            connectionKind: .wifi,
            wifiBandGHz: gigahertz
        )).wifiDetails?.band
    }

    private func projectedKind(_ kind: NetworkConnectionKind?) -> NetscopeMeasurementEvidence.ConnectionKind {
        NetscopeMeasurementEvidenceProjector.project(NetworkMeasurement(connectionKind: kind)).connectionKind
    }

    private func fixture(_ name: String) throws -> Data {
        let path = try XCTUnwrap(Bundle.module.path(forResource: name, ofType: "json"))
        return Data(try String(contentsOfFile: path).utf8)
    }

    private func adding(_ key: String, value: Any, to data: Data) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func removing(_ key: String, from data: Data) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func adding(_ key: String, value: Any, toNested nestedKey: String, in data: Data) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var nested = try XCTUnwrap(object[nestedKey] as? [String: Any])
        nested[key] = value
        object[nestedKey] = nested
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func XCTAssertValidationFails(
        _ data: Data,
        for input: NetscopeLocalAnalysisInput,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try NetscopeV1Codec.validateResponse(try NetscopeV1Codec.decodeResponse(data), for: input),
            file: file,
            line: line
        ) { XCTAssertEqual($0 as? NetscopeV1Codec.Error, .responseDoesNotMatchRequest, file: file, line: line) }
    }

    private func replacingEvidenceValue(_ value: Any, at index: Int, in data: Data) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var evidence = try XCTUnwrap(object["evidence_used"] as? [[String: Any]])
        evidence[index]["value"] = value
        object["evidence_used"] = evidence
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func replacingEvidenceMetric(_ metric: String, at index: Int, in data: Data) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var evidence = try XCTUnwrap(object["evidence_used"] as? [[String: Any]])
        evidence[index]["metric"] = metric
        object["evidence_used"] = evidence
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func replacingDeclaredObjective(_ objective: String, in data: Data) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["declared_context"] = ["objective": objective]
        return try JSONSerialization.data(withJSONObject: object)
    }
}
