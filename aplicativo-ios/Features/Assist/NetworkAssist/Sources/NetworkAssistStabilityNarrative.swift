import Foundation
import NetworkCore

/// Métrica considerada na narrativa de estabilidade por horário (issue
/// #125). Espelha deliberadamente um subconjunto de `NetworkInsights.NetworkMetric`
/// em vez de depender daquele pacote — mesmo padrão de
/// `NetworkAssistFailurePhaseSignal` espelhando `LinkaEngine.Phase` em
/// `NetworkAssistInvestigation.swift`: `NetworkAssist` não importa
/// `NetworkInsights`, então quem já calculou o padrão (hoje, `LinkaModules`)
/// traduz para este tipo local antes de pedir a frase. Restrito às três
/// métricas citadas explicitamente na issue #125 ("jitter, latência ou
/// perda de pacote") — download/upload não têm frase definida aqui porque o
/// dono do produto não pediu essa leitura para este recurso.
public enum NetworkAssistMetricSignal: String, Codable, Equatable, Sendable {
    case latencyMs
    case jitterMs
    case packetLossPercent
}

/// Identidade da rede citada na narrativa — apenas o que a frase precisa
/// para nomear a rede, nunca um identificador técnico interno.
public struct NetworkAssistNetworkIdentitySignal: Equatable, Sendable {
    public let connectionKind: NetworkConnectionKind
    public let networkIdentifier: String

    public init(connectionKind: NetworkConnectionKind, networkIdentifier: String) {
        self.connectionKind = connectionKind
        self.networkIdentifier = networkIdentifier
    }
}

/// Um padrão de horário já detectado e pronto para virar frase — apenas os
/// fatos que a frase cita (rede, métrica, janela, dias distintos). Nunca
/// carrega valor numérico de piora nem hipótese de causa: a frase gerada a
/// partir daqui é estritamente observacional (AGENTS.md §9 — "Não vira":
/// nenhuma causa raiz não medida, ex. "seu vizinho", "canal do roteador").
public struct NetworkAssistStabilityPatternSignal: Equatable, Sendable {
    public let network: NetworkAssistNetworkIdentitySignal
    public let metric: NetworkAssistMetricSignal
    /// Hora local de início (0–23).
    public let startHour: Int
    /// Hora local de fim (1–24, exclusiva; `24` = meia-noite).
    public let endHour: Int
    public let distinctDayCount: Int

    public init(
        network: NetworkAssistNetworkIdentitySignal,
        metric: NetworkAssistMetricSignal,
        startHour: Int,
        endHour: Int,
        distinctDayCount: Int
    ) {
        self.network = network
        self.metric = metric
        self.startHour = startHour
        self.endHour = endHour
        self.distinctDayCount = distinctDayCount
    }
}

/// Entrada do gerador de narrativa — espelha `NetworkTimeWindowPatternOutcome`
/// (`NetworkInsights`) sem depender dele, pelo mesmo motivo de
/// `NetworkAssistStabilityPatternSignal` acima.
public enum NetworkAssistStabilityPatternOutcome: Equatable, Sendable {
    case detected(NetworkAssistStabilityPatternSignal)
    case noPatternDetected
    case insufficientHistory(distinctDayCount: Int, requiredDistinctDayCount: Int)
}

/// Saída do gerador — três estados explícitos, nunca uma frase vazia nem
/// uma frase genérica fabricada quando não há padrão ou dado insuficiente
/// (requisito explícito da issue #125, item 3).
public enum NetworkAssistStabilityNarrative: Equatable, Sendable {
    /// Frase curta em PT-BR citando só fatos medidos.
    case factual(String)
    case noPatternDetected
    case insufficientHistory(distinctDayCount: Int, requiredDistinctDayCount: Int)
}

/// Gera a frase factual do Assist a partir de um padrão de estabilidade por
/// horário já detectado (issue #125, item 3). Determinístico e sem I/O —
/// texto puro a partir de dado tipado, mesmo padrão de separação
/// cálculo/apresentação do resto do pacote (`NetworkAssistInvestigationEngine`
/// nunca gera texto; a UI/camada de composição gera).
public enum NetworkAssistStabilityNarrativeGenerator {
    /// `locale` é a tag BCP-47 da preferência de idioma do app (mesma
    /// origem de `NetworkAssistRequest.locale`), nunca `Locale.current` —
    /// mesmo critério do resto do pacote (`NetworkAssistActionSuggestion`
    /// não gera copy; quando este tipo gera, segue a preferência manual do
    /// app, não o idioma do sistema).
    public static func makeNarrative(
        from outcome: NetworkAssistStabilityPatternOutcome,
        locale: String? = nil
    ) -> NetworkAssistStabilityNarrative {
        switch outcome {
        case .insufficientHistory(let distinctDayCount, let required):
            return .insufficientHistory(distinctDayCount: distinctDayCount, requiredDistinctDayCount: required)
        case .noPatternDetected:
            return .noPatternDetected
        case .detected(let signal):
            return .factual(phrase(for: signal, locale: locale))
        }
    }

    private static func phrase(for signal: NetworkAssistStabilityPatternSignal, locale: String?) -> String {
        let networkLabel = networkLabel(for: signal.network, locale: locale)
        let metricLabel = metricLabel(for: signal.metric, locale: locale)
        let startLabel = hourLabel(signal.startHour, locale: locale)
        let endLabel = hourLabel(signal.endHour == 24 ? 0 : signal.endHour, locale: locale)

        switch (locale ?? "pt-BR").lowercased() {
        case let tag where tag.hasPrefix("es"):
            return "\(networkLabel) \(metricLabel) todos los días entre \(startLabel) y \(endLabel)."
        case let tag where tag.hasPrefix("en"):
            return "\(networkLabel) \(metricLabel) every day between \(startLabel) and \(endLabel)."
        default:
            return "\(networkLabel) \(metricLabel) todos os dias entre \(startLabel) e \(endLabel)."
        }
    }

    private static func networkLabel(for network: NetworkAssistNetworkIdentitySignal, locale: String?) -> String {
        switch (locale ?? "pt-BR").lowercased() {
        case let tag where tag.hasPrefix("es"):
            switch network.connectionKind {
            case .wifi:
                return "Tu red Wi-Fi \(network.networkIdentifier)"
            case .cellular:
                return "Tu operadora \(network.networkIdentifier)"
            case .ethernet, .other:
                return "Tu red \(network.networkIdentifier)"
            }
        case let tag where tag.hasPrefix("en"):
            switch network.connectionKind {
            case .wifi:
                return "Your Wi-Fi network \(network.networkIdentifier)"
            case .cellular:
                return "Your carrier \(network.networkIdentifier)"
            case .ethernet, .other:
                return "Your network \(network.networkIdentifier)"
            }
        default:
            switch network.connectionKind {
            case .wifi:
                return "Sua rede Wi-Fi \(network.networkIdentifier)"
            case .cellular:
                return "Sua operadora \(network.networkIdentifier)"
            case .ethernet, .other:
                return "Sua rede \(network.networkIdentifier)"
            }
        }
    }

    private static func metricLabel(for metric: NetworkAssistMetricSignal, locale: String?) -> String {
        switch (locale ?? "pt-BR").lowercased() {
        case let tag where tag.hasPrefix("es"):
            switch metric {
            case .jitterMs:
                return "sufre picos de inestabilidad (jitter alto)"
            case .latencyMs:
                return "sufre picos de latencia alta"
            case .packetLossPercent:
                return "pierde paquetes con frecuencia"
            }
        case let tag where tag.hasPrefix("en"):
            switch metric {
            case .jitterMs:
                return "has spikes of instability (high jitter)"
            case .latencyMs:
                return "has spikes of high latency"
            case .packetLossPercent:
                return "loses packets frequently"
            }
        default:
            switch metric {
            case .jitterMs:
                return "sofre picos de instabilidade (jitter alto)"
            case .latencyMs:
                return "sofre picos de latência alta"
            case .packetLossPercent:
                return "perde pacotes com frequência"
            }
        }
    }

    private static func hourLabel(_ hour: Int, locale: String?) -> String {
        let tag = (locale ?? "pt-BR").lowercased()
        if tag.hasPrefix("es") || tag.hasPrefix("en") {
            return "\(hour):00"
        }
        return "\(hour)h"
    }
}
