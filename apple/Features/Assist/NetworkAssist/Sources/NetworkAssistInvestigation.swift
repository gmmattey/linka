import Foundation
import NetworkCore

/// Investigação local de falha (issue #56) — quando a internet não
/// funciona, decide se o indício disponível aponta para algo local
/// (aparelho/rede local) ou externo (acesso além do aparelho), ou se os
/// sinais disponíveis não bastam para dizer.
///
/// Deliberadamente separada de `NetworkAssistService`/`NetworkAssistDisposition`
/// (pergunta→resposta sobre números medidos, issue #53): esta é outra
/// capacidade, com outra disposição (`NetworkAssistInvestigationDisposition`)
/// e outro motor — puro, síncrono, 100% on-device, sem nenhum I/O. Isso
/// garante por construção que indisponibilidade de qualquer transport
/// remoto do Assist nunca bloqueia a investigação nem uma nova medição
/// (AGENTS.md §9).

// MARK: - Failure signal (desacoplado de `LinkaEngine.EngineFailureReason`)

/// Fase em que a conexão foi perdida, espelhando `LinkaEngine.Phase` sem
/// depender dele — `NetworkAssist` não importa `LinkaEngine` (AGENTS.md §8).
/// O mapeamento de `EngineFailureReason` para este tipo vive na camada de
/// adapter do app (ver `AssistFailureSignalMapping` em `LinkaApp`).
public enum NetworkAssistFailurePhaseSignal: String, Codable, Equatable, Sendable {
    case ping
    case download
    case upload
    case result
    /// Fase não observável a partir do fato do motor (ex.: `.idle`/`.error`
    /// mapeados aqui) — não deveria ocorrer na prática, mas evita mapeamento
    /// parcial no adapter do app.
    case unspecified
}

/// Sinal de falha próprio do `NetworkAssist`, equivalente a
/// `EngineFailureReason` (issue #66) mas sem depender de `LinkaEngine`.
public enum NetworkAssistFailureSignal: Codable, Equatable, Sendable {
    /// Nenhuma conectividade de rede detectada antes de iniciar a medição.
    case offline
    /// Conexão de transporte perdida de forma não recuperável durante a
    /// fase indicada.
    case connectionLost(phase: NetworkAssistFailurePhaseSignal)
}

// MARK: - Disposição

/// Disposição da investigação — deliberadamente distinta de
/// `NetworkAssistDisposition` (que responde perguntas sobre números
/// medidos). Vocabulário estritamente observacional: nunca "provedor com
/// problema", nunca infraestrutura que o aparelho não observa.
public enum NetworkAssistInvestigationDisposition: String, Codable, Equatable, Sendable {
    /// Indício aponta mais para o aparelho ou a rede local do que para algo
    /// além do acesso do usuário.
    case localSignalLikely
    /// Indício aponta mais para algo além do acesso do usuário do que para
    /// o aparelho ou a rede local.
    case externalSignalLikely
    /// Sinais disponíveis não bastam para diferenciar local de externo.
    case inconclusive
}

/// Sinal tipado que a investigação não teve disponível — equivalente ao
/// `dadosAusentes` do `DiagnosticReport` remoto (`NetworkDiagnostics`), mas
/// local a esta capacidade. Limita literalmente o que a camada de
/// apresentação pode afirmar: nenhuma alegação pode se basear num sinal
/// listado aqui como ausente.
public enum NetworkAssistInvestigationMissingSignal: String, Codable, Equatable, Sendable, CaseIterable {
    /// Não havia `NetworkAssistFailureSignal` para investigar.
    case failureContext
    /// Não havia medições recentes para comparar com a falha atual.
    case recentMeasurementHistory
    /// Não havia teste recente em outra rede/conexão para diferenciar local
    /// de externo.
    case alternateNetworkSample
    /// Nenhuma medição recente trazia `connectionKind`.
    case connectionKind
    /// Conexão recente resolvida como Wi-Fi, mas nenhuma trazia
    /// `wifiBandGHz` (issue #51) — normal no iPhone, onde a plataforma não
    /// expõe a banda.
    case wifiBandGHz
    /// Nenhuma medição recente trazia `loadedLatencyMs` (issue #52) para
    /// servir de referência.
    case loadedLatencyBaseline
}

// MARK: - Input

/// Entrada do motor de investigação. Puramente estrutural — nenhuma chamada
/// de rede é feita para construí-la nem para processá-la.
public struct NetworkAssistInvestigationInput: Equatable, Sendable {
    /// Sinal de falha do teste que motivou a investigação. `nil` quando não
    /// há falha registrada (ex.: Assist aberto a partir de um resultado
    /// bom) — nesse caso a investigação sempre retorna `.inconclusive`.
    public let failureSignal: NetworkAssistFailureSignal?
    /// Medições recentes do usuário, mais recente primeiro. Usadas para
    /// checar estabilidade histórica (`outcome`), `connectionKind`,
    /// `wifiBandGHz` e `loadedLatencyMs` — nunca para sondar outros
    /// dispositivos ou a rede local ativamente.
    public let recentMeasurements: [NetworkMeasurement]

    public init(
        failureSignal: NetworkAssistFailureSignal? = nil,
        recentMeasurements: [NetworkMeasurement] = []
    ) {
        self.failureSignal = failureSignal
        self.recentMeasurements = recentMeasurements
    }
}

// MARK: - Resultado

/// Resultado da investigação. Deliberadamente sem texto: o motor devolve só
/// dado tipado (disposição, evidência, sinais ausentes) — a linguagem
/// observacional em PT-BR é responsabilidade exclusiva da camada de
/// apresentação (mesmo padrão de `EngineFailureReason`, AGENTS.md §8), o
/// que também torna estruturalmente impossível o motor fabricar uma causa.
public struct NetworkAssistInvestigationResult: Equatable, Sendable {
    public let disposition: NetworkAssistInvestigationDisposition
    /// Evidência que sustenta `disposition`, reaproveitando
    /// `NetworkAssistEvidence`/`NetworkAssistEvidenceKind` já existentes.
    public let evidence: [NetworkAssistEvidence]
    /// IDs de `evidence` — sempre não vazio quando `disposition` não é
    /// `.inconclusive`.
    public let evidenceIDs: [String]
    public let missingSignals: [NetworkAssistInvestigationMissingSignal]

    public init(
        disposition: NetworkAssistInvestigationDisposition,
        evidence: [NetworkAssistEvidence] = [],
        evidenceIDs: [String] = [],
        missingSignals: [NetworkAssistInvestigationMissingSignal] = []
    ) {
        self.disposition = disposition
        self.evidence = evidence
        self.evidenceIDs = evidenceIDs
        self.missingSignals = missingSignals
    }
}

// MARK: - Motor

/// Motor de regras determinístico e puro: mesma entrada sempre produz a
/// mesma saída, sem I/O, sem `async`, sem depender de nenhum transport
/// remoto (`NetworkDiagnostics`/SignallQ). Um sinal de falha nunca é uma
/// causa: quando ele não basta para diferenciar o problema, devolve
/// `.inconclusive` com o fato observado.
public enum NetworkAssistInvestigationEngine {
    /// Quantidade de medições recentes efetivamente consideradas. Limitado
    /// para manter o motor barato e a evidência legível — não é uma
    /// tentativa de média estatística robusta.
    private static let maximumConsideredRecentMeasurements = 5

    private static let failureSignalEvidenceID = "investigation:failure-signal"
    private static let recentHistoryEvidenceID = "investigation:recent-history"
    private static let connectionContextEvidenceID = "investigation:connection-kind"
    private static let wifiBandEvidenceID = "investigation:wifi-band"
    private static let loadedLatencyEvidenceID = "investigation:loaded-latency"

    public static func investigate(_ input: NetworkAssistInvestigationInput) -> NetworkAssistInvestigationResult {
        guard let failureSignal = input.failureSignal else {
            return NetworkAssistInvestigationResult(
                disposition: .inconclusive,
                missingSignals: [.failureContext]
            )
        }

        switch failureSignal {
        case .offline:
            return offlineResult()
        case .connectionLost(let phase):
            return connectionLostResult(phase: phase, recentMeasurements: input.recentMeasurements)
        }
    }

    /// `.offline` só comprova que não havia caminho de rede disponível antes
    /// de a medição começar. Não diferencia Wi-Fi, celular, portal cativo,
    /// modo avião ou indisponibilidade além do aparelho; portanto não pode
    /// produzir hipótese causal nem orientação específica.
    private static func offlineResult() -> NetworkAssistInvestigationResult {
        let evidence = failureSignalEvidence(direction: "offline")
        return NetworkAssistInvestigationResult(
            disposition: .inconclusive,
            evidence: [evidence],
            evidenceIDs: [evidence.id],
            missingSignals: [.connectionKind, .alternateNetworkSample]
        )
    }

    /// `.connectionLost` significa que a conexão chegou a ser estabelecida
    /// (a fase indicada já estava em andamento) e foi perdida de forma não
    /// recuperável. Ao contrário de `.offline`, isso por si só não decide
    /// nada — usa o histórico recente (`outcome`) como sinal de
    /// estabilidade: testes recentes incompletos formam um padrão
    /// consistente com algo local recorrente; testes recentes completos
    /// tornam essa queda pontual mais consistente com algo além do acesso.
    /// Sem nenhum histórico, não há como diferenciar — inconclusivo.
    private static func connectionLostResult(
        phase: NetworkAssistFailurePhaseSignal,
        recentMeasurements: [NetworkMeasurement]
    ) -> NetworkAssistInvestigationResult {
        let failureEvidence = failureSignalEvidence(direction: "connectionLost:\(phase.rawValue)")
        let considered = Array(recentMeasurements.prefix(maximumConsideredRecentMeasurements))

        guard !considered.isEmpty else {
            return NetworkAssistInvestigationResult(
                disposition: .inconclusive,
                evidence: [failureEvidence],
                evidenceIDs: [failureEvidence.id],
                missingSignals: [.recentMeasurementHistory, .alternateNetworkSample]
            )
        }

        var evidence: [NetworkAssistEvidence] = [failureEvidence]
        var missingSignals: [NetworkAssistInvestigationMissingSignal] = []

        let partialCount = considered.filter { $0.outcome == .partial }.count
        evidence.append(
            NetworkAssistEvidence(
                id: recentHistoryEvidenceID,
                kind: .trend,
                metricKey: "recentOutcomeStability",
                value: Double(considered.count - partialCount),
                baselineValue: Double(considered.count),
                direction: partialCount > 0 ? "unstable" : "stable",
                sourceMeasurementIDs: considered.map(\.id)
            )
        )

        if let connectionKind = predominantConnectionKind(in: considered) {
            let matchingIDs = considered.filter { $0.connectionKind == connectionKind }.map(\.id)
            evidence.append(
                NetworkAssistEvidence(
                    id: connectionContextEvidenceID,
                    kind: .context,
                    metricKey: "connectionKind",
                    direction: connectionKind.rawValue,
                    sourceMeasurementIDs: matchingIDs
                )
            )

            if connectionKind == .wifi {
                if let band = averageWifiBandGHz(in: considered) {
                    evidence.append(
                        NetworkAssistEvidence(
                            id: wifiBandEvidenceID,
                            kind: .context,
                            metricKey: "wifiBandGHz",
                            value: band.value,
                            unit: "GHz",
                            sourceMeasurementIDs: band.measurementIDs
                        )
                    )
                } else {
                    missingSignals.append(.wifiBandGHz)
                }
            }
        } else {
            missingSignals.append(.connectionKind)
        }

        if let latency = averageLoadedLatencyMs(in: considered) {
            evidence.append(
                NetworkAssistEvidence(
                    id: loadedLatencyEvidenceID,
                    kind: .statistic,
                    metricKey: "loadedLatencyMs",
                    value: latency.value,
                    unit: "ms",
                    sourceMeasurementIDs: latency.measurementIDs
                )
            )
        } else {
            missingSignals.append(.loadedLatencyBaseline)
        }

        let disposition: NetworkAssistInvestigationDisposition = partialCount > 0
            ? .localSignalLikely
            : .externalSignalLikely

        return NetworkAssistInvestigationResult(
            disposition: disposition,
            evidence: evidence,
            evidenceIDs: evidence.map(\.id),
            missingSignals: missingSignals
        )
    }

    private static func failureSignalEvidence(direction: String) -> NetworkAssistEvidence {
        NetworkAssistEvidence(
            id: failureSignalEvidenceID,
            kind: .context,
            metricKey: "failureSignal",
            direction: direction
        )
    }

    private static func predominantConnectionKind(
        in measurements: [NetworkMeasurement]
    ) -> NetworkConnectionKind? {
        let kinds = measurements.compactMap(\.connectionKind)
        guard !kinds.isEmpty else { return nil }
        var counts: [NetworkConnectionKind: Int] = [:]
        for kind in kinds { counts[kind, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func averageLoadedLatencyMs(
        in measurements: [NetworkMeasurement]
    ) -> (value: Double, measurementIDs: [UUID])? {
        let samples = measurements.compactMap { measurement -> (UUID, Double)? in
            guard let latency = measurement.trustedLoadedLatencies.downloadMs else { return nil }
            return (measurement.id, latency)
        }
        guard !samples.isEmpty else { return nil }
        let average = samples.map(\.1).reduce(0, +) / Double(samples.count)
        return (average, samples.map(\.0))
    }

    private static func averageWifiBandGHz(
        in measurements: [NetworkMeasurement]
    ) -> (value: Double, measurementIDs: [UUID])? {
        let samples = measurements.compactMap { measurement -> (UUID, Double)? in
            guard measurement.connectionKind == .wifi, let band = measurement.wifiBandGHz else { return nil }
            return (measurement.id, band)
        }
        guard !samples.isEmpty else { return nil }
        let average = samples.map(\.1).reduce(0, +) / Double(samples.count)
        return (average, samples.map(\.0))
    }
}
