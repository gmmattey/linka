import Foundation
import NetworkCore

/// Caso de uso cotidiano cuja adequação a conexão medida hoje sustenta ou
/// não (issue #57). Deliberadamente genérico — nunca cita marca, jogo,
/// app ou serviço específico (AGENTS.md §1/§9): a rota real até um
/// servidor de jogo ou de streaming específico nunca é medida pelo Linka,
/// então nenhum veredito pode prometer desempenho de título algum.
///
/// A ordem dos casos aqui não implica prioridade de produto — a UI decide
/// qual frase mostrar quando mais de um caso está `.adequate` (issue #57,
/// `DetailsDisclosure.swift`).
public enum UsageCase: String, Codable, CaseIterable, Equatable, Sendable {
    case videoCall
    case streamingHD
    case streaming4K
    case onlineGaming
    /// Upload sustentado e sensível a estabilidade — envio de arquivos
    /// grandes, backup, transmissão de vídeo, acesso remoto. Distinto de
    /// `videoCall`, que tolera menos upload mas é mais sensível a latência
    /// instantânea que a jitter sustentada.
    case workUpload
}

/// Grau de confiança de um veredito de `UsageCase`.
///
/// `.notAssessed` não é "ruim" — é "não sabemos", reservado para quando uma
/// métrica indispensável para julgar aquele caso de uso está ausente. Uma
/// métrica ausente nunca é tratada como zero nem promove silenciosamente
/// `.adequate` (requisito explícito da issue #57).
public enum SuitabilityLevel: String, Codable, Equatable, Sendable {
    case adequate
    case limited
    case notAssessed
}

/// Veredito de um único `UsageCase` para uma medição.
public struct UsageCaseVerdict: Codable, Equatable, Sendable {
    public let usageCase: UsageCase
    public let level: SuitabilityLevel
    /// Métrica que está limitando a conclusão — a que está fora do limite
    /// aceitável, ou a que está ausente e por isso impede confiança plena.
    /// `nil` somente quando `level == .adequate` (nada limitando o uso).
    public let limitingMetric: NetworkMetric?

    public init(usageCase: UsageCase, level: SuitabilityLevel, limitingMetric: NetworkMetric?) {
        self.usageCase = usageCase
        self.level = level
        self.limitingMetric = limitingMetric
    }
}

/// Conjunto de veredictos, um por `UsageCase`, para uma medição.
public struct UsageSuitabilityReport: Codable, Equatable, Sendable {
    public let verdicts: [UsageCaseVerdict]

    public init(verdicts: [UsageCaseVerdict]) {
        self.verdicts = verdicts
    }

    public func verdict(for usageCase: UsageCase) -> UsageCaseVerdict? {
        verdicts.first { $0.usageCase == usageCase }
    }
}

/// Limiares objetivos usados para classificar cada `UsageCase`. Números de
/// partida validados pelo Giam (issue #57) — ajustáveis sem mexer na
/// lógica de classificação.
public struct UsageSuitabilityThresholds: Equatable, Sendable {
    public var videoCallMinUploadMbps: Double
    public var videoCallMaxLatencyMs: Double
    public var videoCallMaxJitterMs: Double
    public var videoCallMaxPacketLossPercent: Double

    public var streamingHDMinDownloadMbps: Double

    public var streaming4KMinDownloadMbps: Double
    public var streaming4KMaxPacketLossPercent: Double

    public var onlineGamingMaxLatencyMs: Double
    public var onlineGamingMaxJitterMs: Double
    public var onlineGamingMaxPacketLossPercent: Double

    public var workUploadMinUploadMbps: Double
    public var workUploadMaxJitterMs: Double
    public var workUploadMaxLatencyMs: Double
    public var workUploadMaxPacketLossPercent: Double

    public init(
        videoCallMinUploadMbps: Double = 3,
        videoCallMaxLatencyMs: Double = 150,
        videoCallMaxJitterMs: Double = 30,
        videoCallMaxPacketLossPercent: Double = 2,
        streamingHDMinDownloadMbps: Double = 5,
        streaming4KMinDownloadMbps: Double = 25,
        streaming4KMaxPacketLossPercent: Double = 2,
        onlineGamingMaxLatencyMs: Double = 50,
        onlineGamingMaxJitterMs: Double = 30,
        onlineGamingMaxPacketLossPercent: Double = 1,
        workUploadMinUploadMbps: Double = 5,
        workUploadMaxJitterMs: Double = 40,
        workUploadMaxLatencyMs: Double = 200,
        workUploadMaxPacketLossPercent: Double = 2
    ) {
        self.videoCallMinUploadMbps = videoCallMinUploadMbps
        self.videoCallMaxLatencyMs = videoCallMaxLatencyMs
        self.videoCallMaxJitterMs = videoCallMaxJitterMs
        self.videoCallMaxPacketLossPercent = videoCallMaxPacketLossPercent
        self.streamingHDMinDownloadMbps = streamingHDMinDownloadMbps
        self.streaming4KMinDownloadMbps = streaming4KMinDownloadMbps
        self.streaming4KMaxPacketLossPercent = streaming4KMaxPacketLossPercent
        self.onlineGamingMaxLatencyMs = onlineGamingMaxLatencyMs
        self.onlineGamingMaxJitterMs = onlineGamingMaxJitterMs
        self.onlineGamingMaxPacketLossPercent = onlineGamingMaxPacketLossPercent
        self.workUploadMinUploadMbps = workUploadMinUploadMbps
        self.workUploadMaxJitterMs = workUploadMaxJitterMs
        self.workUploadMaxLatencyMs = workUploadMaxLatencyMs
        self.workUploadMaxPacketLossPercent = workUploadMaxPacketLossPercent
    }
}

public protocol UsageSuitabilityEvaluating: Sendable {
    func evaluate(_ measurement: NetworkMeasurement) -> UsageSuitabilityReport
}

/// Classificação pura e testável de uma `NetworkMeasurement` contra
/// limiares objetivos por caso de uso (issue #57). Não conhece copy de
/// produto, não conhece marca/jogo/serviço e não lança erro — trabalha
/// nil-safe com o que a medição tiver, rebaixando o veredito quando uma
/// métrica necessária está ausente em vez de assumir um valor (AGENTS.md
/// §8/§9).
public struct UsageSuitabilityEvaluator: UsageSuitabilityEvaluating {
    public let thresholds: UsageSuitabilityThresholds

    public init(thresholds: UsageSuitabilityThresholds = .init()) {
        self.thresholds = thresholds
    }

    public func evaluate(_ measurement: NetworkMeasurement) -> UsageSuitabilityReport {
        UsageSuitabilityReport(
            verdicts: UsageCase.allCases.map { evaluate($0, in: measurement) }
        )
    }

    private func evaluate(_ usageCase: UsageCase, in measurement: NetworkMeasurement) -> UsageCaseVerdict {
        switch usageCase {
        case .videoCall:
            return evaluateVideoCall(measurement)
        case .streamingHD:
            return evaluateStreamingHD(measurement)
        case .streaming4K:
            return evaluateStreaming4K(measurement)
        case .onlineGaming:
            return evaluateOnlineGaming(measurement)
        case .workUpload:
            return evaluateWorkUpload(measurement)
        }
    }

    // MARK: - Chamada em vídeo

    private func evaluateVideoCall(_ measurement: NetworkMeasurement) -> UsageCaseVerdict {
        guard hasCompletedProbeEvidence(measurement) else {
            return verdict(.videoCall, .notAssessed, .packetLossPercent)
        }
        guard let uploadMbps = measurement.uploadMbps else {
            return verdict(.videoCall, .notAssessed, .uploadMbps)
        }
        guard let latencyMs = measurement.latencyMs else {
            return verdict(.videoCall, .notAssessed, .latencyMs)
        }
        guard let jitterMs = measurement.jitterMs else {
            return verdict(.videoCall, .notAssessed, .jitterMs)
        }
        guard let loadedLatency = worstTrustedLoadedLatency(measurement) else {
            return verdict(.videoCall, .notAssessed, .loadedLatencyMs)
        }

        if uploadMbps < thresholds.videoCallMinUploadMbps {
            return verdict(.videoCall, .limited, .uploadMbps)
        }
        if latencyMs > thresholds.videoCallMaxLatencyMs {
            return verdict(.videoCall, .limited, .latencyMs)
        }
        if jitterMs > thresholds.videoCallMaxJitterMs {
            return verdict(.videoCall, .limited, .jitterMs)
        }
        if loadedLatency > thresholds.videoCallMaxLatencyMs {
            return verdict(.videoCall, .limited, .loadedLatencyMs)
        }

        return verdict(
            .videoCall,
            packetLossOutcome(
                measurement.packetLossPercent,
                maxAllowed: thresholds.videoCallMaxPacketLossPercent
            )
        )
    }

    // MARK: - Streaming padrão/HD

    private func evaluateStreamingHD(_ measurement: NetworkMeasurement) -> UsageCaseVerdict {
        guard let downloadMbps = measurement.downloadMbps else {
            return verdict(.streamingHD, .notAssessed, .downloadMbps)
        }

        if downloadMbps < thresholds.streamingHDMinDownloadMbps {
            return verdict(.streamingHD, .limited, .downloadMbps)
        }

        return verdict(.streamingHD, .adequate, nil)
    }

    // MARK: - Streaming 4K

    private func evaluateStreaming4K(_ measurement: NetworkMeasurement) -> UsageCaseVerdict {
        guard let downloadMbps = measurement.downloadMbps else {
            return verdict(.streaming4K, .notAssessed, .downloadMbps)
        }

        if downloadMbps <= thresholds.streaming4KMinDownloadMbps {
            return verdict(.streaming4K, .limited, .downloadMbps)
        }

        return verdict(
            .streaming4K,
            packetLossOutcome(
                measurement.packetLossPercent,
                maxAllowed: thresholds.streaming4KMaxPacketLossPercent
            )
        )
    }

    // MARK: - Jogo online

    private func evaluateOnlineGaming(_ measurement: NetworkMeasurement) -> UsageCaseVerdict {
        guard hasCompletedProbeEvidence(measurement) else {
            return verdict(.onlineGaming, .notAssessed, .packetLossPercent)
        }
        guard let reference = measurement.regionalGameReference,
              reference.status == .measured,
              let referenceLatency = reference.p50LatencyMs else {
            return verdict(.onlineGaming, .notAssessed, .latencyMs)
        }
        // Preferimos latência sob carga quando existir — mais representativa
        // de jogo online (conexão ocupada) que o ping isolado — mas caímos
        // para `latencyMs` quando o motor não calculou `loadedLatencyMs`
        // para este teste, em vez de marcar como não avaliado à toa.
        guard let latencyMs = worstTrustedLoadedLatency(measurement) else {
            return verdict(.onlineGaming, .notAssessed, .loadedLatencyMs)
        }
        guard let jitterMs = measurement.jitterMs else {
            return verdict(.onlineGaming, .notAssessed, .jitterMs)
        }

        if latencyMs > thresholds.onlineGamingMaxLatencyMs {
            return verdict(.onlineGaming, .limited, .loadedLatencyMs)
        }
        if jitterMs > thresholds.onlineGamingMaxJitterMs {
            return verdict(.onlineGaming, .limited, .jitterMs)
        }
        if referenceLatency > thresholds.onlineGamingMaxLatencyMs {
            return verdict(.onlineGaming, .limited, .latencyMs)
        }

        return verdict(
            .onlineGaming,
            packetLossOutcome(
                measurement.packetLossPercent,
                maxAllowed: thresholds.onlineGamingMaxPacketLossPercent
            )
        )
    }

    // MARK: - Upload/trabalho

    private func evaluateWorkUpload(_ measurement: NetworkMeasurement) -> UsageCaseVerdict {
        guard let uploadMbps = measurement.uploadMbps else {
            return verdict(.workUpload, .notAssessed, .uploadMbps)
        }
        guard let jitterMs = measurement.jitterMs else {
            return verdict(.workUpload, .notAssessed, .jitterMs)
        }

        if uploadMbps < thresholds.workUploadMinUploadMbps {
            return verdict(.workUpload, .limited, .uploadMbps)
        }
        if jitterMs > thresholds.workUploadMaxJitterMs {
            return verdict(.workUpload, .limited, .jitterMs)
        }
        if let latencyMs = measurement.latencyMs, latencyMs > thresholds.workUploadMaxLatencyMs {
            return verdict(.workUpload, .limited, .latencyMs)
        }

        return verdict(
            .workUpload,
            packetLossOutcome(
                measurement.packetLossPercent,
                maxAllowed: thresholds.workUploadMaxPacketLossPercent
            )
        )
    }

    // MARK: - Auxiliares

    /// `packetLossPercent` é um sinal opcional em todos os casos de uso que
    /// o usam: quando o motor mediu perda de pacotes (mesmo `0`), ela entra
    /// na decisão normalmente. Quando é `nil` — ausência, não zero — o
    /// veredito não vira `.adequate` pleno mesmo com as demais métricas
    /// dentro do limiar: rebaixa para `.limited` porque falta esse sinal
    /// para confirmar a conclusão (requisito explícito da issue #57).
    private func packetLossOutcome(
        _ packetLossPercent: Double?,
        maxAllowed: Double
    ) -> (SuitabilityLevel, NetworkMetric?) {
        guard let packetLossPercent else {
            return (.limited, .packetLossPercent)
        }
        if packetLossPercent > maxAllowed {
            return (.limited, .packetLossPercent)
        }
        return (.adequate, nil)
    }

    private func hasCompletedProbeEvidence(_ measurement: NetworkMeasurement) -> Bool {
        measurement.packetProbeEvidence?.completed == true
    }

    private func worstTrustedLoadedLatency(_ measurement: NetworkMeasurement) -> Double? {
        let loaded = measurement.trustedLoadedLatencies
        guard let download = loaded.downloadMs, let upload = loaded.uploadMs else { return nil }
        return max(download, upload)
    }

    private func verdict(
        _ usageCase: UsageCase,
        _ outcome: (SuitabilityLevel, NetworkMetric?)
    ) -> UsageCaseVerdict {
        UsageCaseVerdict(usageCase: usageCase, level: outcome.0, limitingMetric: outcome.1)
    }

    private func verdict(
        _ usageCase: UsageCase,
        _ level: SuitabilityLevel,
        _ limitingMetric: NetworkMetric?
    ) -> UsageCaseVerdict {
        UsageCaseVerdict(usageCase: usageCase, level: level, limitingMetric: limitingMetric)
    }
}
