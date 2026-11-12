import Foundation

/// Tipo de rede detectado por `SpeedTestCore` (`NWPathMonitor`). Fato puro,
/// sem copy — mesma disciplina de `EngineFailureReason`: o motor nunca
/// decide texto de apresentação, só o fato tipado. A UI (`SpeedTestViewModel`)
/// resolve o texto no idioma corrente a partir deste caso.
public enum MeasurementNetworkKind: String, Equatable, Sendable {
    case wifi
    case cellular
    case unknown
}

/// Fato do motor, convertido para o contrato persistível pelo adaptador do app.
public struct EnginePacketProbeEvidence: Equatable, Sendable {
    public let environmentIdentifier: String
    public let attemptCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let timeoutCount: Int
    public let longestFailureStreak: Int
    public let expandedAfterInitialWindow: Bool
    public let completed: Bool

    public init(environmentIdentifier: String, attemptCount: Int, successCount: Int, failureCount: Int, timeoutCount: Int, longestFailureStreak: Int, expandedAfterInitialWindow: Bool, completed: Bool) {
        self.environmentIdentifier = environmentIdentifier
        self.attemptCount = attemptCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.timeoutCount = timeoutCount
        self.longestFailureStreak = longestFailureStreak
        self.expandedAfterInitialWindow = expandedAfterInitialWindow
        self.completed = completed
    }

    public var packetLossPercent: Double? {
        guard completed, attemptCount > 0 else { return nil }
        return Double(failureCount) / Double(attemptCount) * 100
    }
}

public struct EngineRegionalGameReference: Equatable, Sendable {
    public let catalogVersion: String
    public let regionIdentifier: String?
    public let p50LatencyMs: Double?
    public let jitterMs: Double?
    public let attemptCount: Int
    public let validResponseCount: Int
    public let timeoutCount: Int
    public let packetLossPercent: Double?
    public let isMeasured: Bool
}

public struct MeasurementState {
    public var ping: Double?
    public var jitter: Double?
    public var packetLossPercent: Double?
    public var packetProbeEvidence: EnginePacketProbeEvidence?
    public var regionalGameReference: EngineRegionalGameReference?
    public var downloadSpeed: Double? // in Mbps
    public var uploadSpeed: Double? // in Mbps
    public var progress: Double // 0.0 to 1.0
    public var phase: Phase
    public var provider: String?
    public var networkType: MeasurementNetworkKind?
    public var duration: Double?
    /// Latência sob carga (ms), amostrada durante a fase de download
    /// (issue #52). `nil` quando a fase não produziu amostras válidas
    /// suficientes — nunca um valor inventado. Espelha o campo homônimo já
    /// existente no contrato canônico `NetworkMeasurement`.
    public var loadedLatencyMs: Double?
    /// Latência sob carga (ms) amostrada durante a fase de upload (issue
    /// #128) — paridade com `loadedLatencyMs`, mesma sondagem
    /// (`SpeedTestCore.performLoadedLatencyProbe`) e mesma agregação
    /// (`SpeedTestCore.aggregateLoadedLatency`), só que concorrente à carga
    /// de upload em vez de download. `nil` pelo mesmo motivo: amostras
    /// insuficientes ou sondagem indisponível nunca inventam um valor.
    /// Campo distinto (em vez de reaproveitar `loadedLatencyMs` para as duas
    /// fases) porque download e upload sob carga são fatos independentes —
    /// um pode existir sem o outro, e a comparação parada-vs-carga (issue
    /// #128, `NetworkInsights.LoadResponsivenessEvaluator`) precisa dos dois
    /// separadamente. Espelha o campo homônimo em `NetworkMeasurement`.
    public var loadedLatencyUploadMs: Double?
    /// Tempo de resolução DNS (ms) do host usado no teste — Expert Mode.
    /// Sondagem única via `SpeedTestCore.resolveDNS`, roda em paralelo ao
    /// ping. `nil` em falha ou timeout — nunca `0` (ausência não é zero).
    /// Espelha o campo homônimo em `NetworkMeasurement`.
    public var dnsResolutionMs: Double?
    /// Coeficiente de variação da vazão de download (desvio padrão relativo
    /// à média, janela estável) — issue #52. Propriedade motor-interna
    /// nesta primeira entrega, não faz parte do contrato canônico
    /// `NetworkMeasurement`. `nil` quando não há amostras suficientes.
    public var downloadThroughputVariation: Double?
    /// Mesma medida de `downloadThroughputVariation`, para a fase de upload.
    public var uploadThroughputVariation: Double?
    /// Evidência da metodologia v1 de responsividade sob carga. Só é
    /// preenchida no estado final; a UI continua recebendo os escalares
    /// compatíveis durante as fases.
    public var loadResponsiveness: EngineLoadResponsivenessEvidence?
    /// Motivo tipado de falha fatal (issue #66) — não-`nil` somente quando
    /// `phase == .error`. Só fato, sem copy: mensagem amigável é decisão da
    /// UI (ver `EngineFailureReason`).
    public var failureReason: EngineFailureReason?
    
    public var location: (latitude: Double, longitude: Double)?

    public init(ping: Double? = nil, jitter: Double? = nil, packetLossPercent: Double? = nil, packetProbeEvidence: EnginePacketProbeEvidence? = nil, regionalGameReference: EngineRegionalGameReference? = nil, downloadSpeed: Double? = nil, uploadSpeed: Double? = nil, progress: Double = 0.0, phase: Phase = .idle, provider: String? = nil, networkType: MeasurementNetworkKind? = nil, duration: Double? = nil, loadedLatencyMs: Double? = nil, loadedLatencyUploadMs: Double? = nil, dnsResolutionMs: Double? = nil, downloadThroughputVariation: Double? = nil, uploadThroughputVariation: Double? = nil, loadResponsiveness: EngineLoadResponsivenessEvidence? = nil, failureReason: EngineFailureReason? = nil, location: (latitude: Double, longitude: Double)? = nil) {
        self.ping = ping
        self.jitter = jitter
        self.packetLossPercent = packetLossPercent
        self.packetProbeEvidence = packetProbeEvidence
        self.regionalGameReference = regionalGameReference
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.progress = progress
        self.phase = phase
        self.provider = provider
        self.networkType = networkType
        self.duration = duration
        self.loadedLatencyMs = loadedLatencyMs
        self.loadedLatencyUploadMs = loadedLatencyUploadMs
        self.dnsResolutionMs = dnsResolutionMs
        self.downloadThroughputVariation = downloadThroughputVariation
        self.uploadThroughputVariation = uploadThroughputVariation
        self.loadResponsiveness = loadResponsiveness
        self.failureReason = failureReason
        self.location = location
    }
}
