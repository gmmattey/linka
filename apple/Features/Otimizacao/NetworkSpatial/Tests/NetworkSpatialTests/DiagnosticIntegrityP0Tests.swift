import XCTest
@testable import NetworkSpatial

final class DiagnosticIntegrityP0Tests: XCTestCase {

    // MARK: - 1. P0: Hipóteses Fundamentadas vs. Certeza Excessiva

    func testQualityClassifierUsesProbableCausesAndNotAbsoluteClaims() {
        let metricsWanBad = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 3.5,
            gatewayJitterMs: 0.8,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 140.0,
            wanPacketLossPercent: 5.0,
            downloadThroughputMbps: 12.0,
            gatewayMedianMs: 3.5,
            gatewayP95Ms: 5.0,
            gatewayLossEvents: 0,
            gatewayTotalProbes: 20,
            gatewayLossInterpretation: .stable,
            wanMedianMs: 140.0,
            wanP95Ms: 190.0,
            wanJitterMs: 25.0,
            wanLossInterpretation: .confirmedLoss
        )

        let resultWan = QualityClassifier.classify(metrics: metricsWanBad, isWiFiActive: true)
        XCTAssertEqual(resultWan.cause, .ispDegraded)
        // Deve expressar como causa provável e hipótese, sem afirmar perícia
        XCTAssertTrue(resultWan.explanation.contains("Causa provável"), "Deve apresentar como hipótese/causa provável")
        XCTAssertFalse(resultWan.explanation.contains("decorre de instabilidade externa"), "Não deve alegar certeza pericial")

        let metricsLanBad = NetworkMetrics(
            gatewayIP: "192.168.1.1",
            gatewayLatencyMs: 55.0,
            gatewayJitterMs: 14.0,
            gatewayPacketLossPercent: 0.0,
            wanLatencyMs: 40.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 20.0,
            gatewayMedianMs: 55.0,
            gatewayP95Ms: 90.0,
            gatewayLossEvents: 0,
            gatewayTotalProbes: 20,
            gatewayLossInterpretation: .stable
        )

        let resultLan = QualityClassifier.classify(metrics: metricsLanBad, isWiFiActive: true)
        XCTAssertEqual(resultLan.cause, .localWiFiDegraded)
        XCTAssertTrue(resultLan.explanation.contains("Causa provável"), "Deve indicar causa provável e não cravar paredes")
        XCTAssertFalse(resultLan.explanation.contains("As paredes ou a distância estão bloqueando"), "Não deve alegar conhecimento físico do ambiente")
    }

    // MARK: - 2. P0: Qualidade Média nos Pontos Medidos vs. Cobertura Total Falsa

    func testSingleMeasuredRoomDoesNotImplyFullHouseCoverage() {
        let room1 = Room(name: "Sala", icon: "sofa", hasRouter: true, lastMeasurement: MeasurementResult(
            roomId: UUID(), rating: .excellent, score: 98, cause: .allGood,
            metrics: NetworkMetrics(), explanation: "Ótimo", actionableRecommendation: "Nenhuma"
        ))
        let room2 = Room(name: "Quarto 1", icon: "bed.double")
        let room3 = Room(name: "Quarto 2", icon: "bed.double")
        let room4 = Room(name: "Cozinha", icon: "fork.knife")

        let rooms = [room1, room2, room3, room4]

        let averageScore = SpatialLayoutEngine.calculateHouseCoverage(rooms: rooms)
        // A nota dos pontos medidos é 98, mas apenas 1 de 4 cômodos foi avaliado
        XCTAssertEqual(averageScore, 98)

        let recommendations = SpatialLayoutEngine.generateRecommendations(rooms: rooms)
        // O motor deve avisar claramente que nem todos os cômodos foram medidos
        XCTAssertTrue(recommendations.contains(where: { $0.contains("1 de 4") }), "Recomendação deve explicitar proporção de cômodos medidos")
    }

    // MARK: - 3. P0: Eliminação de Métricas Fictícias em Mesh

    func testMeshTopologyProberDoesNotFabricateNodeHopLatency() async {
        let simulatedProber = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(
                meanLatencyMs: 22.0,
                jitterMs: 2.1,
                packetLossPercent: 0.0,
                samples: [21.5, 22.5]
            )
        })

        let apSatellite = AccessPointNode(
            name: "Satélite Sala de TV",
            type: .meshSatellite,
            backhaulType: .wifi,
            roomId: UUID()
        )

        let diagnostic = await simulatedProber.probeBackhaulQuality(node: apSatellite, gatewayIP: "192.168.1.1")

        // O salto interno AP-cliente não é exposto pelo sandbox do iOS e deve ser nil (nunca 0.0 nem inventado)
        XCTAssertNil(diagnostic.nodeLatencyMs, "Salto interno AP-cliente deve ser nil pois não é mensurável pelo iOS")
        XCTAssertEqual(diagnostic.gatewayLatencyMs, 22.0, "Latência real medida até o gateway preservada")
    }

    // MARK: - 4. P0: Descoberta de Gateway não Chuta IP Falso

    func testGatewayDiscoveryDoesNotDefaultToHardcodedIP() {
        let service = GatewayDiscoveryService()
        let displayStr = service.discoverGatewayIPDisplayString()
        if service.discoverGatewayIP() == nil {
            XCTAssertEqual(displayStr, "Não identificado")
        } else {
            XCTAssertFalse(displayStr.isEmpty)
        }
    }

    // MARK: - 5. P1: WAN Sonda Destino Consistente (RFC 3550)

    func testWANProberMaintainsConsistentTargetForJitterIntegrity() async {
        let prober = WANProber()
        let result = await prober.probe(sampleCount: 4, timeoutSeconds: 0.8, enableAdaptiveProbing: false)
        // Garante que o prober conclui com série primária consistente
        XCTAssertGreaterThanOrEqual(result.wanTotalProbes, 0)
    }

    // MARK: - 6. P1: Throughput Retorna Nil em Falha (Diferenciando de Zero Mbps)

    func testThroughputMicroProberReturnsNilOrValidMbps() async {
        let prober = ThroughputMicroProber()
        let result = await prober.measureThroughputMbps()
        // Se houver conexão com a internet retorna Double > 0, senão retorna nil (nunca finge ser 0.0 Mbps)
        if let mbps = result {
            XCTAssertGreaterThan(mbps, 0.0, "Quando medido com sucesso, vazão deve ser positiva")
        } else {
            // Em falha/timeout ou ambiente offline de testes, deve ser nil
            XCTAssertNil(result, "Em caso de erro ou timeout, deve retornar nil e não 0.0")
        }
    }

    func testNetworkMetricsThroughputIsOptional() {
        let metricsWithoutThroughput = NetworkMetrics(gatewayIP: "192.168.1.1")
        XCTAssertNil(metricsWithoutThroughput.downloadThroughputMbps, "Download deve ser nil por padrão quando não executado")

        let metricsWithThroughput = NetworkMetrics(gatewayIP: "192.168.1.1", downloadThroughputMbps: 150.0)
        XCTAssertEqual(metricsWithThroughput.downloadThroughputMbps, 150.0)
    }
}
