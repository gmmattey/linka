import Foundation
import NetworkCore

/// Etapa do modelo diagnóstico "Caminho da Conexão". Não representa saltos
/// reais de rede (o Linka não faz traceroute) — é um agrupamento didático
/// das medições que o motor já faz, pensado para responder "onde
/// provavelmente está o problema" em linguagem comum.
public enum ConnectionPathStage: String, Codable, CaseIterable, Equatable, Sendable {
    case device
    case wifi
    case router
    case carrier
    case internet
}

/// Estado visual de uma etapa. `.unavailable` não é "ruim" — é "não sabemos
/// medir isso agora" (ex.: sem diagnóstico Wi-Fi avançado, sem histórico).
/// Uma etapa nunca vira `.normal` só pela ausência de evidência de problema
/// (AGENTS.md §8/§9): falta de dado é `.unavailable`, não "tudo bem".
public enum ConnectionPathStageStatus: String, Codable, Equatable, Sendable {
    case normal
    case attention
    case likelyProblem
    case unavailable
}

/// Fato que sustenta o veredito de uma etapa — usado pela UI para escolher
/// a explicação certa sem duplicar limiares/regras (mesmo padrão de
/// `NetworkMetric`/`UsageCaseVerdict.limitingMetric`).
public enum ConnectionPathFact: String, Codable, Equatable, Sendable {
    case wifiSignal
    case routerJitter
    case routerLoadedLatency
    case carrierLatency
    case carrierPacketLoss
    case internetDownload
    case internetDns
}

public struct ConnectionPathStageVerdict: Codable, Equatable, Sendable {
    public let stage: ConnectionPathStage
    public let status: ConnectionPathStageStatus
    public let limitingFact: ConnectionPathFact?

    public init(stage: ConnectionPathStage, status: ConnectionPathStageStatus, limitingFact: ConnectionPathFact?) {
        self.stage = stage
        self.status = status
        self.limitingFact = limitingFact
    }
}

/// Categoria de responsável provável — as quatro situações do modelo
/// diagnóstico, mais dois estados sem responsável único: `.healthy` (nada
/// fora do esperado) e `.inconclusive` (mais de uma etapa igualmente
/// suspeita, sem uma causa dominante clara).
public enum ConnectionPathCategory: String, Codable, Equatable, Sendable {
    case local
    case wifi
    case carrier
    case external
    case healthy
    case inconclusive
}

public struct ConnectionPathReport: Codable, Equatable, Sendable {
    public let stages: [ConnectionPathStageVerdict]
    public let category: ConnectionPathCategory
    /// Etapa a destacar visualmente quando há um único responsável claro.
    /// `nil` quando `.healthy` (nada a destacar) ou `.inconclusive` (mais
    /// de uma etapa suspeita, destacar uma só seria enganoso).
    public let highlightedStage: ConnectionPathStage?

    public init(stages: [ConnectionPathStageVerdict], category: ConnectionPathCategory, highlightedStage: ConnectionPathStage?) {
        self.stages = stages
        self.category = category
        self.highlightedStage = highlightedStage
    }

    public func verdict(for stage: ConnectionPathStage) -> ConnectionPathStageVerdict? {
        stages.first { $0.stage == stage }
    }
}

/// Limiares do modelo diagnóstico. Números de partida razoáveis, não
/// validados por medição de campo como os de `UsageSuitabilityThresholds`
/// — ajustáveis sem mexer na lógica de classificação.
public struct ConnectionPathThresholds: Equatable, Sendable {
    public var wifiRssiAttentionDbm: Double
    public var wifiRssiProblemDbm: Double

    public var routerJitterAttentionMs: Double
    public var routerJitterProblemMs: Double
    public var routerLoadedLatencyDeltaAttentionMs: Double
    public var routerLoadedLatencyDeltaProblemMs: Double

    public var carrierLatencyAttentionMs: Double
    public var carrierLatencyProblemMs: Double
    public var carrierPacketLossAttentionPercent: Double
    public var carrierPacketLossProblemPercent: Double

    public var internetDownloadAttentionMbps: Double
    public var internetDownloadProblemMbps: Double
    public var internetDnsAttentionMs: Double
    public var internetDnsProblemMs: Double

    public init(
        wifiRssiAttentionDbm: Double = -70,
        wifiRssiProblemDbm: Double = -80,
        routerJitterAttentionMs: Double = 30,
        routerJitterProblemMs: Double = 60,
        routerLoadedLatencyDeltaAttentionMs: Double = 50,
        routerLoadedLatencyDeltaProblemMs: Double = 150,
        carrierLatencyAttentionMs: Double = 80,
        carrierLatencyProblemMs: Double = 150,
        carrierPacketLossAttentionPercent: Double = 1,
        carrierPacketLossProblemPercent: Double = 5,
        internetDownloadAttentionMbps: Double = 10,
        internetDownloadProblemMbps: Double = 3,
        internetDnsAttentionMs: Double = 150,
        internetDnsProblemMs: Double = 400
    ) {
        self.wifiRssiAttentionDbm = wifiRssiAttentionDbm
        self.wifiRssiProblemDbm = wifiRssiProblemDbm
        self.routerJitterAttentionMs = routerJitterAttentionMs
        self.routerJitterProblemMs = routerJitterProblemMs
        self.routerLoadedLatencyDeltaAttentionMs = routerLoadedLatencyDeltaAttentionMs
        self.routerLoadedLatencyDeltaProblemMs = routerLoadedLatencyDeltaProblemMs
        self.carrierLatencyAttentionMs = carrierLatencyAttentionMs
        self.carrierLatencyProblemMs = carrierLatencyProblemMs
        self.carrierPacketLossAttentionPercent = carrierPacketLossAttentionPercent
        self.carrierPacketLossProblemPercent = carrierPacketLossProblemPercent
        self.internetDownloadAttentionMbps = internetDownloadAttentionMbps
        self.internetDownloadProblemMbps = internetDownloadProblemMbps
        self.internetDnsAttentionMs = internetDnsAttentionMs
        self.internetDnsProblemMs = internetDnsProblemMs
    }
}

public protocol ConnectionPathEvaluating: Sendable {
    func evaluate(_ measurement: NetworkMeasurement) -> ConnectionPathReport
}

/// Classificação pura e testável de uma `NetworkMeasurement` no modelo
/// "Caminho da Conexão" (iPhone → Wi-Fi → Roteador → Operadora →
/// Internet). Não conhece copy de produto, não sabe nada de traceroute
/// real — agrupa sinais que o motor já mede em cinco etapas didáticas.
/// Nil-safe: métrica ausente vira `.unavailable`, nunca um veredito
/// inventado (AGENTS.md §8/§9, mesmo espírito de `UsageSuitabilityEvaluator`).
public struct ConnectionPathEvaluator: ConnectionPathEvaluating {
    public let thresholds: ConnectionPathThresholds

    public init(thresholds: ConnectionPathThresholds = .init()) {
        self.thresholds = thresholds
    }

    public func evaluate(_ measurement: NetworkMeasurement) -> ConnectionPathReport {
        var stages: [ConnectionPathStageVerdict] = []
        stages.append(evaluateDevice(measurement))
        
        if measurement.connectionKind != .cellular {
            stages.append(evaluateWiFi(measurement))
            stages.append(evaluateRouter(measurement))
        }
        
        stages.append(evaluateCarrier(measurement))
        stages.append(evaluateInternet(measurement))
        
        let (category, highlighted) = Self.deriveCategory(stages)
        return ConnectionPathReport(stages: stages, category: category, highlightedStage: highlighted)
    }

    // MARK: - iPhone

    /// O Linka não audita o aparelho (CPU, memória, etc.) — só sabe que o
    /// teste rodou até produzir este relatório, o que já é evidência de
    /// que o dispositivo está funcionalmente conectado. Não há hoje um
    /// sinal que rebaixe esta etapa para `.attention`/`.likelyProblem`.
    private func evaluateDevice(_ measurement: NetworkMeasurement) -> ConnectionPathStageVerdict {
        ConnectionPathStageVerdict(stage: .device, status: .normal, limitingFact: nil)
    }

    // MARK: - Wi-Fi

    private func evaluateWiFi(_ measurement: NetworkMeasurement) -> ConnectionPathStageVerdict {
        guard measurement.connectionKind == .wifi else {
            return ConnectionPathStageVerdict(stage: .wifi, status: .unavailable, limitingFact: nil)
        }
        guard let rssi = measurement.advancedWiFiDiagnostics?.rssiDbm else {
            return ConnectionPathStageVerdict(stage: .wifi, status: .unavailable, limitingFact: nil)
        }
        if rssi <= thresholds.wifiRssiProblemDbm {
            return ConnectionPathStageVerdict(stage: .wifi, status: .likelyProblem, limitingFact: .wifiSignal)
        }
        if rssi <= thresholds.wifiRssiAttentionDbm {
            return ConnectionPathStageVerdict(stage: .wifi, status: .attention, limitingFact: .wifiSignal)
        }
        return ConnectionPathStageVerdict(stage: .wifi, status: .normal, limitingFact: nil)
    }

    // MARK: - Roteador

    /// O Linka não sonda o gateway diretamente — usa dois sinais indiretos
    /// já medidos: jitter (ruído na resposta) e o quanto a latência piora
    /// sob carga em relação ao ping parado (fila cheia no roteador /
    /// bufferbloat). O pior dos dois decide o veredito.
    private func evaluateRouter(_ measurement: NetworkMeasurement) -> ConnectionPathStageVerdict {
        guard measurement.connectionKind == .wifi else {
            return ConnectionPathStageVerdict(stage: .router, status: .unavailable, limitingFact: nil)
        }

        var status: ConnectionPathStageStatus = .normal
        var fact: ConnectionPathFact?
        var hasAnySignal = false

        if let jitter = measurement.jitterMs {
            hasAnySignal = true
            if jitter >= thresholds.routerJitterProblemMs {
                status = .likelyProblem
                fact = .routerJitter
            } else if jitter >= thresholds.routerJitterAttentionMs, status != .likelyProblem {
                status = .attention
                fact = .routerJitter
            }
        }

        let trustedLoadedLatency = measurement.trustedLoadedLatencies.downloadMs
        if let loaded = trustedLoadedLatency, let idle = measurement.latencyMs {
            hasAnySignal = true
            let delta = loaded - idle
            if delta >= thresholds.routerLoadedLatencyDeltaProblemMs {
                status = .likelyProblem
                fact = .routerLoadedLatency
            } else if delta >= thresholds.routerLoadedLatencyDeltaAttentionMs, status != .likelyProblem {
                status = .attention
                fact = .routerLoadedLatency
            }
        }

        guard hasAnySignal else {
            return ConnectionPathStageVerdict(stage: .router, status: .unavailable, limitingFact: nil)
        }
        return ConnectionPathStageVerdict(stage: .router, status: status, limitingFact: fact)
    }

    // MARK: - Operadora

    private func evaluateCarrier(_ measurement: NetworkMeasurement) -> ConnectionPathStageVerdict {
        guard let latency = measurement.latencyMs else {
            return ConnectionPathStageVerdict(stage: .carrier, status: .unavailable, limitingFact: nil)
        }

        if let loss = measurement.packetLossPercent, loss >= thresholds.carrierPacketLossProblemPercent {
            return ConnectionPathStageVerdict(stage: .carrier, status: .likelyProblem, limitingFact: .carrierPacketLoss)
        }
        if latency >= thresholds.carrierLatencyProblemMs {
            return ConnectionPathStageVerdict(stage: .carrier, status: .likelyProblem, limitingFact: .carrierLatency)
        }
        if let loss = measurement.packetLossPercent, loss >= thresholds.carrierPacketLossAttentionPercent {
            return ConnectionPathStageVerdict(stage: .carrier, status: .attention, limitingFact: .carrierPacketLoss)
        }
        if latency >= thresholds.carrierLatencyAttentionMs {
            return ConnectionPathStageVerdict(stage: .carrier, status: .attention, limitingFact: .carrierLatency)
        }
        return ConnectionPathStageVerdict(stage: .carrier, status: .normal, limitingFact: nil)
    }

    // MARK: - Internet

    private func evaluateInternet(_ measurement: NetworkMeasurement) -> ConnectionPathStageVerdict {
        guard let download = measurement.downloadMbps else {
            return ConnectionPathStageVerdict(stage: .internet, status: .unavailable, limitingFact: nil)
        }

        if download <= thresholds.internetDownloadProblemMbps {
            return ConnectionPathStageVerdict(stage: .internet, status: .likelyProblem, limitingFact: .internetDownload)
        }
        if let dns = measurement.dnsResolutionMs, dns >= thresholds.internetDnsProblemMs {
            return ConnectionPathStageVerdict(stage: .internet, status: .likelyProblem, limitingFact: .internetDns)
        }
        if download <= thresholds.internetDownloadAttentionMbps {
            return ConnectionPathStageVerdict(stage: .internet, status: .attention, limitingFact: .internetDownload)
        }
        if let dns = measurement.dnsResolutionMs, dns >= thresholds.internetDnsAttentionMs {
            return ConnectionPathStageVerdict(stage: .internet, status: .attention, limitingFact: .internetDns)
        }
        return ConnectionPathStageVerdict(stage: .internet, status: .normal, limitingFact: nil)
    }

    // MARK: - Categoria

    /// Escolhe a pior severidade entre as etapas (`.unavailable` não conta
    /// como problema — é neutro). Sem nenhuma etapa ruim, `.healthy`. Com
    /// uma única categoria de responsável no topo, destaca a etapa mais a
    /// montante (mais perto do usuário) entre as empatadas. Com mais de
    /// uma categoria empatada no topo, `.inconclusive` — o modelo evita
    /// apontar um culpado único quando a evidência não sustenta isso
    /// (requisito explícito da especificação: nunca afirmação categórica
    /// sem segurança).
    private static func deriveCategory(
        _ stages: [ConnectionPathStageVerdict]
    ) -> (ConnectionPathCategory, ConnectionPathStage?) {
        func severity(_ status: ConnectionPathStageStatus) -> Int {
            switch status {
            case .normal, .unavailable: return 0
            case .attention: return 1
            case .likelyProblem: return 2
            }
        }
        func category(for stage: ConnectionPathStage) -> ConnectionPathCategory {
            switch stage {
            case .device: return .local
            case .wifi, .router: return .wifi
            case .carrier: return .carrier
            case .internet: return .external
            }
        }

        let maxSeverity = stages.map { severity($0.status) }.max() ?? 0
        guard maxSeverity > 0 else { return (.healthy, nil) }

        let worst = stages.filter { severity($0.status) == maxSeverity }
        let categories = Set(worst.map { category(for: $0.stage) })
        guard categories.count == 1, let onlyCategory = categories.first else {
            return (.inconclusive, nil)
        }

        let order: [ConnectionPathStage] = [.device, .wifi, .router, .carrier, .internet]
        let highlighted = order.first { stage in worst.contains { $0.stage == stage } }
        return (onlyCategory, highlighted)
    }
}
