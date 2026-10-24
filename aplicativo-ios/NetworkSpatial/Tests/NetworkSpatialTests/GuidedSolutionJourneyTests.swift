import XCTest
@testable import NetworkSpatial

final class GuidedSolutionJourneyTests: XCTestCase {

    private func makeMeasurement(
        roomId: UUID = UUID(),
        rating: QualityRating = .good,
        score: Int = 80,
        lanMs: Double = 10.0,
        lanLoss: Double = 0.0,
        lanJitter: Double = 2.0,
        wanMs: Double = 25.0,
        wanLoss: Double = 0.0,
        wanJitter: Double = 3.0,
        throughput: Double? = 100.0
    ) -> MeasurementResult {
        MeasurementResult(
            id: UUID(),
            roomId: roomId,
            timestamp: Date(),
            rating: rating,
            score: score,
            cause: .allGood,
            metrics: NetworkMetrics(
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: lanMs,
                gatewayJitterMs: lanJitter,
                gatewayPacketLossPercent: lanLoss,
                wanLatencyMs: wanMs,
                wanPacketLossPercent: wanLoss,
                downloadThroughputMbps: throughput,
                gatewayMedianMs: lanMs,
                wanMedianMs: wanMs,
                wanJitterMs: wanJitter
            ),
            explanation: "Teste",
            actionableRecommendation: "Teste"
        )
    }

    // MARK: - Análise de 2 Pontos (Base vs Cômodo)

    func testTwoPointAnalysis_DetectsISPBottleneckAtOrigin() {
        // Base já chega com 120 ms de WAN e 3% de perda
        let base = makeMeasurement(score: 70, lanMs: 3.0, wanMs: 120.0, wanLoss: 3.0)
        let target = makeMeasurement(score: 65, lanMs: 8.0, wanMs: 130.0, wanLoss: 3.5)

        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: target)

        XCTAssertEqual(analysis.bottleneck, .ispProvider)
        XCTAssertEqual(analysis.confidence, .high)
        XCTAssertTrue(analysis.explanation.contains("Mesmo ao lado do roteador"))
        XCTAssertTrue(analysis.explanation.contains("operadora"))
    }

    func testTwoPointAnalysis_DetectsPhysicalDistanceOrObstacles() {
        // Base perfeita (3 ms LAN), cômodo sofre atenuação severa (45 ms LAN, delta +42 ms)
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let target = makeMeasurement(rating: .poor, score: 35, lanMs: 45.0, lanLoss: 3.0, wanMs: 65.0)

        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: target)

        XCTAssertEqual(analysis.bottleneck, .localDistanceOrObstacle)
        XCTAssertEqual(analysis.confidence, .high)
        XCTAssertTrue(analysis.explanation.contains("O sinal sai perfeito da base"))
        XCTAssertTrue(analysis.explanation.contains("paredes grossas") || analysis.explanation.contains("distância física"))
    }

    func testTwoPointAnalysis_DetectsLocalInterference() {
        // Base rápida, cômodo com latência média baixa mas jitter alto (16 ms)
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let target = makeMeasurement(rating: .fair, score: 60, lanMs: 12.0, lanJitter: 16.0, wanMs: 30.0)

        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: target)

        XCTAssertEqual(analysis.bottleneck, .localInterference)
        XCTAssertEqual(analysis.confidence, .medium)
        XCTAssertTrue(analysis.explanation.contains("nicho fechado") || analysis.explanation.contains("interferência"))
    }

    func testTwoPointAnalysis_DetectsHealthyConnection() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let target = makeMeasurement(rating: .excellent, score: 90, lanMs: 6.0, wanMs: 22.0)

        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: target)

        XCTAssertEqual(analysis.bottleneck, .healthy)
        XCTAssertEqual(analysis.confidence, .high)
        XCTAssertTrue(analysis.explanation.contains("equilibrada"))
    }

    // MARK: - Planos de Ação Física

    func testActionPlan_ObstaclePlanRecommendsElevationAndClearance() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let target = makeMeasurement(rating: .poor, score: 30, lanMs: 50.0, wanMs: 70.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: target)

        let plan = GuidedSolutionEngine.generateActionPlan(for: analysis, problem: .weakRoom)

        XCTAssertEqual(plan.title, "Reposicionamento e Elevação do Roteador")
        XCTAssertTrue(plan.instructions.contains { $0.contains("1 a 1,5 metro do chão") })
        XCTAssertTrue(plan.instructions.contains { $0.contains("nichos de madeira fechados") })
        XCTAssertTrue(plan.tip.contains("cúpula de luz"))
    }

    func testActionPlan_ISPPlanInstructsCheckingLineNotBuyingEquipment() {
        let base = makeMeasurement(score: 60, lanMs: 3.0, wanMs: 150.0, wanLoss: 4.0)
        let target = makeMeasurement(score: 55, lanMs: 6.0, wanMs: 155.0, wanLoss: 4.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: target)

        let plan = GuidedSolutionEngine.generateActionPlan(for: analysis, problem: .weakRoom)

        XCTAssertEqual(plan.title, "Verificação com a Operadora de Internet")
        XCTAssertTrue(plan.tip.contains("comprar repetidor não resolverá a lentidão"))
    }

    // MARK: - Veredictos Finais (Decisão Assistida)

    func testFinalVerdict_SolvedWithoutCostWhenScoreImproves() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let initialTarget = makeMeasurement(rating: .poor, score: 35, lanMs: 45.0, wanMs: 65.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initialTarget)

        // Após mudança física, nota sobe para 80 (+45 pontos) e latência cai para 10 ms
        let afterTarget = makeMeasurement(rating: .good, score: 80, lanMs: 10.0, wanMs: 25.0)

        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(
            initialTarget: initialTarget,
            afterTarget: afterTarget,
            analysis: analysis
        )

        XCTAssertEqual(verdict.type, .solvedWithoutCost)
        XCTAssertEqual(verdict.headline, "Problema Resolvido com Ajuste Físico!")
        XCTAssertTrue(verdict.description.contains("sem você precisar gastar nada"))
        XCTAssertEqual(verdict.deltaScore, 45)
    }

    func testFinalVerdict_RecommendsMeshOnlyWhenBaseIsPristineAndBarrierPersists() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let initialTarget = makeMeasurement(rating: .poor, score: 30, lanMs: 60.0, wanMs: 75.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initialTarget)

        // Mesmo após reposicionar, o cômodo continua Ruim (32 pts, delta +2)
        let afterTarget = makeMeasurement(rating: .poor, score: 32, lanMs: 58.0, wanMs: 73.0)

        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(
            initialTarget: initialTarget,
            afterTarget: afterTarget,
            analysis: analysis
        )

        XCTAssertEqual(verdict.type, .meshOrEquipmentRecommended)
        XCTAssertEqual(verdict.headline, "Barreira Estrutural Comprovada")
        XCTAssertTrue(verdict.description.contains("sistema Mesh com nó intermediário ou cabo de rede é a solução recomendada"))
    }

    func testFinalVerdict_DirectsToISPWhenRootCauseIsProvider() {
        let base = makeMeasurement(score: 60, lanMs: 3.0, wanMs: 140.0, wanLoss: 3.0)
        let initialTarget = makeMeasurement(score: 55, lanMs: 6.0, wanMs: 145.0, wanLoss: 3.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initialTarget)

        let afterTarget = makeMeasurement(score: 56, lanMs: 5.0, wanMs: 142.0, wanLoss: 3.0)

        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(
            initialTarget: initialTarget,
            afterTarget: afterTarget,
            analysis: analysis
        )

        XCTAssertEqual(verdict.type, .ispContactNeeded)
        XCTAssertEqual(verdict.headline, "O Gargalo Permanece na Operadora")
        XCTAssertTrue(verdict.description.contains("Não compre novos roteadores"))
    }

    func testFinalVerdict_PartialImprovementToFair_InstructsRepositionNotSolvedCost() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let initialTarget = makeMeasurement(rating: .poor, score: 30, lanMs: 50.0, wanMs: 65.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initialTarget)

        // Subiu de 30 para 65 (+35 pontos), mas rating final atingiu apenas Regular (.fair)
        let afterTarget = makeMeasurement(rating: .fair, score: 65, lanMs: 22.0, wanMs: 35.0)

        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(
            initialTarget: initialTarget,
            afterTarget: afterTarget,
            analysis: analysis
        )

        // Deve orientar reposicionamento adicional sem custos e NUNCA dar por resolvido ou empurrar compra
        XCTAssertEqual(verdict.type, .repositionAgain)
        XCTAssertEqual(verdict.headline, "Melhora Parcial, Mas Ainda Regular")
        XCTAssertEqual(verdict.deltaScore, 35)
        XCTAssertTrue(verdict.description.contains("atingindo qualidade Regular"))
        XCTAssertTrue(verdict.description.contains("antes de pensar em comprar equipamentos"))
    }

    func testFinalVerdict_RetestWithDegradedWAN_GuardsAgainstFalseSolvedAndMesh() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let initialTarget = makeMeasurement(rating: .poor, score: 35, lanMs: 55.0, wanMs: 65.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initialTarget)

        // No re-teste, o LAN melhorou (10 ms), mas a WAN da operadora caiu feio (140 ms, 3% perda)
        let afterTarget = makeMeasurement(rating: .good, score: 80, lanMs: 10.0, wanMs: 140.0, wanLoss: 3.0)

        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(
            initialTarget: initialTarget,
            afterTarget: afterTarget,
            analysis: analysis
        )

        // A guarda de WAN da operadora deve impedir .solvedWithoutCost e apontar provedor
        XCTAssertEqual(verdict.type, .ispContactNeeded)
        XCTAssertEqual(verdict.headline, "O Gargalo Permanece na Operadora")
        XCTAssertTrue(verdict.description.contains("link da operadora"))
    }

    func testFinalVerdict_MeshRequiresPoorAndNoDegradedWANAndCalculatesResidualAttenuation() {
        let base = makeMeasurement(score: 95, lanMs: 4.0, wanMs: 20.0)
        let initialTarget = makeMeasurement(rating: .poor, score: 28, lanMs: 62.0, wanMs: 70.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initialTarget)

        // Mesmo após reposicionar, cômodo continua Ruim (.poor) com 30 pontos (delta +2 < 3) e LAN de 44 ms
        let afterTarget = makeMeasurement(rating: .poor, score: 30, lanMs: 44.0, wanMs: 55.0)

        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(
            initialTarget: initialTarget,
            afterTarget: afterTarget,
            analysis: analysis
        )

        XCTAssertEqual(verdict.type, .meshOrEquipmentRecommended)
        XCTAssertEqual(verdict.headline, "Barreira Estrutural Comprovada")
        // Atenuação residual honesta: 44 ms - 4 ms = +40 ms
        XCTAssertTrue(verdict.technicalSummary.contains { $0.contains("Atenuação residual no trajeto: +40 ms") })
    }

    func testTwoPointAnalysis_MidTestWANOscillationDetectedAsISP() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 25.0)
        let target = makeMeasurement(rating: .fair, score: 60, lanMs: 6.0, wanMs: 130.0)

        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: target)

        XCTAssertEqual(analysis.bottleneck, .ispProvider)
        XCTAssertEqual(analysis.confidence, .medium)
        XCTAssertTrue(analysis.explanation.contains("conexão com a internet oscilou"))
    }

    func testBoundaryConditions_ExactThresholdsAndNegativeCases() {
        // 1. Limiares de Base WAN: exatamente 100.0 ms e 2.0% NÃO disparam ISP
        let baseWANAtLimit = makeMeasurement(score: 80, lanMs: 4.0, wanMs: 100.0, wanLoss: 2.0)
        let targetHealthy = makeMeasurement(score: 80, lanMs: 5.0, wanMs: 40.0)
        let analysisBelow = GuidedSolutionEngine.analyzeTwoPoints(base: baseWANAtLimit, target: targetHealthy)
        XCTAssertNotEqual(analysisBelow.bottleneck, .ispProvider)

        let baseWANAbove = makeMeasurement(score: 70, lanMs: 4.0, wanMs: 100.1, wanLoss: 0.0)
        let analysisAboveWAN = GuidedSolutionEngine.analyzeTwoPoints(base: baseWANAbove, target: targetHealthy)
        XCTAssertEqual(analysisAboveWAN.bottleneck, .ispProvider)

        let baseWANLossAbove = makeMeasurement(score: 70, lanMs: 4.0, wanMs: 30.0, wanLoss: 2.1)
        let analysisAboveWANLoss = GuidedSolutionEngine.analyzeTwoPoints(base: baseWANLossAbove, target: targetHealthy)
        XCTAssertEqual(analysisAboveWANLoss.bottleneck, .ispProvider)

        // 2. Limiares de Base LAN: exatamente 25.0 ms, 2.0% loss e 15.0 ms jitter NÃO disparam localInterference
        let baseLANAtLimit = makeMeasurement(score: 80, lanMs: 25.0, lanLoss: 2.0, lanJitter: 15.0, wanMs: 30.0)
        let analysisLANBelow = GuidedSolutionEngine.analyzeTwoPoints(base: baseLANAtLimit, target: targetHealthy)
        XCTAssertNotEqual(analysisLANBelow.bottleneck, .localInterference)

        let baseLANAbove = makeMeasurement(score: 70, lanMs: 25.1, lanLoss: 0.0, lanJitter: 2.0, wanMs: 30.0)
        let analysisLANAbove = GuidedSolutionEngine.analyzeTwoPoints(base: baseLANAbove, target: targetHealthy)
        XCTAssertEqual(analysisLANAbove.bottleneck, .localInterference)

        // 3. Limiares de Trajeto (LAN Delta): exatamente 25.0 ms e loss delta 2.0% NÃO disparam localDistanceOrObstacle
        let baseClean = makeMeasurement(score: 95, lanMs: 4.0, lanLoss: 0.0, wanMs: 20.0)
        let targetDeltaAtLimit = makeMeasurement(rating: .good, score: 75, lanMs: 29.0, lanLoss: 2.0, wanMs: 25.0) // lanDelta = 25.0, lossDelta = 2.0
        let analysisDeltaBelow = GuidedSolutionEngine.analyzeTwoPoints(base: baseClean, target: targetDeltaAtLimit)
        XCTAssertNotEqual(analysisDeltaBelow.bottleneck, .localDistanceOrObstacle)

        let targetDeltaAbove = makeMeasurement(rating: .poor, score: 35, lanMs: 29.1, wanMs: 25.0) // lanDelta = 25.1
        let analysisDeltaAbove = GuidedSolutionEngine.analyzeTwoPoints(base: baseClean, target: targetDeltaAbove)
        XCTAssertEqual(analysisDeltaAbove.bottleneck, .localDistanceOrObstacle)

        // 4. Limiares de Veredicto de Score: delta de exatamente 2 com rating .good NÃO dispara resolvido
        let initialScore50 = makeMeasurement(rating: .fair, score: 50, lanMs: 30.0, wanMs: 30.0)
        let afterScore52Good = makeMeasurement(rating: .good, score: 52, lanMs: 12.0, wanMs: 25.0)
        let verdictDelta2 = GuidedSolutionEngine.evaluateFinalVerdict(
            initialTarget: initialScore50,
            afterTarget: afterScore52Good,
            analysis: analysisDeltaAbove
        )
        XCTAssertEqual(verdictDelta2.type, .repositionAgain)

        // Delta de exatamente +3 com rating .good dispara resolvido
        let afterScore53Good = makeMeasurement(rating: .good, score: 53, lanMs: 12.0, wanMs: 25.0)
        let verdictDelta3 = GuidedSolutionEngine.evaluateFinalVerdict(
            initialTarget: initialScore50,
            afterTarget: afterScore53Good,
            analysis: analysisDeltaAbove
        )
        XCTAssertEqual(verdictDelta3.type, .solvedWithoutCost)
    }

    func testFinalVerdict_RetestDegradedOnlyByWANPacketLoss_BlocksSolvedCost() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let initial = makeMeasurement(rating: .poor, score: 30, lanMs: 50.0, wanMs: 40.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initial)

        // LAN excelente, score alto, WAN de 25 ms, mas com perda de pacotes externa (2.5%)
        let afterTarget = makeMeasurement(rating: .good, score: 85, lanMs: 8.0, wanMs: 25.0, wanLoss: 2.5)
        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(initialTarget: initial, afterTarget: afterTarget, analysis: analysis)

        XCTAssertEqual(verdict.type, .ispContactNeeded)
        XCTAssertEqual(verdict.headline, "O Gargalo Permanece na Operadora")
    }

    func testFinalVerdict_MeshBlockedWhenRetestHasDegradedWAN() {
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 20.0)
        let initial = makeMeasurement(rating: .poor, score: 25, lanMs: 65.0, wanMs: 30.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initial)

        // Continua ruim no LAN (60 ms), mas a WAN degradou no re-teste (120 ms)
        let afterTarget = makeMeasurement(rating: .poor, score: 26, lanMs: 60.0, wanMs: 120.0)
        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(initialTarget: initial, afterTarget: afterTarget, analysis: analysis)

        // Guarda de operadora tem precedência absoluta sobre recomendação de Mesh
        XCTAssertEqual(verdict.type, .ispContactNeeded)
        XCTAssertFalse(verdict.description.contains("sistema Mesh"))
    }

    func testFinalVerdict_TransientWANOscillationNormalizesInRetest_AllowsSolvedCost() {
        // Análise inicial detectou oscilação transitória de WAN no cômodo (média confiança)
        let base = makeMeasurement(score: 95, lanMs: 3.0, wanMs: 25.0)
        let initial = makeMeasurement(rating: .fair, score: 60, lanMs: 6.0, wanMs: 130.0)
        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: initial)
        XCTAssertEqual(analysis.confidence, .medium)
        XCTAssertEqual(analysis.bottleneck, .ispProvider)

        // No re-teste, a WAN normalizou completamente (25 ms, 0% perda) e o LAN continuou bom (85 pts)
        let afterTarget = makeMeasurement(rating: .good, score: 85, lanMs: 5.0, wanMs: 25.0, wanLoss: 0.0)
        let verdict = GuidedSolutionEngine.evaluateFinalVerdict(initialTarget: initial, afterTarget: afterTarget, analysis: analysis)

        // Como a operadora normalizou e o sinal é Bom, o veredicto reconhece a resolução
        XCTAssertEqual(verdict.type, .solvedWithoutCost)
        XCTAssertEqual(verdict.headline, "Problema Resolvido com Ajuste Físico!")
    }

    func testFormatSignedDeltaMs_HandlesPositiveNegativeAndZero() {
        XCTAssertEqual(GuidedSolutionEngine.formatSignedDeltaMs(12.4), "+12 ms")
        XCTAssertEqual(GuidedSolutionEngine.formatSignedDeltaMs(-8.6), "-9 ms")
        XCTAssertEqual(GuidedSolutionEngine.formatSignedDeltaMs(0.2), "0 ms")
        XCTAssertEqual(GuidedSolutionEngine.formatSignedDeltaMs(-0.1), "0 ms")
    }

    func testTwoPointAnalysis_PacketLossWithNegativeLanDeltaDoesNotProduceInvalidString() {
        let base = makeMeasurement(score: 90, lanMs: 10.0, lanLoss: 0.0, wanMs: 20.0)
        // LAN melhor no cômodo (7 ms), mas houve perda de pacotes (4%)
        let target = makeMeasurement(rating: .poor, score: 45, lanMs: 7.0, lanLoss: 4.0, wanMs: 25.0)

        let analysis = GuidedSolutionEngine.analyzeTwoPoints(base: base, target: target)

        XCTAssertEqual(analysis.bottleneck, .localDistanceOrObstacle)
        XCTAssertFalse(analysis.explanation.contains("+-"))
        XCTAssertTrue(analysis.explanation.contains("perda de pacotes no enlace"))
    }
}
