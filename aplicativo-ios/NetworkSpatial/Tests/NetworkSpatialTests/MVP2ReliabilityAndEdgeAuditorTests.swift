import XCTest
import SwiftUI
@testable import NetworkSpatial

@MainActor
final class MVP2ReliabilityAndEdgeAuditorTests: XCTestCase {

    // MARK: - 1. Verificação de Regressão do MVP 1

    func testMVP1CoreHouseAndRoomEditingIntegrity() {
        let salaId = UUID()
        let cozinhaId = UUID()
        let quartoId = UUID()

        var house = House(
            name: "Residência Padrão MVP 1",
            rooms: [
                Room(id: salaId, name: "Sala", icon: "sofa", gridX: 0, gridY: 0, hasRouter: true),
                Room(id: cozinhaId, name: "Cozinha", icon: "fork.knife", gridX: 1, gridY: 0, hasRouter: false),
                Room(id: quartoId, name: "Quarto", icon: "bed.double", gridX: 0, gridY: 1, hasRouter: false)
            ]
        )

        XCTAssertEqual(house.rooms.count, 3)
        XCTAssertEqual(house.totalCoveragePercent, 0, "Sem medições, cobertura deve ser 0%")

        // Adiciona medição excelente na Sala
        let salaMeasurement = MeasurementResult(
            roomId: salaId,
            rating: .excellent,
            score: 95,
            cause: .allGood,
            metrics: NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 3.5,
                gatewayJitterMs: 0.8,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 14.2,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 350.0
            ),
            explanation: "Conexão de excelente qualidade.",
            actionableRecommendation: "Sua rede está perfeitamente ajustada."
        )
        house.rooms[0].lastMeasurement = salaMeasurement

        // 1 cômodo medido de 3 com score 95 = média 95%
        XCTAssertEqual(house.totalCoveragePercent, 95)
        XCTAssertEqual(house.rooms[0].currentRating, .excellent)
        XCTAssertEqual(house.rooms[1].currentRating, .unmeasured)

        // Adiciona um novo cômodo manualmente (Regressão do Editor 2D)
        let novoEscritorio = Room(
            name: "Escritório",
            icon: "laptopcomputer",
            gridX: 1,
            gridY: 1,
            hasRouter: false
        )
        house.rooms.append(novoEscritorio)
        XCTAssertEqual(house.rooms.count, 4)
        XCTAssertEqual(house.totalCoveragePercent, 95, "Total de cômodos medidos continua 1 (score 95)")
    }

    func testMVP1BeforeAfterComparisonEngine() {
        let salaId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let quartoId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let baselineRooms = [
            Room(id: salaId, name: "Sala", icon: "sofa", hasRouter: true, lastMeasurement: MeasurementResult(
                roomId: salaId, rating: .good, score: 80, cause: .allGood,
                metrics: NetworkMetrics(gatewayIP: "192.168.1.1", gatewayLatencyMs: 12.0, gatewayJitterMs: 2.0, gatewayPacketLossPercent: 0.0, wanLatencyMs: 25.0, wanPacketLossPercent: 0.0, downloadThroughputMbps: 100.0),
                explanation: "", actionableRecommendation: ""
            )),
            Room(id: quartoId, name: "Quarto Fundos", icon: "bed.double", hasRouter: false, lastMeasurement: MeasurementResult(
                roomId: quartoId, rating: .poor, score: 30, cause: .localWiFiDegraded,
                metrics: NetworkMetrics(gatewayIP: "192.168.1.1", gatewayLatencyMs: 85.0, gatewayJitterMs: 20.0, gatewayPacketLossPercent: 12.0, wanLatencyMs: 95.0, wanPacketLossPercent: 12.0, downloadThroughputMbps: 10.0),
                explanation: "", actionableRecommendation: ""
            ))
        ]

        let afterRooms = [
            Room(id: salaId, name: "Sala", icon: "sofa", hasRouter: true, lastMeasurement: MeasurementResult(
                roomId: salaId, rating: .excellent, score: 92, cause: .allGood,
                metrics: NetworkMetrics(gatewayIP: "192.168.1.1", gatewayLatencyMs: 4.0, gatewayJitterMs: 1.0, gatewayPacketLossPercent: 0.0, wanLatencyMs: 18.0, wanPacketLossPercent: 0.0, downloadThroughputMbps: 250.0),
                explanation: "", actionableRecommendation: ""
            )),
            Room(id: quartoId, name: "Quarto Fundos", icon: "bed.double", hasRouter: false, lastMeasurement: MeasurementResult(
                roomId: quartoId, rating: .good, score: 78, cause: .allGood,
                metrics: NetworkMetrics(gatewayIP: "192.168.1.1", gatewayLatencyMs: 15.0, gatewayJitterMs: 3.0, gatewayPacketLossPercent: 0.0, wanLatencyMs: 28.0, wanPacketLossPercent: 0.0, downloadThroughputMbps: 120.0),
                explanation: "", actionableRecommendation: ""
            ))
        ]

        let comparison = SpatialLayoutEngine.generateComparison(
            title: "Otimização Teste",
            baselineRooms: baselineRooms,
            afterRooms: afterRooms
        )

        XCTAssertEqual(comparison.baselineCoveragePercent, 55)
        XCTAssertEqual(comparison.afterCoveragePercent, 85)
        XCTAssertEqual(comparison.deltaCoveragePercent, 30) // +30%
        XCTAssertEqual(comparison.roomComparisons.count, 2)
        XCTAssertTrue(comparison.roomComparisons.allSatisfy { $0.deltaScore > 0 })
    }

    // MARK: - 3. Cenários de Borda: RoomPlan & Sanitização de Áreas Extremas

    func testRoomPlanAreaAndDimensionExtremeEdgeCases() {
        let extremeCapturedRooms: [CapturedRoomData] = [
            // Área negativa
            CapturedRoomData(suggestedName: "Cômodo Negativo", areaSqMeters: -15.0, boundingWidthMeters: -4.0, boundingLengthMeters: 3.0),
            // Área zero
            CapturedRoomData(suggestedName: "Cômodo Zero", areaSqMeters: 0.0, boundingWidthMeters: 0.0, boundingLengthMeters: 0.0),
            // Área microscópica
            CapturedRoomData(suggestedName: "Cômodo Micro", areaSqMeters: 0.1, boundingWidthMeters: 0.2, boundingLengthMeters: 0.5),
            // Área colossal
            CapturedRoomData(suggestedName: "Cômodo Gigante", areaSqMeters: 1800.0, boundingWidthMeters: 120.0, boundingLengthMeters: 15.0)
        ]

        // Conversão com roteador default preservando integridade e clampando limites
        let convertedRooms = RoomPlanParser.convertCapturedRoomsToHouseRooms(
            capturedRooms: extremeCapturedRooms,
            defaultRouterRoomIndex: 1
        )
        XCTAssertEqual(convertedRooms.count, 4)

        // Verificação de limites estritos: área clampada entre 1.0 m² e 500.0 m²
        XCTAssertEqual(convertedRooms[0].floorAreaSqMeters, 1.0)
        XCTAssertEqual(convertedRooms[1].floorAreaSqMeters, 1.0)
        XCTAssertEqual(convertedRooms[2].floorAreaSqMeters, 1.0)
        XCTAssertEqual(convertedRooms[3].floorAreaSqMeters, 500.0)

        XCTAssertFalse(convertedRooms[0].hasRouter)
        XCTAssertTrue(convertedRooms[1].hasRouter)
        XCTAssertEqual(convertedRooms[1].accessPoint?.type, .mainRouter)
        XCTAssertFalse(convertedRooms[2].hasRouter)
        XCTAssertFalse(convertedRooms[3].hasRouter)
    }

    // MARK: - 4. Cenários de Borda: Topologia Mesh e Roteador Único

    func testSingleMainRouterRuleEnforcement() {
        var rooms = [
            Room(id: UUID(), name: "Sala", icon: "sofa", hasRouter: true, lastMeasurement: nil, accessPoint: AccessPointNode(name: "Roteador Antigo", type: .mainRouter, backhaulType: .ethernet, roomId: UUID())),
            Room(id: UUID(), name: "Quarto", icon: "bed.double", hasRouter: false, lastMeasurement: nil, accessPoint: nil),
            Room(id: UUID(), name: "Corredor", icon: "door.left.hand.open", hasRouter: false, lastMeasurement: nil, accessPoint: AccessPointNode(name: "Satélite", type: .meshSatellite, backhaulType: .wifi, roomId: UUID()))
        ]

        // Nova atribuição: Quarto passa a ser Roteador Principal
        let targetId = rooms[1].id
        for i in rooms.indices {
            if rooms[i].id != targetId && (rooms[i].hasRouter || rooms[i].accessPoint?.type == .mainRouter) {
                rooms[i].hasRouter = false
                rooms[i].accessPoint = nil
            }
        }
        rooms[1].hasRouter = true
        rooms[1].accessPoint = AccessPointNode(name: "Novo Roteador Principal", type: .mainRouter, backhaulType: .ethernet, roomId: targetId)

        // Garantir que a casa tenha exatamente 1 roteador principal
        let mainRouters = rooms.filter { $0.hasRouter || $0.accessPoint?.type == .mainRouter }
        XCTAssertEqual(mainRouters.count, 1)
        XCTAssertEqual(mainRouters.first?.name, "Quarto")
        XCTAssertNil(rooms[0].accessPoint)
        XCTAssertFalse(rooms[0].hasRouter)
        XCTAssertEqual(rooms[2].accessPoint?.type, .meshSatellite, "Satélite Mesh do corredor deve permanecer inalterado")
    }

    func testMeshBackhaulDegradationAndEthernetStability() async {
        let simulatedProber = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(
                meanLatencyMs: 48.0,
                jitterMs: 9.0,
                packetLossPercent: 4.5,
                samples: [45.0, 51.0]
            )
        })

        let guestRoomId = UUID()
        let officeRoomId = UUID()

        // Satélite com backhaul Wi-Fi e latência alta de gateway
        let apPoor = AccessPointNode(name: "Satélite Andar Superior", type: .meshSatellite, backhaulType: .wifi, roomId: guestRoomId)
        let diagnosis = await simulatedProber.probeBackhaulQuality(node: apPoor, gatewayIP: "192.168.1.1")

        XCTAssertEqual(diagnosis.linkQuality, .fair)
        XCTAssertNotNil(diagnosis.recommendation)
        XCTAssertTrue(diagnosis.recommendation?.contains("Aproxime o satélite") == true)

        // Satélite com backhaul Ethernet (Cabo)
        let prober = MeshTopologyProber(customProbeHandler: { _ in
            LatencyProbeResult(meanLatencyMs: 1.5, jitterMs: 0.2, packetLossPercent: 0.0, samples: [1.5])
        })
        let apEthernet = AccessPointNode(name: "Satélite Escritório", type: .meshSatellite, backhaulType: .ethernet, roomId: officeRoomId)
        let ethDiagnosis = await prober.probeBackhaulQuality(node: apEthernet, gatewayIP: "192.168.1.1")

        XCTAssertEqual(ethDiagnosis.linkQuality, .excellent)
        XCTAssertEqual(ethDiagnosis.backhaulType, .ethernet)
        XCTAssertNil(ethDiagnosis.nodeLatencyMs)
        XCTAssertNil(ethDiagnosis.recommendation)
    }

    // MARK: - 5. Integridade Rigorosa de Arquivo PDF

    func testPDFGeneratedDocumentIntegrityAndHeaders() throws {
        let livingId = UUID()
        let suiteId = UUID()

        let rooms = [
            Room(id: livingId, name: "Living", icon: "sofa", hasRouter: true, lastMeasurement: MeasurementResult(
                roomId: livingId, rating: .excellent, score: 96, cause: .allGood,
                metrics: NetworkMetrics(gatewayIP: "192.168.1.1", gatewayLatencyMs: 2.5, gatewayJitterMs: 0.4, gatewayPacketLossPercent: 0.0, wanLatencyMs: 14.0, wanPacketLossPercent: 0.0, downloadThroughputMbps: 450.0),
                explanation: "Excelente", actionableRecommendation: "Perfeito"
            ), accessPoint: AccessPointNode(name: "Roteador AX6000", type: .mainRouter, backhaulType: .ethernet, roomId: livingId)),
            Room(id: suiteId, name: "Suíte Master", icon: "bed.double", hasRouter: false, lastMeasurement: MeasurementResult(
                roomId: suiteId, rating: .good, score: 82, cause: .allGood,
                metrics: NetworkMetrics(gatewayIP: "192.168.1.1", gatewayLatencyMs: 8.5, gatewayJitterMs: 1.2, gatewayPacketLossPercent: 0.0, wanLatencyMs: 22.0, wanPacketLossPercent: 0.0, downloadThroughputMbps: 200.0),
                explanation: "Bom", actionableRecommendation: "Estável"
            ), accessPoint: AccessPointNode(name: "Nó Mesh Suíte", type: .meshSatellite, backhaulType: .wifi, roomId: suiteId))
        ]

        let reportData = TechnicalAuditReportData(
            houseName: "Cobertura Jardins",
            generatedDate: Date(),
            ssid: "Linka-5G",
            gatewayIP: "192.168.1.1",
            accessPoints: rooms.compactMap(\.accessPoint),
            rooms: rooms,
            totalCoveragePercent: 89,
            executiveSummary: "Auditoria técnica residencial executada com alto rigor.",
            ispTechnicalNotice: "O enlace sem fio interno opera dentro das especificações de baixa latência."
        )

        let fileURL = try PDFReportGenerator.generateAuditReportPDF(data: reportData)

        // 1. Arquivo deve existir
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // 2. Tamanho deve ser expressivo (> 10KB devido à renderização vetorial e diagramação de alta densidade)
        let data = try Data(contentsOf: fileURL)
        XCTAssertGreaterThan(data.count, 10 * 1024, "Relatório técnico PDF deve ter mais de 10 KB")

        // 3. Cabeçalho binário padrão PDF: '%PDF-1.'
        let prefix = String(data: data.prefix(7), encoding: .ascii)
        XCTAssertTrue(prefix?.hasPrefix("%PDF-1.") ?? false, "O arquivo deve ser um documento PDF válido iniciando com '%PDF-1.'")
    }

    // MARK: - 5. Regras de Disparo do Ecossistema (Cross-App)

    func testEcosystemTriggerExclusivity() {
        let roomId = UUID()
        let roomDefault = Room(id: roomId, name: "Sala de Estar", icon: "sofa")

        // 1. Causa: .ispDegraded (Wi-Fi local bom, problema no link externo da operadora) -> Dispara Linka
        let ispDegradedResult = MeasurementResult(
            roomId: roomId,
            rating: .poor,
            score: 40,
            cause: .ispDegraded,
            metrics: NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 2.1,
                gatewayJitterMs: 0.4,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 180.0,
                wanPacketLossPercent: 8.0,
                downloadThroughputMbps: 12.0
            ),
            explanation: "O enlace Wi-Fi local está excelente, mas a rota externa da operadora apresenta latência alta e perda.",
            actionableRecommendation: "Contate a operadora."
        )
        let linkaTrigger = EcosystemTriggerEngine.evaluateTrigger(for: ispDegradedResult, room: roomDefault)
        XCTAssertNotNil(linkaTrigger)
        XCTAssertEqual(linkaTrigger?.appTitle, "Linka")
        XCTAssertTrue(linkaTrigger?.deepLinkURL.scheme == "linka")
        XCTAssertTrue(linkaTrigger?.deepLinkURL.absoluteString.contains("referrer=linka_spatial") ?? false)

        // 2. Falha puramente local: .localWiFiDegraded -> NENHUM disparo de SignallQ ou LagCheck
        let localWiFiFailureResult = MeasurementResult(
            roomId: roomId,
            rating: .poor,
            score: 25,
            cause: .localWiFiDegraded,
            metrics: NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 90.0,
                gatewayJitterMs: 25.0,
                gatewayPacketLossPercent: 15.0,
                wanLatencyMs: 110.0,
                wanPacketLossPercent: 15.0,
                downloadThroughputMbps: 5.0
            ),
            explanation: "Sinal Wi-Fi fraco devido à distância das paredes.",
            actionableRecommendation: "Aproxime-se do roteador."
        )
        let noTriggerForLocalIssue = EcosystemTriggerEngine.evaluateTrigger(for: localWiFiFailureResult, room: roomDefault)
        XCTAssertNil(noTriggerForLocalIssue, "Falha estritamente local não pode sugerir app de auditoria de provedor")

        // 3. Jitter elevado (> 15ms) em conexão não degradada por ISP -> Dispara LagCheck
        let highJitterResult = MeasurementResult(
            roomId: roomId,
            rating: .fair,
            score: 65,
            cause: .allGood,
            metrics: NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 18.0,
                gatewayJitterMs: 22.5,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 32.0,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 120.0
            ),
            explanation: "Variação brusca de tempo de resposta entre pacotes.",
            actionableRecommendation: "Evite interferência de aparelhos sem fio."
        )
        let lagCheckTrigger = EcosystemTriggerEngine.evaluateTrigger(for: highJitterResult, room: roomDefault)
        XCTAssertNotNil(lagCheckTrigger)
        XCTAssertEqual(lagCheckTrigger?.appTitle, "Lagcheck")
        XCTAssertTrue(lagCheckTrigger?.deepLinkURL.scheme == "lagcheck")
        XCTAssertEqual(lagCheckTrigger?.deepLinkURL.absoluteString, "lagcheck://quicktest?referrer=linka_spatial")

        // 4. Cômodo Gamer com jitter moderado -> Dispara LagCheck
        let gamerRoomId = UUID()
        let gamingRoom = Room(id: gamerRoomId, name: "Quarto Gamer", icon: "gamecontroller")
        let gamingResult = MeasurementResult(
            roomId: gamerRoomId,
            rating: .good,
            score: 75,
            cause: .allGood,
            metrics: NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 8.0,
                gatewayJitterMs: 6.0,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 22.0,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 180.0
            ),
            explanation: "Estável.",
            actionableRecommendation: "Otimizado para jogos."
        )
        let lagCheckGamingTrigger = EcosystemTriggerEngine.evaluateTrigger(for: gamingResult, room: gamingRoom)
        XCTAssertNotNil(lagCheckGamingTrigger)
        XCTAssertEqual(lagCheckGamingTrigger?.appTitle, "Lagcheck")
    }

    // MARK: - 7. Auditoria de Acessibilidade: Independência de Cores e Semântica

    func testAccessibilityColorIndependenceAndSymbols() {
        // Garantir que todas as classificações de qualidade possuem símbolos e rótulos explícitos
        for rating in QualityRating.allCases {
            XCTAssertFalse(rating.label.isEmpty, "QualityRating deve ter texto explicativo explícito")
            XCTAssertFalse(rating.systemImage.isEmpty, "QualityRating deve ter SF Symbol associado")
        }

        // Garantir que todos os tipos de pontos de acesso possuem rótulo, ícone e descrição VoiceOver
        for apType in AccessPointType.allCases {
            XCTAssertFalse(apType.label.isEmpty)
            XCTAssertFalse(apType.systemImage.isEmpty)
            XCTAssertFalse(apType.accessibilityDescription.isEmpty)
        }

        // Garantir que as tags de diagnóstico possuem SF Symbol semântico
        let tags: [DiagnosisTag] = [.healthy, .weakWiFi, .slowProvider, .unmeasured]
        for tag in tags {
            XCTAssertFalse(tag.rawValue.isEmpty)
            XCTAssertFalse(tag.systemImage.isEmpty)
        }
    }
}
