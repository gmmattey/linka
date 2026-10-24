import Foundation

/// Casos de uso e problemas comuns do consumidor residencial (B2C)
public enum HomeProblemCase: String, CaseIterable, Identifiable, Sendable {
    case weakRoom = "weak_room"
    case videoCallsFreezing = "video_calls_freezing"
    case routerUpgrade = "router_upgrade"
    case planAdequacy = "plan_adequacy"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weakRoom:
            return "Wi-Fi ruim em um cômodo"
        case .videoCallsFreezing:
            return "Chamadas e vídeos travando"
        case .routerUpgrade:
            return "Preciso trocar de roteador?"
        case .planAdequacy:
            return "Meu plano é suficiente?"
        }
    }

    public var subtitle: String {
        switch self {
        case .weakRoom:
            return "Investigar estabilidade e alcance no ponto com problema"
        case .videoCallsFreezing:
            return "Detectar oscilação de latência e perda de pacotes"
        case .routerUpgrade:
            return "Avaliar antes de gastar dinheiro com equipamentos"
        case .planAdequacy:
            return "Verificar resposta da rota externa e velocidade"
        }
    }

    public var icon: String {
        switch self {
        case .weakRoom:
            return "wifi.exclamationmark"
        case .videoCallsFreezing:
            return "video.badge.waveform"
        case .routerUpgrade:
            return "arrow.triangle.2.circlepath"
        case .planAdequacy:
            return "speedometer"
        }
    }

    public var promptQuestion: String {
        switch self {
        case .weakRoom:
            return "Em qual cômodo o sinal costuma falhar ou ficar lento?"
        case .videoCallsFreezing:
            return "Onde você costuma fazer chamadas de vídeo ou reuniões?"
        case .routerUpgrade:
            return "Em qual cômodo você mais sente necessidade de melhorar a internet?"
        case .planAdequacy:
            return "Onde você deseja avaliar a velocidade e estabilidade geral?"
        }
    }

    public var diagnosticFocus: String {
        switch self {
        case .weakRoom:
            return "Avaliando a resposta do roteador local e estabilidade do sinal Wi-Fi neste ponto."
        case .videoCallsFreezing:
            return "Medindo variação de atraso (jitter) e perda de pacotes críticos para chamadas em tempo real."
        case .routerUpgrade:
            return "Verificando se o gargalo real está no roteador doméstico ou na rota da operadora."
        case .planAdequacy:
            return "Aferindo taxa de transferência e tempo de resposta externo da internet."
        }
    }

    /// Gera uma recomendação específica e fundamentada para o problema após a medição
    public func generateTargetedAdvice(
        lanMedianMs: Double,
        wanMedianMs: Double,
        lanJitterMs: Double,
        lanPacketLossPercent: Double,
        wanJitterMs: Double? = nil,
        wanPacketLossPercent: Double? = nil,
        downloadThroughputMbps: Double? = nil,
        rating: QualityRating
    ) -> (hypothesis: String, action: String) {
        let wanLoss = wanPacketLossPercent ?? 0.0
        let wanJitter = wanJitterMs ?? 0.0

        switch self {
        case .weakRoom:
            if lanMedianMs <= 15.0 && lanPacketLossPercent <= 2.0 {
                let lossDesc = lanPacketLossPercent == 0.0 ? "sem perda local" : "perda local residual (\(String(format: "%.1f", lanPacketLossPercent))%)"
                if wanMedianMs > 100.0 || wanLoss > 2.0 || wanJitter > 20.0 {
                    return (
                        "O sinal do Wi-Fi até o roteador neste cômodo está excelente (\(Int(round(lanMedianMs))) ms e \(lossDesc)). A lentidão percebida decorre de instabilidade na rota externa da internet (\(Int(round(wanMedianMs))) ms), e não do alcance Wi-Fi.",
                        "Não é necessário mexer no roteador ou comprar repetidor para este cômodo. A causa provável é a rota do provedor de internet."
                    )
                } else {
                    return (
                        "O sinal Wi-Fi neste ponto apresenta resposta rápida (\(Int(round(lanMedianMs))) ms no roteador). A conexão interna não é o gargalo.",
                        "Se você nota lentidão esporádica, verifique se ocorre em horários de pico ou em aplicativos específicos."
                    )
                }
            } else if lanMedianMs > 35.0 || lanPacketLossPercent > 2.0 {
                return (
                    "O sinal até o roteador apresentou resposta lenta (\(Int(round(lanMedianMs))) ms) ou oscilação local (\(String(format: "%.1f", lanPacketLossPercent))% de perda). Há indício de barreiras físicas (paredes, móveis) ou distância.",
                    "Experimente reposicionar o roteador para um ponto mais central e elevado, desobstruído de paredes grossas, antes de pensar em novos aparelhos."
                )
            } else {
                if wanMedianMs > 100.0 || wanLoss > 2.0 {
                    return (
                        "O sinal local até o roteador é moderado (\(Int(round(lanMedianMs))) ms), mas o principal fator de lentidão é a instabilidade na rota externa da internet (\(Int(round(wanMedianMs))) ms).",
                        "Antes de mexer em cabos e roteador, verifique a estabilidade da sua operadora."
                    )
                } else {
                    return (
                        "A resposta do sinal Wi-Fi local está moderada (\(Int(round(lanMedianMs))) ms). Há atenuação leve pelo percurso até o roteador.",
                        "Manter portas abertas e elevar o roteador em 1 metro do chão costuma ser suficiente para melhorar a resposta neste ambiente."
                    )
                }
            }

        case .videoCallsFreezing:
            if lanJitterMs > 12.0 || lanPacketLossPercent > 1.5 {
                return (
                    "Detectamos indício de oscilação na rota Wi-Fi local (jitter de \(String(format: "%.1f", lanJitterMs)) ms ou perda no roteador). Variações no sinal interno causam engasgos em chamadas de vídeo.",
                    "Aproxime-se do roteador ou conecte os aparelhos que mais consomem banda em horários de reunião via cabo de rede se possível."
                )
            } else if wanLoss > 2.0 || wanJitter > 20.0 {
                let detail = wanLoss > 2.0 ? "perda externa de \(String(format: "%.1f", wanLoss))%" : "jitter externo de \(String(format: "%.1f", wanJitter)) ms"
                return (
                    "A rede Wi-Fi local está estável, mas detectamos oscilação na rota com a internet (\(detail)). Isso afeta a continuidade de reuniões online.",
                    "O problema não está no alcance do seu Wi-Fi. Se o congelamento persistir, consulte seu provedor sobre a estabilidade da rota."
                )
            } else {
                return (
                    "A estabilidade de pacotes está satisfatória (jitter local de \(String(format: "%.1f", lanJitterMs)) ms). O congelamento esporádico pode decorrer do próprio aplicativo de conferência ou de sobrecarga momentânea do aparelho.",
                    "Sua rota de rede local apresenta boa estabilidade para chamadas em vídeo."
                )
            }

        case .routerUpgrade:
            if lanMedianMs > 40.0 || lanPacketLossPercent > 3.0 || lanJitterMs > 20.0 {
                let causeReason: String
                if lanMedianMs > 40.0 {
                    causeReason = "atenuação severa neste cômodo (\(Int(round(lanMedianMs))) ms de resposta local)"
                } else if lanPacketLossPercent > 3.0 {
                    causeReason = "perda de pacotes elevada no enlace local (\(String(format: "%.1f", lanPacketLossPercent))% de perda até o roteador)"
                } else {
                    causeReason = "alta oscilação no enlace local (jitter de \(String(format: "%.1f", lanJitterMs)) ms até o roteador)"
                }

                return (
                    "O roteador atual apresenta \(causeReason), indicando limite de alcance ou barreiras espessas.",
                    "Antes de comprar outro aparelho, teste reposicionar o roteador atual em local central. Se a residência tiver múltiplos pavimentos ou mais de 90 m², um sistema mesh com 2 nós pode ser uma solução mais duradoura que outro roteador comum."
                )
            } else if lanMedianMs <= 15.0 && lanPacketLossPercent <= 1.0 && lanJitterMs <= 8.0 {
                if wanMedianMs > 100.0 || wanLoss > 2.0 {
                    return (
                        "Com base neste teste, seu roteador entrega resposta rápida no cômodo (\(Int(round(lanMedianMs))) ms local). A lentidão decorre da rota externa da operadora.",
                        "Comprar outro roteador dificilmente resolverá o problema, pois a limitação observada está no link externo do provedor."
                    )
                } else {
                    return (
                        "Com base neste ponto, o roteador atual apresenta resposta rápida e estável (\(Int(round(lanMedianMs))) ms de latência local).",
                        "Não há evidência técnica de que a troca de roteador trará ganho neste ambiente. Seu aparelho atual atende bem o local."
                    )
                }
            } else {
                return (
                    "A resposta do roteador neste ponto é intermediária (\(Int(round(lanMedianMs))) ms). O sinal chega, mas sofre degradação moderada.",
                    "Evite gastos imediatos: pequenos ajustes de altura e desobstrução de antenas costumam ser suficientes para este nível de sinal."
                )
            }

        case .planAdequacy:
            if lanMedianMs > 35.0 || lanPacketLossPercent > 2.0 {
                return (
                    "O gargalo observado está na conexão Wi-Fi local (\(Int(round(lanMedianMs))) ms até o roteador), e não na velocidade do plano da operadora.",
                    "Aumentar a velocidade do seu plano não resolverá a lentidão neste cômodo. O sinal Wi-Fi precisa chegar com mais qualidade antes de avaliar o plano."
                )
            } else if let throughput = downloadThroughputMbps {
                if wanLoss > 2.0 || wanMedianMs > 100.0 {
                    let causeText = wanLoss > 2.0 ? "perda de pacotes na rota externa (\(String(format: "%.1f", wanLoss))%)" : "alta latência na rota externa (\(Int(round(wanMedianMs))) ms)"
                    return (
                        "A taxa de download é de \(Int(round(throughput))) Mbps, mas detectamos \(causeText). A lentidão percebida decorre da rota da operadora, e não da banda contratada.",
                        "Aumentar a velocidade do plano não corrige instabilidade de rota. Entre em contato com seu provedor para verificar a rota na sua região."
                    )
                } else if throughput >= 100.0 {
                    return (
                        "A taxa de download aferida (\(Int(round(throughput))) Mbps) e a rota externa (\(Int(round(wanMedianMs))) ms) confirmam boa capacidade para streaming 4K, downloads e múltiplos aparelhos.",
                        "Seu plano atual atende com folga as demandas residenciais comuns. Não há necessidade técnica de contratar velocidade superior."
                    )
                } else if throughput >= 30.0 {
                    return (
                        "A taxa de download aferida (\(Int(round(throughput))) Mbps) é suficiente para trabalho, streaming HD e navegação simultânea.",
                        "Seu plano é adequado para o dia a dia. Se você faz downloads muito pesados ou tem muitas pessoas transmitindo simultaneamente, avalie a velocidade contratada."
                    )
                } else {
                    return (
                        "A taxa de download aferida ficou em \(Int(round(throughput))) Mbps, abaixo do padrão típico para conexões banda larga modernas.",
                        "Verifique com seu provedor qual velocidade está contratada e faça um teste comparativo conectado via cabo de rede diretamente ao roteador."
                    )
                }
            } else {
                if wanLoss > 2.0 || wanMedianMs > 100.0 {
                    return (
                        "A rota para a internet externa apresentou oscilação (\(Int(round(wanMedianMs))) ms), mas não foi possível aferir a taxa de download nesta medição.",
                        "Antes de avaliar alteração de plano, consulte seu provedor sobre a estabilidade da rota na sua região."
                    )
                } else {
                    return (
                        "A resposta de rota externa está em \(Int(round(wanMedianMs))) ms, mas não foi possível aferir a taxa de download nesta medição.",
                        "Para avaliar se a velocidade contratada é suficiente, realize uma medição com o teste de vazão ativo ou compare a resposta em horários diferentes."
                    )
                }
            }
        }
    }
}
