import Foundation
import LinkaEntitlements
import NetworkAssist
import NetworkCore
import NetworkInsights

/// Narrativa de uma única métrica dentro de um grupo de rede — sempre
/// presente para toda métrica varrida, mesmo quando não há padrão (issue
/// #125, item 3: nunca omitir silenciosamente, sempre um estado explícito).
public struct NetworkStabilityMetricNarrative: Equatable, Sendable {
    public let metric: NetworkAssistMetricSignal
    public let narrative: NetworkAssistStabilityNarrative

    public init(metric: NetworkAssistMetricSignal, narrative: NetworkAssistStabilityNarrative) {
        self.metric = metric
        self.narrative = narrative
    }
}

/// Relatório de estabilidade de um único grupo de rede: as
/// estatísticas/tendência gerais do grupo (reaproveitando
/// `BasicNetworkInsightsAnalyzer`, issue #125 item 1) mais a narrativa de
/// padrão por horário de cada métrica varrida (item 2 + item 3).
public struct NetworkStabilityPatternReport: Equatable, Sendable {
    public let connectionKind: NetworkConnectionKind
    public let networkIdentifier: String
    public let summary: NetworkInsightsSummary
    public let metricNarratives: [NetworkStabilityMetricNarrative]

    public init(
        connectionKind: NetworkConnectionKind,
        networkIdentifier: String,
        summary: NetworkInsightsSummary,
        metricNarratives: [NetworkStabilityMetricNarrative]
    ) {
        self.connectionKind = connectionKind
        self.networkIdentifier = networkIdentifier
        self.summary = summary
        self.metricNarratives = metricNarratives
    }

    public func narrative(for metric: NetworkAssistMetricSignal) -> NetworkAssistStabilityNarrative? {
        metricNarratives.first { $0.metric == metric }?.narrative
    }
}

public protocol NetworkStabilityPatternAnalyzing: Sendable {
    /// Varre o histórico completo do usuário, agrupa por rede e devolve um
    /// relatório por grupo elegível. Nunca lança por falta de padrão — só
    /// por medição inválida (mesma semântica de `NetworkInsightsAnalyzing`).
    /// `locale` é a tag BCP-47 da preferência de idioma do app — repassada
    /// para `NetworkAssistStabilityNarrativeGenerator` para que a frase
    /// factual saia no idioma corrente em vez de sempre pt-BR.
    func analyze(_ measurements: [NetworkMeasurement], locale: String?) throws -> [NetworkStabilityPatternReport]
}

/// Implementação local e determinística (issue #125): agrupa por rede
/// (`NetworkGroupInsightsAnalyzer`), calcula estatística/tendência de cada
/// grupo elegível e varre janelas de horário (`NetworkTimeWindowPatternDetector`)
/// para as métricas citadas na issue (jitter, latência, perda de pacote),
/// traduzindo o resultado para a frase factual do Assist
/// (`NetworkAssistStabilityNarrativeGenerator`). Não é uma chamada ao NDS
/// remoto — cálculo puro sobre o histórico já existente no aparelho.
public struct BasicNetworkStabilityPatternAnalyzer: NetworkStabilityPatternAnalyzing {
    /// Métricas varridas por padrão — exatamente as três citadas na issue
    /// #125 ("jitter, latência ou perda de pacote"). Download/upload ficam
    /// de fora porque `NetworkAssistMetricSignal` não define frase para
    /// elas (ver comentário do tipo) — escopo deliberado, não esquecimento.
    public static let defaultScannedMetrics: [NetworkMetric] = [.jitterMs, .latencyMs, .packetLossPercent]

    private let groupInsightsAnalyzer: any NetworkInsightsAnalyzing
    private let groupConfiguration: NetworkGroupInsightsConfiguration
    private let patternConfiguration: NetworkTimeWindowPatternConfiguration
    private let scannedMetrics: [NetworkMetric]
    private let calendar: Calendar

    public init(
        groupInsightsAnalyzer: any NetworkInsightsAnalyzing = BasicNetworkInsightsAnalyzer(),
        groupConfiguration: NetworkGroupInsightsConfiguration = .init(),
        patternConfiguration: NetworkTimeWindowPatternConfiguration = .init(),
        scannedMetrics: [NetworkMetric] = BasicNetworkStabilityPatternAnalyzer.defaultScannedMetrics,
        calendar: Calendar = .current
    ) {
        self.groupInsightsAnalyzer = groupInsightsAnalyzer
        self.groupConfiguration = groupConfiguration
        self.patternConfiguration = patternConfiguration
        self.scannedMetrics = scannedMetrics
        self.calendar = calendar
    }

    public func analyze(_ measurements: [NetworkMeasurement], locale: String? = nil) throws -> [NetworkStabilityPatternReport] {
        let groups = NetworkGroupInsightsAnalyzer.eligibleGroups(
            measurements,
            minimumSampleCount: groupConfiguration.minimumSampleCount
        )

        return try groups.map { identity, groupMeasurements in
            let summary = try groupInsightsAnalyzer.summarize(groupMeasurements)

            let metricNarratives: [NetworkStabilityMetricNarrative] = scannedMetrics.compactMap { metric in
                guard let assistMetric = Self.assistMetricSignal(for: metric) else { return nil }
                let outcome = NetworkTimeWindowPatternDetector.detect(
                    metric: metric,
                    in: groupMeasurements,
                    configuration: patternConfiguration,
                    calendar: calendar
                )
                let assistOutcome = Self.translate(outcome, metric: assistMetric, identity: identity)
                let narrative = NetworkAssistStabilityNarrativeGenerator.makeNarrative(from: assistOutcome, locale: locale)
                return NetworkStabilityMetricNarrative(metric: assistMetric, narrative: narrative)
            }

            return NetworkStabilityPatternReport(
                connectionKind: identity.connectionKind,
                networkIdentifier: identity.networkIdentifier,
                summary: summary,
                metricNarratives: metricNarratives
            )
        }
    }

    /// Ponte entre `NetworkMetric` (`NetworkInsights`) e `NetworkAssistMetricSignal`
    /// (`NetworkAssist`) — as duas enumerações existem separadas de
    /// propósito (ver comentário de `NetworkAssistMetricSignal`); esta é a
    /// única camada que conhece as duas e faz a tradução. Métrica sem
    /// equivalente no Assist (download/upload) devolve `nil` e é ignorada
    /// pelo chamador.
    private static func assistMetricSignal(for metric: NetworkMetric) -> NetworkAssistMetricSignal? {
        switch metric {
        case .jitterMs:
            return .jitterMs
        case .latencyMs:
            return .latencyMs
        case .packetLossPercent:
            return .packetLossPercent
        case .downloadMbps, .uploadMbps, .loadedLatencyMs, .loadedLatencyUploadMs:
            return nil
        }
    }

    private static func translate(
        _ outcome: NetworkTimeWindowPatternOutcome,
        metric: NetworkAssistMetricSignal,
        identity: NetworkGroupIdentity
    ) -> NetworkAssistStabilityPatternOutcome {
        switch outcome {
        case .insufficientSamples(let distinctDayCount, let required):
            return .insufficientHistory(distinctDayCount: distinctDayCount, requiredDistinctDayCount: required)
        case .noPatternDetected:
            return .noPatternDetected
        case .detected(let pattern):
            let signal = NetworkAssistStabilityPatternSignal(
                network: NetworkAssistNetworkIdentitySignal(
                    connectionKind: identity.connectionKind,
                    networkIdentifier: identity.networkIdentifier
                ),
                metric: metric,
                startHour: pattern.startHour,
                endHour: pattern.endHour,
                distinctDayCount: pattern.distinctDayCount
            )
            return .detected(signal)
        }
    }
}

// MARK: - Gate de entitlement

/// Envolve `NetworkStabilityPatternAnalyzing` com o mesmo gate de
/// `LinkaCapability.insights` já usado por `EntitlementGatedNetworkInsightsAnalyzer`
/// (issue #125, item 4 — "assist interpreta tendências de estabilidade" é,
/// na prática, mais uma leitura de Insights sobre o histórico do usuário, não
/// uma capacidade nova; reaproveitar `.insights` evita uma capability
/// redundante na matriz Free/Plus). Lança `NetworkInsightsError.notEntitled`
/// — mesmo erro do gate de Insights, porque é a mesma capability sendo
/// checada — em vez de um erro novo só para este wrapper.
public struct EntitlementGatedNetworkStabilityPatternAnalyzer: NetworkStabilityPatternAnalyzing {
    private let analyzer: any NetworkStabilityPatternAnalyzing
    private let snapshot: LinkaEntitlementSnapshot

    public init(
        wrapping analyzer: any NetworkStabilityPatternAnalyzing,
        snapshot: LinkaEntitlementSnapshot
    ) {
        self.analyzer = analyzer
        self.snapshot = snapshot
    }

    public func analyze(_ measurements: [NetworkMeasurement], locale: String? = nil) throws -> [NetworkStabilityPatternReport] {
        let decision = LinkaEntitlementPolicy.decision(for: .insights, snapshot: snapshot)
        guard decision.isGranted else {
            throw NetworkInsightsError.notEntitled
        }
        return try analyzer.analyze(measurements, locale: locale)
    }
}
