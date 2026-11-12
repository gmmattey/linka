import Foundation
import NetworkCore

/// Identidade de uma "rede" para fins de agrupamento de histórico (issue
/// #125). Combina `connectionKind` + `networkIdentifier` deliberadamente —
/// duas medições no mesmo Wi-Fi "Casa" antes e depois de o roteador cair
/// para 4G, por exemplo, não devem virar o mesmo grupo só porque alguém
/// nomeou a rede celular igual ao SSID por coincidência. Tratar Wi-Fi e
/// celular como identidades sempre distintas, mesmo com `networkIdentifier`
/// igual, evita esse cruzamento espúrio sem custo real (a coincidência de
/// nome entre SSID e operadora é rara e, quando acontece, confundir os dois
/// seria pior que separá-los).
public struct NetworkGroupIdentity: Hashable, Codable, Sendable {
    public let connectionKind: NetworkConnectionKind
    public let networkIdentifier: String

    public init(connectionKind: NetworkConnectionKind, networkIdentifier: String) {
        self.connectionKind = connectionKind
        self.networkIdentifier = networkIdentifier
    }
}

extension NetworkGroupIdentity: Comparable {
    /// Ordenação determinística (por tipo de conexão, depois nome) — usada
    /// só para tornar a saída de `NetworkGroupInsightsAnalyzer` estável e
    /// fácil de testar, sem implicar prioridade de produto entre redes.
    public static func < (lhs: NetworkGroupIdentity, rhs: NetworkGroupIdentity) -> Bool {
        if lhs.connectionKind != rhs.connectionKind {
            return lhs.connectionKind.rawValue < rhs.connectionKind.rawValue
        }
        return lhs.networkIdentifier < rhs.networkIdentifier
    }
}

/// Estatísticas/tendência (via `BasicNetworkInsightsAnalyzer`) de um grupo de
/// rede específico.
public struct NetworkGroupSummary: Equatable, Sendable {
    public let identity: NetworkGroupIdentity
    public let summary: NetworkInsightsSummary

    public init(identity: NetworkGroupIdentity, summary: NetworkInsightsSummary) {
        self.identity = identity
        self.summary = summary
    }
}

public struct NetworkGroupInsightsConfiguration: Equatable, Sendable {
    /// Amostras mínimas dentro de um grupo para que ele entre no resultado.
    /// Abaixo disso, estatística e tendência por rede viram ruído — mesmo
    /// espírito de `NetworkInsightsConfiguration.minimumTrendSamples`, mas
    /// aplicado à elegibilidade do grupo inteiro, não só à tendência.
    public let minimumSampleCount: Int

    public init(minimumSampleCount: Int = 5) {
        self.minimumSampleCount = max(1, minimumSampleCount)
    }
}

public protocol NetworkGroupInsightsAnalyzing: Sendable {
    func summarizeByNetwork(_ measurements: [NetworkMeasurement]) throws -> [NetworkGroupSummary]
}

/// Agrupa um histórico de `NetworkMeasurement` por identidade de rede e
/// reaproveita `NetworkInsightsAnalyzing` (por padrão `BasicNetworkInsightsAnalyzer`)
/// para calcular estatística/tendência de cada grupo elegível (issue #125,
/// item 1) — não reimplementa a matemática de `NetworkInsights.swift`.
public struct NetworkGroupInsightsAnalyzer: NetworkGroupInsightsAnalyzing {
    public let analyzer: any NetworkInsightsAnalyzing
    public let configuration: NetworkGroupInsightsConfiguration

    public init(
        analyzer: any NetworkInsightsAnalyzing = BasicNetworkInsightsAnalyzer(),
        configuration: NetworkGroupInsightsConfiguration = .init()
    ) {
        self.analyzer = analyzer
        self.configuration = configuration
    }

    public func summarizeByNetwork(_ measurements: [NetworkMeasurement]) throws -> [NetworkGroupSummary] {
        try Self.eligibleGroups(measurements, minimumSampleCount: configuration.minimumSampleCount)
            .map { identity, groupMeasurements in
                NetworkGroupSummary(
                    identity: identity,
                    summary: try analyzer.summarize(groupMeasurements)
                )
            }
    }

    /// Agrupa por `NetworkGroupIdentity`. Medições sem `connectionKind` ou
    /// sem identidade (SSID para Wi-Fi novo; `networkIdentifier` para os
    /// demais e registros legados) ficam de fora: sem os dois
    /// fatos não há como nomear a rede numa frase factual depois (issue
    /// #125, item 3) nem como garantir que o grupo é realmente uma única
    /// rede — em vez de inventar um rótulo tipo "desconhecida", a medição
    /// simplesmente não participa de nenhum grupo.
    public static func group(_ measurements: [NetworkMeasurement]) -> [NetworkGroupIdentity: [NetworkMeasurement]] {
        Dictionary(grouping: measurements.filter { measurement in
            guard measurement.connectionKind != nil else { return false }
            guard let identifier = Self.identifier(for: measurement),
                  !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return true
        }) { measurement in
            NetworkGroupIdentity(
                connectionKind: measurement.connectionKind!,
                networkIdentifier: Self.identifier(for: measurement)!
            )
        }
    }

    private static func identifier(for measurement: NetworkMeasurement) -> String? {
        if measurement.connectionKind == .wifi {
            return measurement.wifiContext?.ssid ?? measurement.networkIdentifier
        }
        return measurement.networkIdentifier
    }

    /// `group(_:)` filtrado por amostra mínima e ordenado de forma
    /// determinística — usado tanto por `summarizeByNetwork` quanto por
    /// consumidores externos (ex.: detecção de padrão por horário em
    /// `LinkaModules`) que precisam da mesma noção de "grupo elegível" sem
    /// duplicar o critério de corte.
    public static func eligibleGroups(
        _ measurements: [NetworkMeasurement],
        minimumSampleCount: Int
    ) -> [(identity: NetworkGroupIdentity, measurements: [NetworkMeasurement])] {
        group(measurements)
            .filter { $0.value.count >= minimumSampleCount }
            .map { (identity: $0.key, measurements: $0.value) }
            .sorted { $0.identity < $1.identity }
    }
}
