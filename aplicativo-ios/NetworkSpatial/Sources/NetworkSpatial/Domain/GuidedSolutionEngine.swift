import Foundation

// MARK: - Tipos e Modelos da Jornada de Solução Guiada (Fase 3 B2C)

public enum AnalysisConfidence: String, Codable, Sendable {
    case high = "Alta Confiança"
    case medium = "Média Confiança"
    case inconclusive = "Inconclusivo"

    public var label: String {
        switch self {
        case .high: return SpatialCopy.value("spatial.confidence.high", defaultValue: rawValue)
        case .medium: return SpatialCopy.value("spatial.confidence.medium", defaultValue: rawValue)
        case .inconclusive: return SpatialCopy.value("spatial.confidence.inconclusive", defaultValue: rawValue)
        }
    }

    public var systemImage: String {
        switch self {
        case .high: return "checkmark.seal.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .inconclusive: return "questionmark.circle.fill"
        }
    }
}

public enum BottleneckType: String, Codable, Sendable {
    case localDistanceOrObstacle = "Barreiras Físicas e Distância"
    case ispProvider = "Instabilidade da Operadora de Internet"
    case localInterference = "Interferência ou Roteador Obstruído"
    case healthy = "Conexão Equilibrada"

    public var label: String {
        switch self {
        case .localDistanceOrObstacle: return SpatialCopy.value("spatial.bottleneck.obstacle", defaultValue: rawValue)
        case .ispProvider: return SpatialCopy.value("spatial.bottleneck.isp", defaultValue: rawValue)
        case .localInterference: return SpatialCopy.value("spatial.bottleneck.interference", defaultValue: rawValue)
        case .healthy: return SpatialCopy.value("spatial.bottleneck.healthy", defaultValue: rawValue)
        }
    }
}

public struct TwoPointAnalysis: Sendable, Equatable {
    public let baseResult: MeasurementResult
    public let targetResult: MeasurementResult
    public let lanDeltaMs: Double
    public let wanDeltaMs: Double
    public let lossDeltaPercent: Double
    public let bottleneck: BottleneckType
    public let confidence: AnalysisConfidence
    public let explanation: String

    public init(
        baseResult: MeasurementResult,
        targetResult: MeasurementResult,
        lanDeltaMs: Double,
        wanDeltaMs: Double,
        lossDeltaPercent: Double,
        bottleneck: BottleneckType,
        confidence: AnalysisConfidence,
        explanation: String
    ) {
        self.baseResult = baseResult
        self.targetResult = targetResult
        self.lanDeltaMs = lanDeltaMs
        self.wanDeltaMs = wanDeltaMs
        self.lossDeltaPercent = lossDeltaPercent
        self.bottleneck = bottleneck
        self.confidence = confidence
        self.explanation = explanation
    }
}

public struct PhysicalActionPlan: Sendable, Equatable {
    public let title: String
    public let instructions: [String]
    public let tip: String
    public let icon: String

    public init(title: String, instructions: [String], tip: String, icon: String) {
        self.title = title
        self.instructions = instructions
        self.tip = tip
        self.icon = icon
    }
}

public enum VerdictType: String, Codable, Sendable {
    case solvedWithoutCost = "Problema Resolvido Sem Gastos"
    case ispContactNeeded = "Falha no Provedor de Internet"
    case meshOrEquipmentRecommended = "Solução Estrutural (Mesh ou Cabo)"
    case repositionAgain = "Necessário Novo Reposicionamento"
}

public struct GuidedVerdict: Sendable, Equatable {
    public let type: VerdictType
    public let headline: String
    public let description: String
    public let deltaScore: Int
    public let technicalSummary: [String]

    public init(
        type: VerdictType,
        headline: String,
        description: String,
        deltaScore: Int,
        technicalSummary: [String]
    ) {
        self.type = type
        self.headline = headline
        self.description = description
        self.deltaScore = deltaScore
        self.technicalSummary = technicalSummary
    }
}

// MARK: - Motor de Regras da Jornada de Solução Guiada

public struct GuidedSolutionEngine: Sendable {
    public init() {}

    /// Formata uma variação de latência em milissegundos com sinal explícito e correto
    public static func formatSignedDeltaMs(_ delta: Double) -> String {
        let rounded = Int(round(delta))
        if rounded > 0 {
            return "+\(rounded) ms"
        } else if rounded < 0 {
            return "\(rounded) ms"
        } else {
            return "0 ms"
        }
    }

    /// Analisa a comparação de dois pontos: Ponto Base (junto ao roteador) vs. Ponto Crítico (onde a internet falha)
    public static func analyzeTwoPoints(
        base: MeasurementResult,
        target: MeasurementResult
    ) -> TwoPointAnalysis {
        let baseLAN = base.metrics.gatewayMedianMs ?? base.metrics.gatewayLatencyMs
        let targetLAN = target.metrics.gatewayMedianMs ?? target.metrics.gatewayLatencyMs
        let baseWAN = base.metrics.wanMedianMs ?? base.metrics.wanLatencyMs
        let targetWAN = target.metrics.wanMedianMs ?? target.metrics.wanLatencyMs

        let lanDelta = targetLAN - baseLAN
        let wanDelta = targetWAN - baseWAN
        let lossDelta = target.metrics.gatewayPacketLossPercent - base.metrics.gatewayPacketLossPercent

        let baseWANLoss = base.metrics.wanPacketLossPercent ?? 0.0
        let targetWANLoss = target.metrics.wanPacketLossPercent ?? 0.0

        // 1. Checagem da Origem/Base: Se a base já apresenta WAN ruim ou perda externa na rua
        if baseWAN > 100.0 || baseWANLoss > 2.0 {
            let detail = baseWANLoss > 2.0 ? "perda de \(String(format: "%.1f", baseWANLoss))% no link" : "latência externa de \(Int(round(baseWAN))) ms"
            return TwoPointAnalysis(
                baseResult: base,
                targetResult: target,
                lanDeltaMs: lanDelta,
                wanDeltaMs: wanDelta,
                lossDeltaPercent: lossDelta,
                bottleneck: .ispProvider,
                confidence: .high,
                explanation: "Mesmo ao lado do roteador, a conexão com a internet já apresenta instabilidade (\(detail)). A raiz do problema vem da operadora, e não da distância entre os cômodos."
            )
        }

        // 2. Checagem da Origem/Base: Se a base já apresenta instabilidade local severa no próprio roteador
        if baseLAN > 25.0 || base.metrics.gatewayPacketLossPercent > 2.0 || base.metrics.gatewayJitterMs > 15.0 {
            return TwoPointAnalysis(
                baseResult: base,
                targetResult: target,
                lanDeltaMs: lanDelta,
                wanDeltaMs: wanDelta,
                lossDeltaPercent: lossDelta,
                bottleneck: .localInterference,
                confidence: .high,
                explanation: "O teste ao lado do roteador já revelou oscilação local (\(Int(round(baseLAN))) ms ou perda de pacotes no aparelho). O roteador pode estar sobrecarregado por múltiplos dispositivos ou precisando de reinicialização."
            )
        }

        // 3. Atenuação Física Comprovada no Trajeto: Base excelente, mas o cômodo tem grande atraso (+25 ms ou perda de pacotes)
        if lanDelta > 25.0 || lossDelta > 2.0 {
            let deltaDetail = lanDelta > 0 ? "degrada em +\(Int(round(lanDelta))) ms" : "apresenta perda de pacotes no enlace"
            return TwoPointAnalysis(
                baseResult: base,
                targetResult: target,
                lanDeltaMs: lanDelta,
                wanDeltaMs: wanDelta,
                lossDeltaPercent: lossDelta,
                bottleneck: .localDistanceOrObstacle,
                confidence: .high,
                explanation: "O sinal sai perfeito da base (\(Int(round(baseLAN))) ms), mas \(deltaDetail) no trajeto até o cômodo testado. Há forte indício de atenuação por paredes grossas, espelhos ou distância física."
            )
        }

        // 4. Oscilação de WAN no momento do teste do cômodo (operadora oscilou entre testes)
        if (targetWAN > 100.0 && baseWAN <= 40.0) || (targetWANLoss > 2.0 && baseWANLoss == 0.0) {
            return TwoPointAnalysis(
                baseResult: base,
                targetResult: target,
                lanDeltaMs: lanDelta,
                wanDeltaMs: wanDelta,
                lossDeltaPercent: lossDelta,
                bottleneck: .ispProvider,
                confidence: .medium,
                explanation: "O sinal Wi-Fi local até o roteador é estável (\(Int(round(targetLAN))) ms), mas a conexão com a internet oscilou durante o teste (\(Int(round(targetWAN))) ms externo). A instabilidade é externa da operadora."
            )
        }

        // 5. Jitter ou oscilação local residual no cômodo
        let jitterDelta = target.metrics.gatewayJitterMs - base.metrics.gatewayJitterMs
        if jitterDelta > 10.0 || target.metrics.gatewayJitterMs > 15.0 {
            return TwoPointAnalysis(
                baseResult: base,
                targetResult: target,
                lanDeltaMs: lanDelta,
                wanDeltaMs: wanDelta,
                lossDeltaPercent: lossDelta,
                bottleneck: .localInterference,
                confidence: .medium,
                explanation: "A latência média é aceitável, mas há oscilação intermitente de pacotes no cômodo (jitter de \(String(format: "%.1f", target.metrics.gatewayJitterMs)) ms). O roteador pode estar em nicho fechado ou sofrendo interferência de outros eletrônicos."
            )
        }

        // 6. Ambos os pontos saudáveis
        if target.rating == .excellent || target.rating == .good {
            return TwoPointAnalysis(
                baseResult: base,
                targetResult: target,
                lanDeltaMs: lanDelta,
                wanDeltaMs: wanDelta,
                lossDeltaPercent: lossDelta,
                bottleneck: .healthy,
                confidence: .high,
                explanation: "A resposta do sinal entre a base e este cômodo está equilibrada (\(Int(round(targetLAN))) ms local). Não há evidência de gargalo físico neste momento."
            )
        }

        // 7. Divergência muito sutil ou delta negativo/ruído: inconclusivo
        return TwoPointAnalysis(
            baseResult: base,
            targetResult: target,
            lanDeltaMs: lanDelta,
            wanDeltaMs: wanDelta,
            lossDeltaPercent: lossDelta,
            bottleneck: .healthy,
            confidence: .inconclusive,
            explanation: "A variação de sinal entre a base e este ponto ficou dentro da margem normal de oscilação (\(Int(round(abs(lanDelta)))) ms). Não há evidência estatística de barreira física."
        )
    }

    /// Gera o plano de ação física guiado de acordo com o gargalo identificado e o problema do usuário
    public static func generateActionPlan(
        for analysis: TwoPointAnalysis,
        problem: HomeProblemCase
    ) -> PhysicalActionPlan {
        switch analysis.bottleneck {
        case .localDistanceOrObstacle:
            let instructions: [String]
            if problem == .videoCallsFreezing {
                instructions = [
                    "Eleve o roteador para 1 a 1,5 metro do chão para desviar de móveis baixos.",
                    "Aproxime o equipamento em direção ao vão livre que conecta este cômodo.",
                    "Durante chamadas de trabalho, prefira a rede 5 GHz e feche portas metálicas ou espelhos no caminho."
                ]
            } else {
                instructions = [
                    "Eleve o roteador para 1 a 1,5 metro do chão (sobre uma bancada ou prateleira aberta).",
                    "Aproxime o equipamento em direção ao corredor ou vão livre que conecta os cômodos.",
                    "Evite colocar o roteador atrás de televisores, dentro de nichos de madeira fechados ou perto de espelhos grandes."
                ]
            }
            return PhysicalActionPlan(
                title: "Reposicionamento e Elevação do Roteador",
                instructions: instructions,
                tip: "O sinal de Wi-Fi se propaga como uma cúpula de luz: quanto mais alto e livre de barreiras, maior o alcance nos quartos.",
                icon: "arrow.up.and.line.horizontal.and.arrow.down"
            )

        case .localInterference:
            return PhysicalActionPlan(
                title: "Desobstrução e Alinhamento de Antenas",
                instructions: [
                    "Retire o roteador de dentro de armários ou atrás do rack da TV.",
                    "Se o roteador tiver antenas externas, posicione uma na vertical e outra inclinada em 45 graus.",
                    "Afaste telefones sem fio, micro-ondas e caixas de som Bluetooth do raio de 1 metro do roteador."
                ],
                tip: "Superfícies metálicas e espelhos refletem e cancelam as ondas de rádio do Wi-Fi.",
                icon: "antenna.radiowaves.left.and.right"
            )

        case .ispProvider:
            let tipText: String
            if analysis.confidence == .high {
                tipText = "Como o teste ao lado do roteador já apresentou instabilidade na internet, trocar de lugar ou comprar repetidor não resolverá a lentidão."
            } else {
                tipText = "A conexão externa com a operadora oscilou durante o teste. Antes de reposicionar equipamentos, certifique-se de que a operadora normalizou o link."
            }
            return PhysicalActionPlan(
                title: "Verificação com a Operadora de Internet",
                instructions: [
                    "Reinicie o modem/roteador da operadora desligando da tomada por 30 segundos.",
                    "Anote os dados desta medição para informar ao suporte técnico.",
                    "Se a oscilação continuar, solicite verificação de ruído na linha óptica ou sinal externo."
                ],
                tip: tipText,
                icon: "phone.badge.waveform"
            )

        case .healthy:
            let tipText = analysis.confidence == .inconclusive
                ? "As variações medidas ficaram dentro da margem normal. Se a oscilação for esporádica, monitore horários de pico ou sobrecarga por outros aparelhos."
                : "Sua rede física responde com agilidade neste cômodo."
            return PhysicalActionPlan(
                title: "Otimização de Horários e Aparelhos",
                instructions: [
                    "Verifique se outros aparelhos estão realizando downloads pesados em segundo plano.",
                    "Em chamadas críticas de trabalho, prefira a rede 5 GHz em vez de 2,4 GHz.",
                    "Teste o mesmo aplicativo em outro aparelho para isolar lentidão do dispositivo."
                ],
                tip: tipText,
                icon: "sparkles"
            )
        }
    }

    /// Avalia o resultado final da jornada (Antes vs. Depois) e ajuda o usuário a decidir
    public static func evaluateFinalVerdict(
        initialTarget: MeasurementResult,
        afterTarget: MeasurementResult,
        analysis: TwoPointAnalysis
    ) -> GuidedVerdict {
        let delta = afterTarget.score - initialTarget.score
        let baseLAN = analysis.baseResult.metrics.gatewayMedianMs ?? analysis.baseResult.metrics.gatewayLatencyMs
        let targetLANAfter = afterTarget.metrics.gatewayMedianMs ?? afterTarget.metrics.gatewayLatencyMs
        let targetLossAfter = afterTarget.metrics.gatewayPacketLossPercent

        let afterTargetWAN = afterTarget.metrics.wanMedianMs ?? afterTarget.metrics.wanLatencyMs
        let afterTargetWANLoss = afterTarget.metrics.wanPacketLossPercent ?? 0.0
        let hasDegradedWANAfter = afterTargetWAN > 100.0 || afterTargetWANLoss > 2.0

        // 1. GUARDA DA OPERADORA:
        // Caso A: Operadora degradada no re-teste (WAN lenta ou perda externa de pacotes)
        if hasDegradedWANAfter {
            return GuidedVerdict(
                type: .ispContactNeeded,
                headline: "O Gargalo Permanece na Operadora",
                description: "A medição externa no re-teste revelou oscilações no link da operadora (\(Int(round(afterTargetWAN))) ms ou perda). Não compre novos roteadores antes de regularizar a estabilidade da sua linha.",
                deltaScore: delta,
                technicalSummary: [
                    "Latência externa medida: \(Int(round(afterTargetWAN))) ms",
                    "Latência no roteador: \(Int(round(targetLANAfter))) ms",
                    "Causa provável: Rota externa ou sobrecarga no provedor"
                ]
            )
        }

        // Caso B: A análise inicial já detectou falha de operadora com Alta Confiança (instabilidade confirmada direto na base)
        if analysis.bottleneck == .ispProvider && analysis.confidence == .high {
            return GuidedVerdict(
                type: .ispContactNeeded,
                headline: "O Gargalo Permanece na Operadora",
                description: "A instabilidade da internet foi confirmada desde a medição junto ao roteador. Ajustes físicos de posição não resolvem falhas na entrega de sinal da operadora.",
                deltaScore: delta,
                technicalSummary: [
                    "Latência externa na base: \(Int(round(analysis.baseResult.metrics.wanMedianMs ?? analysis.baseResult.metrics.wanLatencyMs))) ms",
                    "Latência no roteador: \(Int(round(targetLANAfter))) ms",
                    "Causa provável: Rota externa ou sobrecarga no provedor"
                ]
            )
        }

        // 2. RESOLVIDO SEM GASTOS: Ganho real (delta >= 3) E qualidade final atinge BOM ou ÓTIMO
        if delta >= 3 && (afterTarget.rating == .excellent || afterTarget.rating == .good) {
            return GuidedVerdict(
                type: .solvedWithoutCost,
                headline: "Problema Resolvido com Ajuste Físico!",
                description: "A mudança física gerou um ganho real de +\(delta) pontos na conexão deste cômodo. A latência no roteador baixou para \(Int(round(targetLANAfter))) ms e o sinal estabilizou (\(afterTarget.rating.label)) sem você precisar gastar nada com equipamentos.",
                deltaScore: delta,
                technicalSummary: [
                    "Ganho de pontuação: +\(delta) pontos (\(initialTarget.score) → \(afterTarget.score))",
                    "Resposta local no cômodo: \(Int(round(targetLANAfter))) ms",
                    "Perda de pacotes residual: \(String(format: "%.1f", targetLossAfter))%"
                ]
            )
        }

        // 3. MELHORA PARCIAL ATÉ REGULAR: Sinal subiu, mas atingiu apenas Regular (orienta reposicionar novamente, NÃO comprar)
        if delta >= 3 && afterTarget.rating == .fair {
            return GuidedVerdict(
                type: .repositionAgain,
                headline: "Melhora Parcial, Mas Ainda Regular",
                description: "A mudança física gerou um ganho de +\(delta) pontos (\(initialTarget.score) → \(afterTarget.score)), atingindo qualidade Regular. Tente novo ajuste fino de elevação ou rotação de antenas para atingir qualidade Boa antes de pensar em comprar equipamentos.",
                deltaScore: delta,
                technicalSummary: [
                    "Evolução parcial: \(initialTarget.score) → \(afterTarget.score) (+\(delta) pontos)",
                    "Resposta local no cômodo: \(Int(round(targetLANAfter))) ms",
                    "Recomendação: Novo ajuste físico sem custos"
                ]
            )
        }

        // 4. MELHORA PARCIAL ATÉ RUIM: Sinal subiu, mas continua crítico
        if delta >= 3 && afterTarget.rating == .poor {
            return GuidedVerdict(
                type: .repositionAgain,
                headline: "Melhora Parcial, Mas Ainda Crítico",
                description: "O sinal subiu +\(delta) pontos, mas a conexão neste ponto ainda apresenta instabilidade (\(afterTarget.score) pontos). Tente elevar o roteador ainda mais ou desobstruir outras barreiras antes de investir em equipamentos.",
                deltaScore: delta,
                technicalSummary: [
                    "Evolução parcial: \(initialTarget.score) → \(afterTarget.score) (+\(delta) pontos)",
                    "Latência residual no roteador: \(Int(round(targetLANAfter))) ms"
                ]
            )
        }

        // 5. RECOMENDAÇÃO ESTRUTURAL DE MESH/CABO:
        // Apenas quando comprovado que o gargalo é distância/obstáculo com Alta Confiança,
        // o re-teste continuou Ruim (.poor) sem melhora relevante (delta < 3) e a WAN está saudável
        if analysis.bottleneck == .localDistanceOrObstacle && analysis.confidence == .high && afterTarget.rating == .poor && delta < 3 {
            let residualDelta = targetLANAfter - baseLAN
            let residualStr = GuidedSolutionEngine.formatSignedDeltaMs(residualDelta)
            return GuidedVerdict(
                type: .meshOrEquipmentRecommended,
                headline: "Barreira Estrutural Comprovada",
                description: "A medição comprovou que a base do roteador é rápida, mas as barreiras físicas ou distância deste cômodo impedem a propagação direta do Wi-Fi mesmo com o roteador reposicionado. Para este caso, um sistema Mesh com nó intermediário ou cabo de rede é a solução recomendada.",
                deltaScore: delta,
                technicalSummary: [
                    "Pontuação no ponto crítico: \(afterTarget.score)/100 (\(afterTarget.rating.label))",
                    "Atenuação residual no trajeto: \(residualStr)",
                    "Recomendação fundamentada: Nó Mesh a meio caminho ou conexão via cabo"
                ]
            )
        }

        // 6. INTERFERÊNCIA LOCAL PERSISTENTE
        if analysis.bottleneck == .localInterference {
            return GuidedVerdict(
                type: .repositionAgain,
                headline: "Interferência Local Persistente",
                description: "A alteração não eliminou a oscilação de pacotes. Verifique se o roteador está próximo a outros transmissores sem fio ou teste conectar dispositivos críticos à banda de 5 GHz.",
                deltaScore: delta,
                technicalSummary: [
                    "Pontuação atual: \(afterTarget.score) (\(afterTarget.rating.label))",
                    "Oscilação medida: \(delta) pontos de diferença"
                ]
            )
        }

        // 7. VARIAÇÃO DENTRO DA MARGEM DE RUÍDO
        return GuidedVerdict(
            type: .repositionAgain,
            headline: "Variação Dentro da Margem de Ruído",
            description: "A alteração não produziu mudança perceptível (variação de \(delta) pontos). Tente reposicionar o aparelho em outra direção ou desobstruir vãos livres.",
            deltaScore: delta,
            technicalSummary: [
                "Pontuação anterior: \(initialTarget.score) | Nova pontuação: \(afterTarget.score)",
                "Diferença observada: \(delta) pontos"
            ]
        )
    }
}
