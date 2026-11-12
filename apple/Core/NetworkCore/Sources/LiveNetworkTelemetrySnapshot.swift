import Foundation

/// Snapshot factual de telemetria de rede amostrada ao vivo (em repouso/idle).
///
/// Contém estritamente medições pontuais e metadados de sistema. Nenhuma
/// inferência, fórmula de aptidão ou heurística de produto reside aqui (AGENTS.md §1/§8).
public struct LiveNetworkTelemetrySnapshot: Codable, Equatable, Hashable, Sendable {
    public let timestamp: Date
    public let connectionKind: NetworkConnectionKind?
    public let interfaceLabel: String
    public let isExpensive: Bool
    public let isConstrained: Bool

    /// Latência RTT mediana das amostras recentes (ms). `nil` se não houver amostras válidas.
    public let latencyMs: Double?

    /// Jitter calculado conforme RFC 3550 sobre a janela recente. `nil` se amostras < 3 (ausência não é zero).
    public let jitterMs: Double?

    /// Perda percentual estimada na janela recente (0 a 100%). `nil` se amostras insuficientes.
    public let packetLossPercent: Double?

    /// Taxa de enlace físico Wi-Fi (Mbps) — disponível no macOS via CoreWLAN; `nil` no iOS por restrição de API pública.
    public let wifiLinkSpeedMbps: Double?

    /// Intensidade de sinal Wi-Fi (dBm) informada pela plataforma.
    public let wifiRssiDbm: Double?

    /// Quantidade de amostras ativas na janela de observação.
    public let sampleCount: Int

    public init(
        timestamp: Date = Date(),
        connectionKind: NetworkConnectionKind? = nil,
        interfaceLabel: String = "",
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        latencyMs: Double? = nil,
        jitterMs: Double? = nil,
        packetLossPercent: Double? = nil,
        wifiLinkSpeedMbps: Double? = nil,
        wifiRssiDbm: Double? = nil,
        sampleCount: Int = 0
    ) {
        self.timestamp = timestamp
        self.connectionKind = connectionKind
        self.interfaceLabel = interfaceLabel
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.latencyMs = latencyMs
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
        self.wifiLinkSpeedMbps = wifiLinkSpeedMbps
        self.wifiRssiDbm = wifiRssiDbm
        self.sampleCount = sampleCount
    }
}

/// Linha de base (baseline) histórica comprovada de vazão para uma rede específica.
public struct ThroughputBaseline: Codable, Equatable, Hashable, Sendable {
    public let downloadMbps: Double?
    public let uploadMbps: Double?
    public let lastMeasuredAt: Date?
    public let networkIdentifier: String?
    public let sampleCount: Int

    public init(
        downloadMbps: Double? = nil,
        uploadMbps: Double? = nil,
        lastMeasuredAt: Date? = nil,
        networkIdentifier: String? = nil,
        sampleCount: Int = 1
    ) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.lastMeasuredAt = lastMeasuredAt
        self.networkIdentifier = networkIdentifier
        self.sampleCount = sampleCount
    }
}
