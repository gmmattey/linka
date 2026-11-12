import SwiftUI
import NetworkCore
import NetworkInsights

/// Copy curta em linguagem comum para cada métrica (issue #53) — vive só na
/// UI, compartilhada por `HistoryView` (`DetailItem`) e `MainView`
/// (`InlineResultDetails`) para os dois lugares falarem a mesma língua. Não
/// é diagnóstico nem tutorial de rede, só o que a métrica significa. Não
/// repete o número que já está na tela.
enum MetricExplanation {
    static var ping: String { LinkaCopy.value("metric.explanation.ping") }
    static var jitter: String { LinkaCopy.value("metric.explanation.jitter") }
    static var packetLoss: String { LinkaCopy.value("metric.explanation.packetLoss") }
    static var loadedLatency: String { LinkaCopy.value("metric.explanation.loadedLatency") }
    /// issue #128 — paridade de `loadedLatency` para a fase de upload.
    static var loadedLatencyUpload: String { LinkaCopy.value("metric.explanation.loadedLatencyUpload") }
    static var dnsResolution: String { LinkaCopy.value("metric.explanation.dns") }
}

/// Copy da categoria de responsividade sob carga (issue #128) — vive na UI,
/// mesmo padrão de `MetricExplanation`/`UsageSuitabilityCopy`: o pacote de
/// cálculo (`NetworkInsights`) não conhece texto. Nomeia o fenômeno
/// (fila cheia no roteador / bufferbloat) sem apontar causa não medida
/// (ex.: nunca culpa um aparelho, provedor ou vizinho específico).
enum LoadResponsivenessCopy {
    static func label(for category: LoadResponsivenessCategory) -> String {
        switch category {
        case .high: return LinkaCopy.value("loadResponsiveness.high")
        case .medium: return LinkaCopy.value("loadResponsiveness.medium")
        case .low: return LinkaCopy.value("loadResponsiveness.low")
        case .notAssessed: return LinkaCopy.value("loadResponsiveness.notAssessed")
        }
    }

    static func explanation(for category: LoadResponsivenessCategory) -> String {
        switch category {
        case .high:
            return LinkaCopy.value("loadResponsiveness.high.explanation")
        case .medium, .low:
            return LinkaCopy.value("loadResponsiveness.limited.explanation")
        case .notAssessed:
            return LinkaCopy.value("loadResponsiveness.notAssessed.explanation")
        }
    }
}

/// Traduz o veredito puro de `UsageSuitabilityReport` (NetworkInsights) numa
/// única frase PT-BR de "para que serve" a conexão agora (issue #57).
///
/// Mesmo padrão de `MetricExplanation`: copy de produto vive só na UI, o
/// pacote de interpretação (`NetworkInsights`) não conhece texto nem marca
/// (AGENTS.md §8/§9). Nunca cita jogo, app ou serviço específico e nunca
/// promete desempenho de título algum — só descreve, em linguagem comum, o
/// que as métricas medidas hoje sustentam.
enum UsageSuitabilityCopy {
    /// Ordem de apresentação quando mais de um caso de uso está adequado —
    /// decisão de produto (issue #57), não uma hierarquia técnica entre
    /// unidades incomparáveis (Mbps vs. ms). Representa o "teto" da conexão
    /// do mais ao menos exigente aos olhos de quem está lendo o resultado.
    private static let priorityOrder: [UsageCase] = [.streaming4K, .onlineGaming, .streamingHD, .videoCall]

    private static func positiveSentence(for usageCase: UsageCase) -> String {
        switch usageCase {
        case .videoCall: return LinkaCopy.value("usage.case.videoCall.positive")
        case .streamingHD: return LinkaCopy.value("usage.case.streamingHD.positive")
        case .streaming4K: return LinkaCopy.value("usage.case.streaming4K.positive")
        case .onlineGaming: return LinkaCopy.value("usage.case.onlineGaming.positive")
        case .workUpload: return LinkaCopy.value("usage.case.workUpload.positive")
        }
    }

    private static func limitingMetricLabel(_ metric: NetworkMetric) -> String {
        switch metric {
        case .downloadMbps: return LinkaCopy.value("usage.metric.download")
        case .uploadMbps: return LinkaCopy.value("usage.metric.upload")
        case .latencyMs: return LinkaCopy.value("usage.metric.latency")
        case .jitterMs: return LinkaCopy.value("usage.metric.jitter")
        case .packetLossPercent: return LinkaCopy.value("usage.metric.packetLoss")
        case .loadedLatencyMs: return LinkaCopy.value("usage.metric.loadedLatency")
        case .loadedLatencyUploadMs: return LinkaCopy.value("usage.metric.loadedLatencyUpload")
        }
    }

    /// Escolhe uma única frase: o caso de uso mais exigente com veredito
    /// `.adequate` (o "teto real" da conexão hoje). Quando nenhum caso
    /// está `.adequate`, cita a métrica mais limitante em vez de uma frase
    /// vazia tipo "conexão limitada" sem explicação — requisito explícito
    /// da issue #57.
    static func sentence(for report: UsageSuitabilityReport) -> String {
        for usageCase in priorityOrder {
            guard let verdict = report.verdict(for: usageCase), verdict.level == .adequate else { continue }
            return positiveSentence(for: usageCase)
        }

        for usageCase in priorityOrder {
            guard let verdict = report.verdict(for: usageCase),
                  let limitingMetric = verdict.limitingMetric else { continue }
            let label = limitingMetricLabel(limitingMetric)
            return LinkaCopy.format("usage.limiting.sentence", label)
        }

        return LinkaCopy.value("usage.insufficient")
    }

    /// Título curto de cada `UsageCase`, para a listagem completa de
    /// veredictos (`UsageDiagnosticsView`) — distinto de `positiveSentences`,
    /// que é a frase única de resultado.
    static func title(for usageCase: UsageCase) -> String {
        switch usageCase {
        case .videoCall: return LinkaCopy.value("usage.case.videoCall.title")
        case .streamingHD: return LinkaCopy.value("usage.case.streamingHD.title")
        case .streaming4K: return LinkaCopy.value("usage.case.streaming4K.title")
        case .onlineGaming: return LinkaCopy.value("usage.case.onlineGaming.title")
        case .workUpload: return LinkaCopy.value("usage.case.workUpload.title")
        }
    }

    /// Descrição curta de um veredito individual — usada quando cada
    /// `UsageCase` tem sua própria linha (`UsageDiagnosticsView`), diferente
    /// de `sentence(for:)` que escolhe só um caso para uma frase única.
    static func detail(for verdict: UsageCaseVerdict) -> String {
        switch verdict.level {
        case .adequate:
            return positiveSentence(for: verdict.usageCase)
        case .limited:
            if let limitingMetric = verdict.limitingMetric {
                let label = limitingMetricLabel(limitingMetric)
                return LinkaCopy.format("usage.limiting.detail", label)
            }
            return LinkaCopy.value("usage.limited")
        case .notAssessed:
            return LinkaCopy.value("usage.insufficient.case")
        }
    }

    /// Nível agregado (Boa/Média/Ruim) exibido como resumo de uma linha na
    /// tela de resultado (issue "qualidade de uso Boa/Média/Ruim",
    /// 2026-08-29) — não substitui os veredictos por caso de
    /// `UsageDiagnosticsView`, é só um resumo de leitura rápida.
    /// `.notAssessed` fica fora da proporção: falta de dado não deve
    /// puxar o nível pra baixo nem pra cima, mesmo princípio de
    /// `ConnectionPathStageStatus.unavailable`.
    /// Ícone canônico de cada caso de uso.
    static func iconName(for usageCase: UsageCase) -> String {
        switch usageCase {
        case .videoCall: return "video"
        case .onlineGaming: return "gamecontroller"
        case .streamingHD, .streaming4K: return "play.tv"
        case .workUpload: return "arrow.up.circle"
        }
    }

    /// Rótulo, cor e ícone para um veredito avaliado ao vivo.
    static func liveStatusBadge(for verdict: LiveUsageCaseVerdict) -> (label: String, color: Color, icon: String) {
        switch verdict.level {
        case .adequate:
            if verdict.confidence == .liveTelemetry {
                return (LinkaCopy.value("usage.live.stable"), .statusGood, "checkmark.circle.fill")
            } else {
                return (LinkaCopy.value("usage.status.adequate"), .statusGood, "checkmark.circle.fill")
            }
        case .limited:
            if let reason = verdict.reason {
                switch reason {
                case .latencyTooHigh:
                    return (LinkaCopy.value("usage.live.latencyHigh"), .statusAttention, "exclamationmark.triangle.fill")
                case .jitterTooHigh:
                    return (LinkaCopy.value("usage.live.jitterHigh"), .statusAttention, "exclamationmark.triangle.fill")
                case .packetLossExceeded:
                    return (LinkaCopy.value("usage.live.packetLoss"), .statusCritical, "exclamationmark.triangle.fill")
                case .throughputBelowMinimum:
                    return (LinkaCopy.value("usage.status.limited"), .statusAttention, "exclamationmark.triangle.fill")
                case .constrainedModeActive:
                    return (LinkaCopy.value("usage.live.constrained"), .statusAttention, "exclamationmark.triangle.fill")
                default:
                    return (LinkaCopy.value("usage.status.limited"), .statusAttention, "exclamationmark.triangle.fill")
                }
            }
            return (LinkaCopy.value("usage.status.limited"), .statusAttention, "exclamationmark.triangle.fill")
        case .notAssessed:
            if verdict.reason == .missingThroughputMeasurement {
                return (LinkaCopy.value("usage.live.requiresSpeedTest"), .textSecondary, "speedometer")
            }
            return (LinkaCopy.value("usage.status.notAssessed"), .textSecondary, "questionmark.circle")
        }
    }

    /// Detalhe contextual do veredito ao vivo para acessibilidade e tooltips.
    static func liveDetail(for verdict: LiveUsageCaseVerdict) -> String {
        switch verdict.confidence {
        case .liveTelemetry:
            return LinkaCopy.value("usage.live.stable")
        case .historicalBaselineInferred:
            return LinkaCopy.value("usage.live.historicalBaseline")
        case .insufficientData:
            return LinkaCopy.value("usage.live.requiresSpeedTest")
        }
    }

    /// Nível agregado (Boa/Média/Ruim) exibido como resumo de uma linha na
    /// tela de resultado (issue "qualidade de uso Boa/Média/Ruim",
    /// 2026-08-29) — não substitui os veredictos por caso de
    /// `UsageDiagnosticsView`, é só um resumo de leitura rápida.
    /// `.notAssessed` fica fora da proporção: falta de dado não deve
    /// puxar o nível pra baixo nem pra cima, mesmo princípio de
    /// `ConnectionPathStageStatus.unavailable`.
    static func qualityLevel(for report: UsageSuitabilityReport) -> UsageQualityLevel? {
        let assessed = report.verdicts.filter { $0.level != .notAssessed }
        guard !assessed.isEmpty else { return nil }
        let adequateRatio = Double(assessed.filter { $0.level == .adequate }.count) / Double(assessed.count)
        if adequateRatio >= 0.75 { return .good }
        if adequateRatio >= 0.4 { return .medium }
        return .poor
    }
}

/// Três níveis de leitura rápida para a linha "Qualidade de uso" — issue
/// 2026-08-29. Não é um quarto sistema de classificação paralelo aos
/// `SuitabilityLevel`/`ConnectionPathStageStatus`; é só a tradução deles
/// pra um resumo de uma palavra, calculada em `UsageSuitabilityCopy.
/// qualityLevel(for:)`.
enum UsageQualityLevel: Equatable {
    case good
    case medium
    case poor

    var label: String {
        switch self {
        case .good: return LinkaCopy.value("usage.quality.good")
        case .medium: return LinkaCopy.value("usage.quality.medium")
        case .poor: return LinkaCopy.value("usage.quality.poor")
        }
    }

    var color: Color {
        switch self {
        case .good: return .statusGood
        case .medium: return .statusAttention
        case .poor: return .statusCritical
        }
    }
}
