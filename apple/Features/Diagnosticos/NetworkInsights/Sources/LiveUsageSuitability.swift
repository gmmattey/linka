import Foundation
import NetworkCore

/// Grau de confiança de um veredito avaliado ao vivo (sem teste pesado de velocidade).
public enum LiveAssessmentConfidence: String, Codable, Equatable, Sendable {
    /// Julgado 100% com telemetria instantânea da rota (ex: latência, jitter, perda de pacotes).
    case liveTelemetry
    /// Julgado combinando telemetria ao vivo com histórico recente de vazão na mesma rede.
    case historicalBaselineInferred
    /// Dados insuficientes de vazão para julgar o caso sem um teste de velocidade ativo.
    case insufficientData
}

/// Razão estruturada pela qual um caso de uso ao vivo foi limitado ou não avaliado.
public enum LiveSuitabilityLimitingReason: String, Codable, Equatable, Sendable {
    case latencyTooHigh
    case jitterTooHigh
    case packetLossExceeded
    case throughputBelowMinimum
    case missingThroughputMeasurement
    case constrainedModeActive
    case networkUnavailable
}

/// Veredito de adequação de um `UsageCase` calculado em tempo real.
public struct LiveUsageCaseVerdict: Codable, Equatable, Sendable {
    public let usageCase: UsageCase
    public let level: SuitabilityLevel
    public let confidence: LiveAssessmentConfidence
    public let limitingMetric: NetworkMetric?
    public let reason: LiveSuitabilityLimitingReason?

    public init(
        usageCase: UsageCase,
        level: SuitabilityLevel,
        confidence: LiveAssessmentConfidence,
        limitingMetric: NetworkMetric? = nil,
        reason: LiveSuitabilityLimitingReason? = nil
    ) {
        self.usageCase = usageCase
        self.level = level
        self.confidence = confidence
        self.limitingMetric = limitingMetric
        self.reason = reason
    }
}

/// Relatório agregado contendo os vereditos ao vivo de todos os casos de uso.
public struct LiveUsageSuitabilityReport: Codable, Equatable, Sendable {
    public let evaluatedAt: Date
    public let verdicts: [LiveUsageCaseVerdict]
    public let telemetry: LiveNetworkTelemetrySnapshot
    public let baseline: ThroughputBaseline?

    public init(
        evaluatedAt: Date = Date(),
        verdicts: [LiveUsageCaseVerdict],
        telemetry: LiveNetworkTelemetrySnapshot,
        baseline: ThroughputBaseline? = nil
    ) {
        self.evaluatedAt = evaluatedAt
        self.verdicts = verdicts
        self.telemetry = telemetry
        self.baseline = baseline
    }

    public func verdict(for usageCase: UsageCase) -> LiveUsageCaseVerdict? {
        verdicts.first { $0.usageCase == usageCase }
    }
}

public protocol LiveUsageSuitabilityEvaluating: Sendable {
    func evaluate(
        telemetry: LiveNetworkTelemetrySnapshot,
        baseline: ThroughputBaseline?
    ) -> LiveUsageSuitabilityReport
}

/// Avaliador determinístico de casos de uso ao vivo.
///
/// Função pura e desacoplada de UI/sockets (AGENTS.md §8 e §9).
/// Não inventa taxas de transferência e rebaixa confianças honestamente
/// quando dados essenciais de vazão estão ausentes.
public struct LiveUsageSuitabilityEvaluator: LiveUsageSuitabilityEvaluating {
    public let thresholds: UsageSuitabilityThresholds

    public init(thresholds: UsageSuitabilityThresholds = .init()) {
        self.thresholds = thresholds
    }

    public func evaluate(
        telemetry: LiveNetworkTelemetrySnapshot,
        baseline: ThroughputBaseline? = nil
    ) -> LiveUsageSuitabilityReport {
        // Home é uma observação, não a medição formal. Três respostas boas
        // não autorizam conclusão de uso; a janela só amadurece com cinco.
        if telemetry.sampleCount < 5 {
            return LiveUsageSuitabilityReport(
                verdicts: UsageCase.allCases.map {
                    LiveUsageCaseVerdict(
                        usageCase: $0,
                        level: .notAssessed,
                        confidence: .insufficientData,
                        limitingMetric: $0 == .onlineGaming ? .jitterMs : nil,
                        reason: .missingThroughputMeasurement
                    )
                },
                telemetry: telemetry,
                baseline: baseline
            )
        }
        let verdicts = UsageCase.allCases.map { usageCase in
            evaluateCase(usageCase, telemetry: telemetry, baseline: baseline)
        }
        return LiveUsageSuitabilityReport(
            verdicts: verdicts,
            telemetry: telemetry,
            baseline: baseline
        )
    }

    /// Uma única falha numa janela curta não é instabilidade. Como o snapshot
    /// expõe apenas a porcentagem agregada, convertemos de volta para uma
    /// contagem mínima e só promovemos o sintoma a partir de duas falhas.
    private func hasRepeatedLoss(_ telemetry: LiveNetworkTelemetrySnapshot, threshold: Double) -> Bool {
        guard let loss = telemetry.packetLossPercent, loss > threshold else { return false }
        return (loss * Double(telemetry.sampleCount) / 100) >= 2
    }

    private func evaluateCase(
        _ usageCase: UsageCase,
        telemetry: LiveNetworkTelemetrySnapshot,
        baseline: ThroughputBaseline?
    ) -> LiveUsageCaseVerdict {
        switch usageCase {
        case .onlineGaming:
            return evaluateGaming(telemetry: telemetry)
        case .videoCall:
            return evaluateVideoCall(telemetry: telemetry, baseline: baseline)
        case .streamingHD:
            return evaluateStreamingHD(telemetry: telemetry, baseline: baseline)
        case .streaming4K:
            return evaluateStreaming4K(telemetry: telemetry, baseline: baseline)
        case .workUpload:
            return evaluateWorkUpload(telemetry: telemetry, baseline: baseline)
        }
    }

    // MARK: - 1. Jogos Online (Online Gaming)
    // Sensível primariamente a RTT, jitter e perda de pacotes; demanda baixa vazão.
    private func evaluateGaming(telemetry: LiveNetworkTelemetrySnapshot) -> LiveUsageCaseVerdict {
        guard let latency = telemetry.latencyMs else {
            return LiveUsageCaseVerdict(
                usageCase: .onlineGaming,
                level: .notAssessed,
                confidence: .insufficientData,
                limitingMetric: .latencyMs,
                reason: .networkUnavailable
            )
        }

        if latency > thresholds.onlineGamingMaxLatencyMs {
            return LiveUsageCaseVerdict(
                usageCase: .onlineGaming,
                level: .limited,
                confidence: .liveTelemetry,
                limitingMetric: .latencyMs,
                reason: .latencyTooHigh
            )
        }

        if let jitter = telemetry.jitterMs, jitter > thresholds.onlineGamingMaxJitterMs {
            return LiveUsageCaseVerdict(
                usageCase: .onlineGaming,
                level: .limited,
                confidence: .liveTelemetry,
                limitingMetric: .jitterMs,
                reason: .jitterTooHigh
            )
        }

        if hasRepeatedLoss(telemetry, threshold: thresholds.onlineGamingMaxPacketLossPercent) {
            return LiveUsageCaseVerdict(
                usageCase: .onlineGaming,
                level: .limited,
                confidence: .liveTelemetry,
                limitingMetric: .packetLossPercent,
                reason: .packetLossExceeded
            )
        }

        // AGENTS.md §8: Ausência de jitter (amostras < 3) não é zero nem promove adequado
        guard let _ = telemetry.jitterMs, telemetry.sampleCount >= 3 else {
            return LiveUsageCaseVerdict(
                usageCase: .onlineGaming,
                level: .notAssessed,
                confidence: .insufficientData,
                limitingMetric: .jitterMs,
                reason: .missingThroughputMeasurement
            )
        }

        return LiveUsageCaseVerdict(
            usageCase: .onlineGaming,
            level: .adequate,
            confidence: .liveTelemetry
        )
    }

    // MARK: - 2. Chamadas em Vídeo (Video Call)
    // Sensível a latência, perda de pacotes e upload modesto (~3 Mbps).
    private func evaluateVideoCall(
        telemetry: LiveNetworkTelemetrySnapshot,
        baseline: ThroughputBaseline?
    ) -> LiveUsageCaseVerdict {
        if telemetry.isConstrained {
            return LiveUsageCaseVerdict(
                usageCase: .videoCall,
                level: .limited,
                confidence: .liveTelemetry,
                limitingMetric: .uploadMbps,
                reason: .constrainedModeActive
            )
        }

        guard let latency = telemetry.latencyMs else {
            return LiveUsageCaseVerdict(
                usageCase: .videoCall,
                level: .notAssessed,
                confidence: .insufficientData,
                limitingMetric: .latencyMs,
                reason: .networkUnavailable
            )
        }

        if latency > thresholds.videoCallMaxLatencyMs {
            return LiveUsageCaseVerdict(
                usageCase: .videoCall,
                level: .limited,
                confidence: .liveTelemetry,
                limitingMetric: .latencyMs,
                reason: .latencyTooHigh
            )
        }

        if hasRepeatedLoss(telemetry, threshold: thresholds.videoCallMaxPacketLossPercent) {
            return LiveUsageCaseVerdict(
                usageCase: .videoCall,
                level: .limited,
                confidence: .liveTelemetry,
                limitingMetric: .packetLossPercent,
                reason: .packetLossExceeded
            )
        }

        // AGENTS.md §6/§8: Chamada em vídeo exige upload (min. 3 Mbps). Ausência de upload medido
        // nunca promove silenciosamente para .adequate (mesmo princípio de UsageSuitability.swift:160).
        guard let baselineUpload = baseline?.uploadMbps else {
            return LiveUsageCaseVerdict(
                usageCase: .videoCall,
                level: .notAssessed,
                confidence: .insufficientData,
                limitingMetric: .uploadMbps,
                reason: .missingThroughputMeasurement
            )
        }

        if baselineUpload < thresholds.videoCallMinUploadMbps {
            return LiveUsageCaseVerdict(
                usageCase: .videoCall,
                level: .limited,
                confidence: .historicalBaselineInferred,
                limitingMetric: .uploadMbps,
                reason: .throughputBelowMinimum
            )
        }

        return LiveUsageCaseVerdict(
            usageCase: .videoCall,
            level: .adequate,
            confidence: .historicalBaselineInferred
        )
    }

    // MARK: - 3. Streaming HD
    private func evaluateStreamingHD(
        telemetry: LiveNetworkTelemetrySnapshot,
        baseline: ThroughputBaseline?
    ) -> LiveUsageCaseVerdict {
        guard let downloadMbps = baseline?.downloadMbps else {
            return LiveUsageCaseVerdict(
                usageCase: .streamingHD,
                level: .notAssessed,
                confidence: .insufficientData,
                limitingMetric: .downloadMbps,
                reason: .missingThroughputMeasurement
            )
        }

        if downloadMbps < thresholds.streamingHDMinDownloadMbps {
            return LiveUsageCaseVerdict(
                usageCase: .streamingHD,
                level: .limited,
                confidence: .historicalBaselineInferred,
                limitingMetric: .downloadMbps,
                reason: .throughputBelowMinimum
            )
        }

        if hasRepeatedLoss(telemetry, threshold: thresholds.streaming4KMaxPacketLossPercent) {
            return LiveUsageCaseVerdict(
                usageCase: .streamingHD,
                level: .limited,
                confidence: .historicalBaselineInferred,
                limitingMetric: .packetLossPercent,
                reason: .packetLossExceeded
            )
        }

        return LiveUsageCaseVerdict(
            usageCase: .streamingHD,
            level: .adequate,
            confidence: .historicalBaselineInferred
        )
    }

    // MARK: - 4. Streaming 4K
    private func evaluateStreaming4K(
        telemetry: LiveNetworkTelemetrySnapshot,
        baseline: ThroughputBaseline?
    ) -> LiveUsageCaseVerdict {
        guard let downloadMbps = baseline?.downloadMbps else {
            return LiveUsageCaseVerdict(
                usageCase: .streaming4K,
                level: .notAssessed,
                confidence: .insufficientData,
                limitingMetric: .downloadMbps,
                reason: .missingThroughputMeasurement
            )
        }

        if downloadMbps < thresholds.streaming4KMinDownloadMbps {
            return LiveUsageCaseVerdict(
                usageCase: .streaming4K,
                level: .limited,
                confidence: .historicalBaselineInferred,
                limitingMetric: .downloadMbps,
                reason: .throughputBelowMinimum
            )
        }

        if hasRepeatedLoss(telemetry, threshold: thresholds.streaming4KMaxPacketLossPercent) {
            return LiveUsageCaseVerdict(
                usageCase: .streaming4K,
                level: .limited,
                confidence: .historicalBaselineInferred,
                limitingMetric: .packetLossPercent,
                reason: .packetLossExceeded
            )
        }

        return LiveUsageCaseVerdict(
            usageCase: .streaming4K,
            level: .adequate,
            confidence: .historicalBaselineInferred
        )
    }

    // MARK: - 5. Upload de Trabalho (Work Upload)
    private func evaluateWorkUpload(
        telemetry: LiveNetworkTelemetrySnapshot,
        baseline: ThroughputBaseline?
    ) -> LiveUsageCaseVerdict {
        guard let uploadMbps = baseline?.uploadMbps else {
            return LiveUsageCaseVerdict(
                usageCase: .workUpload,
                level: .notAssessed,
                confidence: .insufficientData,
                limitingMetric: .uploadMbps,
                reason: .missingThroughputMeasurement
            )
        }

        if uploadMbps < thresholds.workUploadMinUploadMbps {
            return LiveUsageCaseVerdict(
                usageCase: .workUpload,
                level: .limited,
                confidence: .historicalBaselineInferred,
                limitingMetric: .uploadMbps,
                reason: .throughputBelowMinimum
            )
        }

        if let jitter = telemetry.jitterMs, jitter > thresholds.workUploadMaxJitterMs {
            return LiveUsageCaseVerdict(
                usageCase: .workUpload,
                level: .limited,
                confidence: .historicalBaselineInferred,
                limitingMetric: .jitterMs,
                reason: .jitterTooHigh
            )
        }

        return LiveUsageCaseVerdict(
            usageCase: .workUpload,
            level: .adequate,
            confidence: .historicalBaselineInferred
        )
    }
}
