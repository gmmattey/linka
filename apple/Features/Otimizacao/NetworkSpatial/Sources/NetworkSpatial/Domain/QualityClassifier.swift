import Foundation

public struct QualityClassificationResult: Sendable, Equatable {
    public let rating: QualityRating
    public let score: Int
    public let cause: DiagnosisCause
    public let explanation: String
    public let recommendation: String

    public init(
        rating: QualityRating,
        score: Int,
        cause: DiagnosisCause,
        explanation: String,
        recommendation: String
    ) {
        self.rating = rating
        self.score = score
        self.cause = cause
        self.explanation = explanation
        self.recommendation = recommendation
    }
}

public enum QualityClassifier {

    /// Classifica a conexão com base na tabela determinística estrita e amostragem robusta (RFC 7680 & RFC 3550)
    public static func classify(
        metrics: NetworkMetrics,
        isWiFiActive: Bool = true,
        isRouterRoom: Bool = false
    ) -> QualityClassificationResult {
        guard isWiFiActive else {
            return QualityClassificationResult(
                rating: .unmeasured,
                score: 0,
                cause: .offline,
                explanation: "O dispositivo não está conectado ao Wi-Fi.",
                recommendation: "Conecte-se à rede Wi-Fi da sua casa para realizar o teste."
            )
        }

        let lanMedian = metrics.gatewayMedianMs ?? metrics.gatewayLatencyMs
        let lanP95 = metrics.gatewayP95Ms ?? metrics.gatewayLatencyMs
        let lanJitter = metrics.gatewayJitterMs
        let lanLoss = metrics.gatewayPacketLossPercent
        let lossInterpretation = metrics.gatewayLossInterpretation

        let wanMedian = metrics.wanMedianMs ?? metrics.wanLatencyMs
        let wanP95 = metrics.wanP95Ms ?? metrics.wanLatencyMs
        let wanJitter = metrics.wanJitterMs ?? 0.0
        let wanLoss = metrics.wanPacketLossPercent
        let wanLossInterpretation = metrics.wanLossInterpretation

        // 1. Determinação da classificação do segmento LAN
        // Tabela Canônica:
        // Ótimo: Mediana ≤ 10ms, p95 ≤ 20ms, Jitter ≤ 3ms, sem perdas confirmadas
        // Bom: Mediana ≤ 20ms, p95 ≤ 40ms, Jitter ≤ 5ms, sem perdas confirmadas
        // Regular: Mediana ≤ 40ms, p95 ≤ 80ms, Jitter ≤ 15ms, instabilidade eventual (1 perda isolada)
        // Ruim: Mediana > 40ms, p95 > 80ms, Jitter > 15ms, perda repetida/confirmada
        let isPoorByLoss: Bool
        let isFairByLoss: Bool

        if let interpretation = lossInterpretation {
            switch interpretation {
            case .severeLoss, .consecutiveLoss:
                isPoorByLoss = true
                isFairByLoss = false
            case .confirmedLoss:
                isPoorByLoss = true
                isFairByLoss = false
            case .isolatedEvent:
                isPoorByLoss = false
                isFairByLoss = true
            case .stable:
                isPoorByLoss = false
                isFairByLoss = false
            }
        } else {
            // Fallback para métricas legadas
            isPoorByLoss = lanLoss > 2.0
            isFairByLoss = lanLoss > 0.0 && lanLoss <= 2.0
        }

        let rating: QualityRating
        if lanMedian > 40.0 || lanP95 > 80.0 || lanJitter > 15.0 || isPoorByLoss {
            rating = .poor
        } else if lanMedian > 20.0 || lanP95 > 40.0 || lanJitter > 5.0 || isFairByLoss {
            rating = .fair
        } else if lanMedian > 10.0 || lanP95 > 20.0 || lanJitter > 3.0 {
            rating = .good
        } else {
            rating = .excellent
        }

        // 2. Cálculo do score determinístico (0-100)
        let score = calculateScore(
            rating: rating,
            lanMedian: lanMedian,
            lanP95: lanP95,
            lanJitter: lanJitter,
            isFairByLoss: isFairByLoss,
            isPoorByLoss: isPoorByLoss
        )

        // 3. Isolamento Wi-Fi vs. Operadora (WAN)
        let (cause, explanation, recommendation) = isolateCause(
            rating: rating,
            lanMedian: lanMedian,
            lanP95: lanP95,
            lanLoss: lanLoss,
            lossInterpretation: lossInterpretation,
            wanMedian: wanMedian,
            wanP95: wanP95,
            wanJitter: wanJitter,
            wanLoss: wanLoss,
            wanLossInterpretation: wanLossInterpretation,
            isRouterRoom: isRouterRoom
        )

        return QualityClassificationResult(
            rating: rating,
            score: score,
            cause: cause,
            explanation: explanation,
            recommendation: recommendation
        )
    }

    private static func calculateScore(
        rating: QualityRating,
        lanMedian: Double,
        lanP95: Double,
        lanJitter: Double,
        isFairByLoss: Bool,
        isPoorByLoss: Bool
    ) -> Int {
        switch rating {
        case .excellent:
            // Escala 90 a 100
            let medianPenalty = min(5.0, (lanMedian / 10.0) * 5.0)
            let p95Penalty = min(3.0, (lanP95 / 20.0) * 3.0)
            let jitterPenalty = min(2.0, (lanJitter / 3.0) * 2.0)
            return max(90, 100 - Int(round(medianPenalty + p95Penalty + jitterPenalty)))

        case .good:
            // Escala 75 a 89
            let medianFactor = max(0.0, min(1.0, (lanMedian - 10.0) / 10.0))
            let p95Factor = max(0.0, min(1.0, (lanP95 - 20.0) / 20.0))
            let jitterFactor = max(0.0, min(1.0, (lanJitter - 3.0) / 2.0))
            let penalty = (medianFactor * 7.0) + (p95Factor * 4.0) + (jitterFactor * 3.0)
            return max(75, 89 - Int(round(penalty)))

        case .fair:
            // Escala 45 a 74
            let medianFactor = max(0.0, min(1.0, (lanMedian - 20.0) / 20.0))
            let p95Factor = max(0.0, min(1.0, (lanP95 - 40.0) / 40.0))
            let jitterFactor = max(0.0, min(1.0, (lanJitter - 5.0) / 10.0))
            let lossPenalty = isFairByLoss ? 8.0 : 0.0
            let penalty = (medianFactor * 12.0) + (p95Factor * 6.0) + (jitterFactor * 4.0) + lossPenalty
            return max(45, 74 - Int(round(penalty)))

        case .poor:
            // Escala 10 a 44
            let lossPenalty = isPoorByLoss ? 18.0 : 6.0
            let latencyPenalty = min(16.0, max(0.0, (lanMedian - 40.0) / 10.0) + max(0.0, (lanP95 - 80.0) / 20.0))
            let raw = 44 - Int(round(lossPenalty + latencyPenalty))
            return max(10, raw)

        case .unmeasured:
            return 0
        }
    }

    private static func isolateCause(
        rating: QualityRating,
        lanMedian: Double,
        lanP95: Double,
        lanLoss: Double,
        lossInterpretation: LossInterpretation?,
        wanMedian: Double,
        wanP95: Double,
        wanJitter: Double,
        wanLoss: Double,
        wanLossInterpretation: LossInterpretation?,
        isRouterRoom: Bool
    ) -> (DiagnosisCause, String, String) {
        let isLanGood = (rating == .excellent || rating == .good)

        // WAN Degradada (Micro-RFC WAN Probing):
        // Mediana > 120ms, p95 > 200ms, Jitter > 30ms ou Perda confirmada
        let isWanDegraded: Bool
        if let wanLossInterp = wanLossInterpretation {
            isWanDegraded = wanMedian > 120.0 || wanP95 > 200.0 || wanJitter > 30.0 || wanLossInterp.isDegraded
        } else {
            isWanDegraded = (wanMedian > 120.0 || wanLoss > 3.0)
        }

        if isLanGood && isWanDegraded {
            return (
                .ispDegraded,
                "Seu Wi-Fi neste cômodo respondeu rapidamente no roteador (\(String(format: "%.0f", lanMedian)) ms), mas a conexão externa com a internet apresentou oscilação (\(String(format: "%.0f", wanMedian)) ms). Causa provável: lentidão na rota externa ou instabilidade na operadora de internet.",
                "O roteador está bem posicionado neste ponto. Como o sinal local está bom, a lentidão percebida provavelmente tem origem externa ou na operadora."
            )
        } else if rating == .poor || rating == .fair {
            if isWanDegraded {
                return (
                    .bothDegraded,
                    "Há oscilação na resposta do roteador local (\(String(format: "%.0f", lanMedian)) ms) combinada com lentidão externa para a internet (\(String(format: "%.0f", wanMedian)) ms).",
                    isRouterRoom ? "O roteador está neste cômodo mas apresentou instabilidade local. Experimente reiniciar o equipamento." : "Aproxime o aparelho do roteador ou considere posicionar o equipamento em ponto mais central da casa."
                )
            } else {
                let lossDetail: String
                if let interpretation = lossInterpretation, interpretation == .isolatedEvent {
                    lossDetail = " (com oscilação isolada de pacotes)"
                } else if lanLoss > 0 {
                    lossDetail = " e \(String(format: "%.1f", lanLoss))% de perda"
                } else {
                    lossDetail = ""
                }

                return (
                    .localWiFiDegraded,
                    "O sinal até o roteador apresentou resposta lenta (\(String(format: "%.0f", lanMedian)) ms mediana, \(String(format: "%.0f", lanP95)) ms p95\(lossDetail)). Causa provável: distância, barreiras físicas no ambiente ou interferência no sinal.",
                    isRouterRoom ? "Certifique-se de que o roteador não está obstruído por móveis fechados, espelhos ou aparelhos eletrônicos." : "Aproxime-se do roteador ou teste reposicionar o equipamento em um local mais central da casa."
                )
            }
        } else {
            return (
                .allGood,
                "Conexão com excelente estabilidade no roteador e tráfego fluindo com rapidez para a internet.",
                "Posição excelente. Nenhuma alteração necessária neste cômodo."
            )
        }
    }
}
