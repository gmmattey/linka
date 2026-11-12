import Foundation
import NetworkCore
import NetworkInsights

/// Regras puras para transformar medições reais em oportunidades assistidas.
/// Não conhece UI, assinatura, rede ativa ou configurações do sistema.
public enum OptimizationOpportunityKind: String, Codable, CaseIterable, Sendable {
    case responsivenessUnderLoad
    case unstableConnection
    case belowUsualQuality
}

public enum OptimizationGuidedAction: String, Codable, CaseIterable, Sendable {
    case reduceConcurrentUse
    case moveCloserToRouter
    case restartRouter
}

public struct OptimizationOpportunity: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let ruleVersion: Int
    public let kind: OptimizationOpportunityKind
    public let action: OptimizationGuidedAction
    public let evidenceMeasurementIDs: [UUID]
    public let confidence: Double

    public init(
        id: String,
        ruleVersion: Int = 1,
        kind: OptimizationOpportunityKind,
        action: OptimizationGuidedAction,
        evidenceMeasurementIDs: [UUID],
        confidence: Double
    ) {
        self.id = id
        self.ruleVersion = ruleVersion
        self.kind = kind
        self.action = action
        self.evidenceMeasurementIDs = evidenceMeasurementIDs
        self.confidence = min(1, max(0, confidence))
    }
}

public struct OptimizationPlan: Codable, Equatable, Sendable {
    public let baselineMeasurementID: UUID
    public let opportunities: [OptimizationOpportunity]

    public init(baselineMeasurementID: UUID, opportunities: [OptimizationOpportunity]) {
        self.baselineMeasurementID = baselineMeasurementID
        self.opportunities = Array(opportunities.prefix(3))
    }
}

public struct OptimizationPlanBuilder: Sendable {
    public let minimumHistorySamples: Int
    public let highJitterMs: Double
    public let meaningfulLossPercent: Double

    public init(
        minimumHistorySamples: Int = 3,
        highJitterMs: Double = 15,
        meaningfulLossPercent: Double = 2
    ) {
        self.minimumHistorySamples = max(2, minimumHistorySamples)
        self.highJitterMs = max(0, highJitterMs)
        self.meaningfulLossPercent = max(0, meaningfulLossPercent)
    }

    public func build(baseline: NetworkMeasurement, history: [NetworkMeasurement]) -> OptimizationPlan {
        var opportunities: [OptimizationOpportunity] = []

        let responsiveness = LoadResponsivenessEvaluator.evaluateForConsumer(baseline)
        if responsiveness.category == .medium || responsiveness.category == .low {
            opportunities.append(OptimizationOpportunity(
                id: "responsiveness-under-load-v1",
                kind: .responsivenessUnderLoad,
                action: .reduceConcurrentUse,
                evidenceMeasurementIDs: [baseline.id],
                confidence: responsiveness.category == .low ? 0.9 : 0.7
            ))
        }

        let hasInstability = (baseline.jitterMs ?? 0) >= highJitterMs ||
            (baseline.packetLossPercent ?? 0) >= meaningfulLossPercent
        if hasInstability {
            opportunities.append(OptimizationOpportunity(
                id: "unstable-connection-v1",
                kind: .unstableConnection,
                action: baseline.connectionKind == .wifi ? .moveCloserToRouter : .reduceConcurrentUse,
                evidenceMeasurementIDs: [baseline.id],
                confidence: baseline.packetLossPercent.map { $0 >= meaningfulLossPercent } == true ? 0.85 : 0.65
            ))
        }

        if let historicalIDs = degradedHistoryEvidence(for: baseline, in: history) {
            opportunities.append(OptimizationOpportunity(
                id: "below-usual-quality-v1",
                kind: .belowUsualQuality,
                action: hasHomeRouter(baseline.connectionKind) ? .restartRouter : .reduceConcurrentUse,
                evidenceMeasurementIDs: [baseline.id] + historicalIDs,
                confidence: 0.75
            ))
        }

        let ordered = opportunities.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.id < $1.id
        }
        return OptimizationPlan(baselineMeasurementID: baseline.id, opportunities: ordered)
    }

    /// `restartRouter` só é necessária e possível quando a conexão realmente
    /// passa por um roteador doméstico que a pessoa pode reiniciar — Wi-Fi ou
    /// Ethernet. Numa conexão celular não existe roteador nenhum envolvido, e
    /// `.other`/ausência de tipo é caso desconhecido demais para presumir essa
    /// topologia. `moveCloserToRouter` é ainda mais restrita (só `.wifi`
    /// acima, direto no call site): "se aproximar" só faz sentido pra sinal
    /// sem fio — não existe "se aproximar" de um cabo Ethernet já conectado.
    /// Quando a ação de roteador não se aplica, cai para `reduceConcurrentUse`
    /// — a única ação deste conjunto que continua válida independente do tipo
    /// de rede — mesma disciplina de `NetworkAssistActionEngine` (nunca
    /// sugere uma ação sem evidência mínima de que ela se aplica).
    private func hasHomeRouter(_ connectionKind: NetworkConnectionKind?) -> Bool {
        connectionKind == .wifi || connectionKind == .ethernet
    }

    private func degradedHistoryEvidence(
        for baseline: NetworkMeasurement,
        in history: [NetworkMeasurement]
    ) -> [UUID]? {
        guard let kind = baseline.connectionKind,
              let identity = networkIdentity(for: baseline),
              let currentLatency = baseline.latencyMs else { return nil }

        let comparable = history.filter {
            $0.id != baseline.id && $0.connectionKind == kind && networkIdentity(for: $0) == identity
        }
        let latencies = comparable.compactMap(\.latencyMs).sorted()
        guard latencies.count >= minimumHistorySamples else { return nil }
        let median = latencies[latencies.count / 2]
        let comparison = MetricComparator.compare(
            metric: .latencyMs,
            current: currentLatency,
            baseline: median,
            stableChangeThresholdPercent: NetworkInsightsConfiguration().stableChangeThresholdPercent
        )
        guard comparison.direction == .worsened else { return nil }
        return comparable.map(\.id).sorted { $0.uuidString < $1.uuidString }
    }

    private func networkIdentity(for measurement: NetworkMeasurement) -> String? {
        if measurement.connectionKind == .wifi {
            return measurement.wifiContext?.ssid
        }
        return measurement.networkIdentifier
    }
}

public enum OptimizationRetestComparison: Equatable, Sendable {
    case notComparable
    case noSignificantGain
    case improved([MetricComparison])
}

public enum OptimizationRetestComparator {
    public static func compare(
        baseline: NetworkMeasurement,
        retest: NetworkMeasurement,
        analyzer: any NetworkInsightsAnalyzing = BasicNetworkInsightsAnalyzer()
    ) -> OptimizationRetestComparison {
        guard baseline.outcome == .complete,
              retest.outcome == .complete,
              baseline.connectionKind == retest.connectionKind,
              sameNetworkWhenWiFi(baseline, retest),
              let comparison = try? analyzer.compare(current: retest, against: baseline) else {
            return .notComparable
        }
        let improvements = comparison.metrics.filter { $0.direction == .improved }
        return improvements.isEmpty ? .noSignificantGain : .improved(improvements)
    }

    private static func sameNetworkWhenWiFi(_ baseline: NetworkMeasurement, _ retest: NetworkMeasurement) -> Bool {
        guard baseline.connectionKind == .wifi else { return true }
        guard let first = baseline.wifiContext?.ssid, let second = retest.wifiContext?.ssid else { return false }
        return first == second
    }
}

// MARK: - Baseline local por perfil

/// Referência estatística local de uma rede identificada pelo consumidor.
///
/// A identidade é propositalmente opaca para este pacote: a futura camada de
/// perfis fornece seu fingerprint versionado, e esta estrutura nunca precisa
/// conhecer SSID, BSSID/MAC ou a forma como esse fingerprint foi produzido.
/// As métricas continuam opcionais porque uma amostra elegível pode não ter
/// concluído cada sonda; ausência nunca é transformada em zero.
public struct NetworkBaseline: Equatable, Sendable {
    public let profileIdentity: String
    public let sampleCount: Int
    public let measuredFrom: Date
    public let measuredUntil: Date
    public let measurementIDs: [UUID]
    public let downloadMbps: Double?
    public let uploadMbps: Double?
    public let latencyMs: Double?
    public let jitterMs: Double?
    public let packetLossPercent: Double?

    public init(
        profileIdentity: String,
        sampleCount: Int,
        measuredFrom: Date,
        measuredUntil: Date,
        measurementIDs: [UUID],
        downloadMbps: Double?,
        uploadMbps: Double?,
        latencyMs: Double?,
        jitterMs: Double?,
        packetLossPercent: Double?
    ) {
        self.profileIdentity = profileIdentity
        self.sampleCount = sampleCount
        self.measuredFrom = measuredFrom
        self.measuredUntil = measuredUntil
        self.measurementIDs = measurementIDs
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.latencyMs = latencyMs
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
    }
}

/// Calcula a referência de qualidade de um perfil local a partir do histórico
/// já disponível no dispositivo. Não persiste, não busca histórico e não
/// deriva identidade de `networkIdentifier`, que identifica o provedor/servidor
/// do teste e não a rede Wi-Fi local.
public struct NetworkBaselineBuilder: Sendable {
    public typealias MeasurementIdentity = @Sendable (NetworkMeasurement) -> String?

    public let minimumSampleCount: Int
    public let window: TimeInterval
    private let identityForMeasurement: MeasurementIdentity

    public init(
        minimumSampleCount: Int = 3,
        window: TimeInterval = 30 * 24 * 60 * 60,
        identityForMeasurement: @escaping MeasurementIdentity
    ) {
        self.minimumSampleCount = max(3, minimumSampleCount)
        self.window = max(0, window)
        self.identityForMeasurement = identityForMeasurement
    }

    /// Retorna `nil` até haver a quantidade mínima de medições completas,
    /// Wi-Fi, recentes e pertencentes à identidade confirmada do perfil.
    public func build(
        profileIdentity: String,
        measurements: [NetworkMeasurement],
        referenceDate: Date = Date()
    ) -> NetworkBaseline? {
        guard !profileIdentity.isEmpty else { return nil }

        let earliestDate = referenceDate.addingTimeInterval(-window)
        let eligible = measurements.filter { measurement in
            measurement.outcome == .complete
                && measurement.connectionKind == .wifi
                && measurement.measuredAt >= earliestDate
                && measurement.measuredAt <= referenceDate
                && identityForMeasurement(measurement) == profileIdentity
        }

        guard eligible.count >= minimumSampleCount,
              let measuredFrom = eligible.map(\.measuredAt).min(),
              let measuredUntil = eligible.map(\.measuredAt).max() else {
            return nil
        }

        return NetworkBaseline(
            profileIdentity: profileIdentity,
            sampleCount: eligible.count,
            measuredFrom: measuredFrom,
            measuredUntil: measuredUntil,
            measurementIDs: eligible.map(\.id).sorted { $0.uuidString < $1.uuidString },
            downloadMbps: Self.median(eligible.compactMap(\.downloadMbps)),
            uploadMbps: Self.median(eligible.compactMap(\.uploadMbps)),
            latencyMs: Self.median(eligible.compactMap(\.latencyMs)),
            jitterMs: Self.median(eligible.compactMap(\.jitterMs)),
            packetLossPercent: Self.median(eligible.compactMap(\.packetLossPercent))
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

/// Resultado factual da comparação entre uma leitura atual e a referência
/// estatística de um perfil. Uma direção descreve somente a diferença medida;
/// ela não atribui essa diferença a qualquer orientação ou alteração feita
/// pela pessoa.
public struct NetworkBaselineComparison: Equatable, Sendable {
    public let currentMeasurementID: UUID
    public let profileIdentity: String
    public let metrics: [MetricComparison]

    public init(
        currentMeasurementID: UUID,
        profileIdentity: String,
        metrics: [MetricComparison]
    ) {
        self.currentMeasurementID = currentMeasurementID
        self.profileIdentity = profileIdentity
        self.metrics = metrics
    }

    public func comparison(for metric: NetworkMetric) -> MetricComparison? {
        metrics.first { $0.metric == metric }
    }
}

/// Mantém a distinção entre uma métrica ausente (comparação disponível, com
/// `.unavailable` naquela linha) e uma leitura inteira incompatível com a
/// referência da rede (não há comparação honesta a mostrar).
public enum NetworkBaselineComparisonResult: Equatable, Sendable {
    case compared(NetworkBaselineComparison)
    case incompatible
}

/// Compara uma medição atual com uma `NetworkBaseline` já formada. Recebe a
/// mesma identidade opaca usada na formação da baseline para não acoplar este
/// pacote ao futuro armazenamento de perfis ou ao formato do fingerprint.
public struct NetworkBaselineComparator: Sendable {
    private let identityForMeasurement: NetworkBaselineBuilder.MeasurementIdentity
    public let stableChangeThresholdPercent: Double

    public init(
        stableChangeThresholdPercent: Double = NetworkInsightsConfiguration().stableChangeThresholdPercent,
        identityForMeasurement: @escaping NetworkBaselineBuilder.MeasurementIdentity
    ) {
        self.stableChangeThresholdPercent = max(0, stableChangeThresholdPercent)
        self.identityForMeasurement = identityForMeasurement
    }

    public func compare(
        current: NetworkMeasurement,
        against baseline: NetworkBaseline
    ) -> NetworkBaselineComparisonResult {
        guard current.outcome == .complete,
              current.connectionKind == .wifi,
              baseline.sampleCount >= 3,
              !baseline.profileIdentity.isEmpty,
              identityForMeasurement(current) == baseline.profileIdentity else {
            return .incompatible
        }

        let metrics: [MetricComparison] = [
            compare(.downloadMbps, current.downloadMbps, baseline.downloadMbps),
            compare(.uploadMbps, current.uploadMbps, baseline.uploadMbps),
            compare(.latencyMs, current.latencyMs, baseline.latencyMs),
            compare(.jitterMs, current.jitterMs, baseline.jitterMs),
            compare(.packetLossPercent, current.packetLossPercent, baseline.packetLossPercent)
        ]

        return .compared(NetworkBaselineComparison(
            currentMeasurementID: current.id,
            profileIdentity: baseline.profileIdentity,
            metrics: metrics
        ))
    }

    private func compare(
        _ metric: NetworkMetric,
        _ current: Double?,
        _ baseline: Double?
    ) -> MetricComparison {
        MetricComparator.compare(
            metric: metric,
            current: current,
            baseline: baseline,
            stableChangeThresholdPercent: stableChangeThresholdPercent
        )
    }
}
