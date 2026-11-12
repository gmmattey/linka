import XCTest
@testable import NetworkSpatial

@MainActor
final class HomeProblemFlowTests: XCTestCase {

    // MARK: - Enums & ViewModel

    func testAllProblemCasesDefined() {
        XCTAssertEqual(HomeProblemCase.allCases.count, 4)
        XCTAssertEqual(HomeProblemCase.weakRoom.id, "weak_room")
        XCTAssertEqual(HomeProblemCase.videoCallsFreezing.id, "video_calls_freezing")
        XCTAssertEqual(HomeProblemCase.routerUpgrade.id, "router_upgrade")
        XCTAssertEqual(HomeProblemCase.planAdequacy.id, "plan_adequacy")
    }

    func testHomeViewModelStartsProblemDiagnosis() {
        let store = DataStore()
        let vm = HomeViewModel(dataStore: store)

        XCTAssertNil(vm.activeProblemCase)
        XCTAssertFalse(vm.showProblemDiagnosticSheet)

        vm.startProblemDiagnosis(.weakRoom)

        XCTAssertEqual(vm.activeProblemCase, .weakRoom)
        XCTAssertTrue(vm.showProblemDiagnosticSheet)
    }

    // MARK: - Caso 1: Cômodo Fraco (weakRoom)

    func testWeakRoom_FastLAN_FastWAN() {
        let problem = HomeProblemCase.weakRoom
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 20.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 2.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 120.0,
            rating: .excellent
        )

        XCTAssertEqual(
            advice.hypothesis,
            "O sinal Wi-Fi neste ponto apresenta resposta rápida (4 ms no roteador). A conexão interna não é o gargalo."
        )
        XCTAssertEqual(
            advice.action,
            "Se você nota lentidão esporádica, verifique se ocorre em horários de pico ou em aplicativos específicos."
        )
    }

    func testWeakRoom_FastLAN_SlowWAN_BlamesProviderNotLocalWiFi() {
        let problem = HomeProblemCase.weakRoom
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 140.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 25.0,
            wanPacketLossPercent: 3.0,
            downloadThroughputMbps: 15.0,
            rating: .poor
        )

        XCTAssertEqual(
            advice.hypothesis,
            "O sinal do Wi-Fi até o roteador neste cômodo está excelente (4 ms e sem perda local). A lentidão percebida decorre de instabilidade na rota externa da internet (140 ms), e não do alcance Wi-Fi."
        )
        XCTAssertEqual(
            advice.action,
            "Não é necessário mexer no roteador ou comprar repetidor para este cômodo. A causa provável é a rota do provedor de internet."
        )
    }

    func testWeakRoom_IntermediateLAN_SlowWAN() {
        let problem = HomeProblemCase.weakRoom
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 25.0,
            wanMedianMs: 130.0,
            lanJitterMs: 3.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 10.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 40.0,
            rating: .fair
        )

        XCTAssertEqual(
            advice.hypothesis,
            "O sinal local até o roteador é moderado (25 ms), mas o principal fator de lentidão é a instabilidade na rota externa da internet (130 ms)."
        )
        XCTAssertEqual(
            advice.action,
            "Antes de mexer em cabos e roteador, verifique a estabilidade da sua operadora."
        )
    }

    func testWeakRoom_IntermediateLAN_FastWAN() {
        let problem = HomeProblemCase.weakRoom
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 25.0,
            wanMedianMs: 30.0,
            lanJitterMs: 3.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 4.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 60.0,
            rating: .good
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A resposta do sinal Wi-Fi local está moderada (25 ms). Há atenuação leve pelo percurso até o roteador."
        )
        XCTAssertEqual(
            advice.action,
            "Manter portas abertas e elevar o roteador em 1 metro do chão costuma ser suficiente para melhorar a resposta neste ambiente."
        )
    }

    func testWeakRoom_DegradedLAN_IdentifiesBarriers() {
        let problem = HomeProblemCase.weakRoom
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 45.0,
            wanMedianMs: 50.0,
            lanJitterMs: 12.0,
            lanPacketLossPercent: 4.0,
            wanJitterMs: 5.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 20.0,
            rating: .poor
        )

        XCTAssertEqual(
            advice.hypothesis,
            "O sinal até o roteador apresentou resposta lenta (45 ms) ou oscilação local (4.0% de perda). Há indício de barreiras físicas (paredes, móveis) ou distância."
        )
        XCTAssertEqual(
            advice.action,
            "Experimente reposicionar o roteador para um ponto mais central e elevado, desobstruído de paredes grossas, antes de pensar em novos aparelhos."
        )
    }

    // MARK: - Caso 2: Chamadas Travando (videoCallsFreezing)

    func testVideoCallsFreezing_HighLANJitter_UsesCorrectTypoAndSuggestsCable() {
        let problem = HomeProblemCase.videoCallsFreezing
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 15.0,
            wanMedianMs: 35.0,
            lanJitterMs: 15.0,
            lanPacketLossPercent: 2.0,
            wanJitterMs: 5.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 45.0,
            rating: .fair
        )

        XCTAssertEqual(
            advice.hypothesis,
            "Detectamos indício de oscilação na rota Wi-Fi local (jitter de 15.0 ms ou perda no roteador). Variações no sinal interno causam engasgos em chamadas de vídeo."
        )
        XCTAssertEqual(
            advice.action,
            "Aproxime-se do roteador ou conecte os aparelhos que mais consomem banda em horários de reunião via cabo de rede se possível."
        )
    }

    func testVideoCallsFreezing_IsolatedWANJitter_WhenLossIsNil() {
        let problem = HomeProblemCase.videoCallsFreezing
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 40.0,
            lanJitterMs: 2.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 25.0,
            wanPacketLossPercent: nil,
            downloadThroughputMbps: 60.0,
            rating: .good
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A rede Wi-Fi local está estável, mas detectamos oscilação na rota com a internet (jitter externo de 25.0 ms). Isso afeta a continuidade de reuniões online."
        )
        XCTAssertEqual(
            advice.action,
            "O problema não está no alcance do seu Wi-Fi. Se o congelamento persistir, consulte seu provedor sobre a estabilidade da rota."
        )
    }

    func testVideoCallsFreezing_HighWANLoss() {
        let problem = HomeProblemCase.videoCallsFreezing
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 80.0,
            lanJitterMs: 1.5,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 10.0,
            wanPacketLossPercent: 4.0,
            downloadThroughputMbps: 50.0,
            rating: .fair
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A rede Wi-Fi local está estável, mas detectamos oscilação na rota com a internet (perda externa de 4.0%). Isso afeta a continuidade de reuniões online."
        )
        XCTAssertEqual(
            advice.action,
            "O problema não está no alcance do seu Wi-Fi. Se o congelamento persistir, consulte seu provedor sobre a estabilidade da rota."
        )
    }

    func testVideoCallsFreezing_StableConnection() {
        let problem = HomeProblemCase.videoCallsFreezing
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 3.0,
            wanMedianMs: 20.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 2.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 100.0,
            rating: .excellent
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A estabilidade de pacotes está satisfatória (jitter local de 1.0 ms). O congelamento esporádico pode decorrer do próprio aplicativo de conferência ou de sobrecarga momentânea do aparelho."
        )
        XCTAssertEqual(
            advice.action,
            "Sua rota de rede local apresenta boa estabilidade para chamadas em vídeo."
        )
    }

    // MARK: - Caso 3: Troca de Roteador (routerUpgrade)

    func testRouterUpgrade_HealthyConnection_DoesNotRecommendBuying() {
        let problem = HomeProblemCase.routerUpgrade
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 25.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 3.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 150.0,
            rating: .excellent
        )

        XCTAssertEqual(
            advice.hypothesis,
            "Com base neste ponto, o roteador atual apresenta resposta rápida e estável (4 ms de latência local)."
        )
        XCTAssertEqual(
            advice.action,
            "Não há evidência técnica de que a troca de roteador trará ganho neste ambiente. Seu aparelho atual atende bem o local."
        )
    }

    func testRouterUpgrade_FastLAN_SlowWAN_ExplainsRouterCannotFixWAN() {
        let problem = HomeProblemCase.routerUpgrade
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 5.0,
            wanMedianMs: 150.0,
            lanJitterMs: 1.5,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 30.0,
            wanPacketLossPercent: 2.5,
            downloadThroughputMbps: 20.0,
            rating: .fair
        )

        XCTAssertEqual(
            advice.hypothesis,
            "Com base neste teste, seu roteador entrega resposta rápida no cômodo (5 ms local). A lentidão decorre da rota externa da operadora."
        )
        XCTAssertEqual(
            advice.action,
            "Comprar outro roteador dificilmente resolverá o problema, pois a limitação observada está no link externo do provedor."
        )
    }

    func testRouterUpgrade_FastLAN_HighLANLoss_RecognizesDegradationWithoutClaimingFastIsSevereAttenuation() {
        let problem = HomeProblemCase.routerUpgrade
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 5.0,
            wanMedianMs: 25.0,
            lanJitterMs: 2.0,
            lanPacketLossPercent: 4.0, // Perda local alta!
            wanJitterMs: 3.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 50.0,
            rating: .poor
        )

        XCTAssertEqual(
            advice.hypothesis,
            "O roteador atual apresenta perda de pacotes elevada no enlace local (4.0% de perda até o roteador), indicando limite de alcance ou barreiras espessas."
        )
        XCTAssertEqual(
            advice.action,
            "Antes de comprar outro aparelho, teste reposicionar o roteador atual em local central. Se a residência tiver múltiplos pavimentos ou mais de 90 m², um sistema mesh com 2 nós pode ser uma solução mais duradoura que outro roteador comum."
        )
    }

    func testRouterUpgrade_IntermediateLAN() {
        let problem = HomeProblemCase.routerUpgrade
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 25.0,
            wanMedianMs: 40.0,
            lanJitterMs: 4.0,
            lanPacketLossPercent: 0.5,
            wanJitterMs: 5.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 60.0,
            rating: .good
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A resposta do roteador neste ponto é intermediária (25 ms). O sinal chega, mas sofre degradação moderada."
        )
        XCTAssertEqual(
            advice.action,
            "Evite gastos imediatos: pequenos ajustes de altura e desobstrução de antenas costumam ser suficientes para este nível de sinal."
        )
    }

    func testRouterUpgrade_DegradedLAN_SuggestsPositioningBeforeMesh() {
        let problem = HomeProblemCase.routerUpgrade
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 50.0,
            wanMedianMs: 60.0,
            lanJitterMs: 15.0,
            lanPacketLossPercent: 5.0,
            wanJitterMs: 5.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 8.0,
            rating: .poor
        )

        XCTAssertEqual(
            advice.hypothesis,
            "O roteador atual apresenta atenuação severa neste cômodo (50 ms de resposta local), indicando limite de alcance ou barreiras espessas."
        )
        XCTAssertEqual(
            advice.action,
            "Antes de comprar outro aparelho, teste reposicionar o roteador atual em local central. Se a residência tiver múltiplos pavimentos ou mais de 90 m², um sistema mesh com 2 nós pode ser uma solução mais duradoura que outro roteador comum."
        )
    }

    // MARK: - Caso 4: Adequação do Plano (planAdequacy)

    func testPlanAdequacy_LocalBottleneck() {
        let problem = HomeProblemCase.planAdequacy
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 45.0,
            wanMedianMs: 60.0,
            lanJitterMs: 18.0,
            lanPacketLossPercent: 3.0,
            wanJitterMs: 5.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 200.0,
            rating: .poor
        )

        XCTAssertEqual(
            advice.hypothesis,
            "O gargalo observado está na conexão Wi-Fi local (45 ms até o roteador), e não na velocidade do plano da operadora."
        )
        XCTAssertEqual(
            advice.action,
            "Aumentar a velocidade do seu plano não resolverá a lentidão neste cômodo. O sinal Wi-Fi precisa chegar com mais qualidade antes de avaliar o plano."
        )
    }

    func testPlanAdequacy_HighThroughput_WithWANLoss() {
        let problem = HomeProblemCase.planAdequacy
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 30.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 15.0,
            wanPacketLossPercent: 3.5,
            downloadThroughputMbps: 250.0,
            rating: .fair
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A taxa de download é de 250 Mbps, mas detectamos perda de pacotes na rota externa (3.5%). A lentidão percebida decorre da rota da operadora, e não da banda contratada."
        )
        XCTAssertEqual(
            advice.action,
            "Aumentar a velocidade do plano não corrige instabilidade de rota. Entre em contato com seu provedor para verificar a rota na sua região."
        )
    }

    func testPlanAdequacy_HighThroughput_NoLoss() {
        let problem = HomeProblemCase.planAdequacy
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 20.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 2.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 250.0,
            rating: .excellent
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A taxa de download aferida (250 Mbps) e a rota externa (20 ms) confirmam boa capacidade para streaming 4K, downloads e múltiplos aparelhos."
        )
        XCTAssertEqual(
            advice.action,
            "Seu plano atual atende com folga as demandas residenciais comuns. Não há necessidade técnica de contratar velocidade superior."
        )
    }

    func testPlanAdequacy_HighThroughput_WithHighWANLatency() {
        let problem = HomeProblemCase.planAdequacy
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 250.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 5.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 150.0,
            rating: .fair
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A taxa de download é de 150 Mbps, mas detectamos alta latência na rota externa (250 ms). A lentidão percebida decorre da rota da operadora, e não da banda contratada."
        )
        XCTAssertEqual(
            advice.action,
            "Aumentar a velocidade do plano não corrige instabilidade de rota. Entre em contato com seu provedor para verificar a rota na sua região."
        )
    }

    func testPlanAdequacy_MediumThroughput() {
        let problem = HomeProblemCase.planAdequacy
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 25.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 3.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 60.0,
            rating: .good
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A taxa de download aferida (60 Mbps) é suficiente para trabalho, streaming HD e navegação simultânea."
        )
        XCTAssertEqual(
            advice.action,
            "Seu plano é adequado para o dia a dia. Se você faz downloads muito pesados ou tem muitas pessoas transmitindo simultaneamente, avalie a velocidade contratada."
        )
    }

    func testPlanAdequacy_LowThroughput() {
        let problem = HomeProblemCase.planAdequacy
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 4.0,
            wanMedianMs: 35.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 4.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 15.0,
            rating: .fair
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A taxa de download aferida ficou em 15 Mbps, abaixo do padrão típico para conexões banda larga modernas."
        )
        XCTAssertEqual(
            advice.action,
            "Verifique com seu provedor qual velocidade está contratada e faça um teste comparativo conectado via cabo de rede diretamente ao roteador."
        )
    }

    func testPlanAdequacy_NilThroughput_DoesNotAssumePlanCapacity() {
        let problem = HomeProblemCase.planAdequacy
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 5.0,
            wanMedianMs: 25.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 3.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: nil,
            rating: .good
        )

        XCTAssertEqual(
            advice.hypothesis,
            "A resposta de rota externa está em 25 ms, mas não foi possível aferir a taxa de download nesta medição."
        )
        XCTAssertEqual(
            advice.action,
            "Para avaliar se a velocidade contratada é suficiente, realize uma medição com o teste de vazão ativo ou compare a resposta em horários diferentes."
        )
    }

    // MARK: - Testes de Limite (Boundaries)

    func testBoundaries_WeakRoom_Exactly15MsLAN_And100MsWAN() {
        let problem = HomeProblemCase.weakRoom
        // Exatamente 15.0 ms LAN e 100.0 ms WAN: limite superior de rápido
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 15.0,
            wanMedianMs: 100.0,
            lanJitterMs: 1.0,
            lanPacketLossPercent: 1.0,
            wanJitterMs: 5.0,
            wanPacketLossPercent: 1.0,
            downloadThroughputMbps: 50.0,
            rating: .good
        )

        XCTAssertTrue(advice.hypothesis.contains("resposta rápida (15 ms no roteador)"))
    }

    func testBoundaries_RouterUpgrade_Exactly40MsLAN() {
        let problem = HomeProblemCase.routerUpgrade
        // Exatamente 40.0 ms LAN, 0% perda e jitter normal: deve cair no intermediário, não em severo (>40)
        let advice = problem.generateTargetedAdvice(
            lanMedianMs: 40.0,
            wanMedianMs: 40.0,
            lanJitterMs: 2.0,
            lanPacketLossPercent: 0.0,
            wanJitterMs: 2.0,
            wanPacketLossPercent: 0.0,
            downloadThroughputMbps: 50.0,
            rating: .good
        )

        XCTAssertTrue(advice.hypothesis.contains("intermediária (40 ms)"))
    }

    // MARK: - ProblemCardView State

    func testProblemCardViewDisabledState() {
        var didTap = false
        let card = ProblemCardView(problem: .weakRoom, isEnabled: false) {
            didTap = true
        }

        XCTAssertFalse(card.isEnabled)
        XCTAssertEqual(card.problem, .weakRoom)
        XCTAssertFalse(didTap)
    }
}
