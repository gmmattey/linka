import Foundation
import SwiftUI

// MARK: - Classificação Determinística de Qualidade

public enum QualityRating: String, Codable, CaseIterable, Sendable {
    case excellent = "Ótimo"
    case good = "Bom"
    case fair = "Regular"
    case poor = "Ruim"
    case unmeasured = "Não Medido"

    public var label: String {
        switch self {
        case .excellent: return SpatialCopy.value("spatial.rating.excellent", defaultValue: rawValue)
        case .good: return SpatialCopy.value("spatial.rating.good", defaultValue: rawValue)
        case .fair: return SpatialCopy.value("spatial.rating.fair", defaultValue: rawValue)
        case .poor: return SpatialCopy.value("spatial.rating.poor", defaultValue: rawValue)
        case .unmeasured: return SpatialCopy.value("spatial.rating.unmeasured", defaultValue: rawValue)
        }
    }

    public var systemImage: String {
        switch self {
        case .excellent:
            return "checkmark.circle.fill"
        case .good:
            return "checkmark.circle"
        case .fair:
            return "exclamationmark.triangle.fill"
        case .poor:
            return "xmark.octagon.fill"
        case .unmeasured:
            return "circle.dashed"
        }
    }

    /// Pontuação normalizada para cálculo de cobertura da casa (0 a 100)
    public var scoreValue: Int {
        switch self {
        case .excellent: return 100
        case .good: return 80
        case .fair: return 50
        case .poor: return 20
        case .unmeasured: return 0
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .excellent:
            return SpatialCopy.value("spatial.rating.excellent.a11y", defaultValue: "Qualidade Ótima. Conexão excelente neste cômodo.")
        case .good:
            return SpatialCopy.value("spatial.rating.good.a11y", defaultValue: "Qualidade Boa. Conexão estável para chamadas e streaming.")
        case .fair:
            return SpatialCopy.value("spatial.rating.fair.a11y", defaultValue: "Qualidade Regular. Sinal degradado por obstáculos ou distância do roteador.")
        case .poor:
            return SpatialCopy.value("spatial.rating.poor.a11y", defaultValue: "Qualidade Ruim. Ponto crítico com alto risco de quedas e lentidão.")
        case .unmeasured:
            return SpatialCopy.value("spatial.rating.unmeasured.a11y", defaultValue: "Cômodo ainda não medido.")
        }
    }
}

// MARK: - Diagnóstico Discriminado (Wi-Fi vs. Operadora)

public enum DiagnosisCause: String, Codable, Sendable {
    case allGood = "Wi-Fi e Internet Excelentes"
    case localWiFiDegraded = "Problema no Sinal Wi-Fi (Distância/Obstáculos)"
    case ispDegraded = "Instabilidade da Operadora de Internet (WAN)"
    case bothDegraded = "Instabilidade Geral (Wi-Fi e Provedor)"
    case offline = "Sem Conexão Wi-Fi Ativa"

    public var userFriendlyMessage: String {
        switch self {
        case .allGood:
            return SpatialCopy.value("spatial.cause.allGood.msg", defaultValue: "Seu Wi-Fi e sua internet estão funcionando com alta estabilidade neste ponto.")
        case .localWiFiDegraded:
            return SpatialCopy.value("spatial.cause.localWiFiDegraded.msg", defaultValue: "O sinal até o roteador apresentou resposta lenta ou oscilação neste cômodo. Causa provável: distância, obstáculos físicos ou interferência local.")
        case .ispDegraded:
            return SpatialCopy.value("spatial.cause.ispDegraded.msg", defaultValue: "O roteador respondeu com rapidez, mas a rota externa para a internet apresentou lentidão. Causa provável: instabilidade externa da operadora ou na rota.")
        case .bothDegraded:
            return SpatialCopy.value("spatial.cause.bothDegraded.msg", defaultValue: "Identificamos resposta lenta no roteador local combinada com instabilidade externa na internet.")
        case .offline:
            return SpatialCopy.value("spatial.cause.offline.msg", defaultValue: "O dispositivo não está conectado a uma rede Wi-Fi.")
        }
    }

    public var systemImage: String {
        switch self {
        case .allGood:
            return "checkmark.shield.fill"
        case .localWiFiDegraded:
            return "wifi.exclamationmark"
        case .ispDegraded:
            return "antenna.radiowaves.left.and.right.slash"
        case .bothDegraded:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "wifi.slash"
        }
    }
}

// MARK: - Tag Resumida de Diagnóstico (LAN vs. WAN no Card)

public enum DiagnosisTag: String, Codable, Sendable, Equatable {
    case healthy = "Sinal Estável"
    case weakWiFi = "Wi-Fi Fraco"
    case slowProvider = "Operadora Lenta"
    case unmeasured = "Não Medido"

    public var label: String {
        switch self {
        case .healthy: return SpatialCopy.value("spatial.tag.healthy", defaultValue: rawValue)
        case .weakWiFi: return SpatialCopy.value("spatial.tag.weakWiFi", defaultValue: rawValue)
        case .slowProvider: return SpatialCopy.value("spatial.tag.slowProvider", defaultValue: rawValue)
        case .unmeasured: return SpatialCopy.value("spatial.tag.unmeasured", defaultValue: rawValue)
        }
    }

    public var systemImage: String {
        switch self {
        case .healthy:
            return "checkmark.circle"
        case .weakWiFi:
            return "wifi.exclamationmark"
        case .slowProvider:
            return "antenna.radiowaves.left.and.right.slash"
        case .unmeasured:
            return "circle.dashed"
        }
    }

    public var isIssue: Bool {
        self == .weakWiFi || self == .slowProvider
    }
}

// MARK: - Topologia Mesh & Pontos de Acesso Wi-Fi

public enum AccessPointType: String, Codable, CaseIterable, Sendable {
    case none = "Nenhum"
    case mainRouter = "Roteador Principal"
    case meshSatellite = "Nó Mesh"
    case repeater = "Repetidor Wi-Fi"

    public var label: String {
        switch self {
        case .none: return SpatialCopy.value("spatial.ap.none", defaultValue: rawValue)
        case .mainRouter: return SpatialCopy.value("spatial.ap.mainRouter", defaultValue: rawValue)
        case .meshSatellite: return SpatialCopy.value("spatial.ap.meshSatellite", defaultValue: rawValue)
        case .repeater: return SpatialCopy.value("spatial.ap.repeater", defaultValue: rawValue)
        }
    }

    public var shortLabel: String {
        switch self {
        case .none: return SpatialCopy.value("spatial.ap.none", defaultValue: "Nenhum")
        case .mainRouter: return SpatialCopy.value("spatial.ap.short.router", defaultValue: "Roteador")
        case .meshSatellite: return SpatialCopy.value("spatial.ap.meshSatellite", defaultValue: "Nó Mesh")
        case .repeater: return SpatialCopy.value("spatial.ap.short.repeater", defaultValue: "Repetidor")
        }
    }

    public var systemImage: String {
        switch self {
        case .none:
            return "circle.slash"
        case .mainRouter:
            return "router.fill"
        case .meshSatellite:
            return "point.3.connected.trianglepath.dotted"
        case .repeater:
            return "antenna.radiowaves.left.and.right"
        }
    }

    public var isAccessPoint: Bool {
        self != .none
    }

    public var semanticColor: Color {
        switch self {
        case .mainRouter:
            return WiFiCasaTheme.brandAccent
        case .meshSatellite:
            return WiFiCasaTheme.brandAccentWarm
        case .repeater:
            return WiFiCasaTheme.scoreFair
        case .none:
            return WiFiCasaTheme.textSecondary
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .mainRouter:
            return "Roteador principal instalado neste cômodo"
        case .meshSatellite:
            return "Nó Mesh satélite instalado neste cômodo"
        case .repeater:
            return "Repetidor Wi-Fi instalado neste cômodo"
        case .none:
            return "Sem ponto de acesso Wi-Fi configurado"
        }
    }
}

public enum BackhaulType: String, Codable, CaseIterable, Sendable {
    case wifi = "Sem Fio (Wi-Fi)"
    case ethernet = "Cabo de Rede (Ethernet)"
    case unknown = "Desconhecido"

    public var label: String {
        switch self {
        case .wifi: return SpatialCopy.value("spatial.backhaul.wifi", defaultValue: rawValue)
        case .ethernet: return SpatialCopy.value("spatial.backhaul.ethernet", defaultValue: rawValue)
        case .unknown: return SpatialCopy.value("spatial.backhaul.unknown", defaultValue: rawValue)
        }
    }

    public var systemImage: String {
        switch self {
        case .wifi:
            return "wifi"
        case .ethernet:
            return "cable.connector"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

public struct AccessPointNode: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var type: AccessPointType
    public var backhaulType: BackhaulType
    public var roomId: UUID
    public var bssid: String?

    public init(
        id: UUID = UUID(),
        name: String,
        type: AccessPointType,
        backhaulType: BackhaulType = .wifi,
        roomId: UUID,
        bssid: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.backhaulType = backhaulType
        self.roomId = roomId
        self.bssid = bssid
    }
}

// MARK: - Interpretação Estatística de Perda de Pacotes (RFC 7680)

public enum LossInterpretation: String, Codable, Sendable {
    case stable = "Estável"
    case isolatedEvent = "Evento Isolado"
    case confirmedLoss = "Perda Confirmada"
    case consecutiveLoss = "Instabilidade Forte"
    case severeLoss = "Timeout Repetido"

    public var isDegraded: Bool {
        switch self {
        case .stable, .isolatedEvent:
            return false
        case .confirmedLoss, .consecutiveLoss, .severeLoss:
            return true
        }
    }

    public var badgeText: String {
        switch self {
        case .stable:
            return SpatialCopy.value("spatial.loss.stable", defaultValue: "Estável")
        case .isolatedEvent:
            return SpatialCopy.value("spatial.loss.isolated", defaultValue: "Oscilação Isolada")
        case .confirmedLoss:
            return SpatialCopy.value("spatial.loss.confirmed", defaultValue: "Perda Confirmada")
        case .consecutiveLoss:
            return SpatialCopy.value("spatial.loss.consecutive", defaultValue: "Perdas Consecutivas")
        case .severeLoss:
            return SpatialCopy.value("spatial.loss.severe", defaultValue: "Timeout Crítico")
        }
    }
}

// MARK: - Métricas de Rede

public struct NetworkMetrics: Codable, Sendable, Equatable {
    public var gatewayIP: String
    public var gatewayLatencyMs: Double // RTT Mediano ou Médio para compatibilidade
    public var gatewayJitterMs: Double
    public var gatewayPacketLossPercent: Double
    public var wanLatencyMs: Double
    public var wanPacketLossPercent: Double
    public var downloadThroughputMbps: Double?
    public var connectedNodeName: String?
    public var bssid: String?
    public var ssid: String?
    public var backhaulLatencyMs: Double?

    // Métricas estatísticas refinadas (RFC 7680 / RFC 3550)
    public var gatewayMedianMs: Double?
    public var gatewayP95Ms: Double?
    public var gatewayLossEvents: Int?
    public var gatewayTotalProbes: Int?
    public var gatewayConsecutiveLoss: Int?
    public var gatewayLossInterpretation: LossInterpretation?

    public var wanMedianMs: Double?
    public var wanP95Ms: Double?
    public var wanJitterMs: Double?
    public var wanLossInterpretation: LossInterpretation?

    public init(
        gatewayIP: String = "192.168.1.1",
        gatewayLatencyMs: Double = 0,
        gatewayJitterMs: Double = 0,
        gatewayPacketLossPercent: Double = 0,
        wanLatencyMs: Double = 0,
        wanPacketLossPercent: Double = 0,
        downloadThroughputMbps: Double? = nil,
        connectedNodeName: String? = nil,
        bssid: String? = nil,
        ssid: String? = nil,
        backhaulLatencyMs: Double? = nil,
        gatewayMedianMs: Double? = nil,
        gatewayP95Ms: Double? = nil,
        gatewayLossEvents: Int? = nil,
        gatewayTotalProbes: Int? = nil,
        gatewayConsecutiveLoss: Int? = nil,
        gatewayLossInterpretation: LossInterpretation? = nil,
        wanMedianMs: Double? = nil,
        wanP95Ms: Double? = nil,
        wanJitterMs: Double? = nil,
        wanLossInterpretation: LossInterpretation? = nil
    ) {
        self.gatewayIP = gatewayIP
        self.gatewayLatencyMs = gatewayLatencyMs
        self.gatewayJitterMs = gatewayJitterMs
        self.gatewayPacketLossPercent = gatewayPacketLossPercent
        self.wanLatencyMs = wanLatencyMs
        self.wanPacketLossPercent = wanPacketLossPercent
        self.downloadThroughputMbps = downloadThroughputMbps
        self.connectedNodeName = connectedNodeName
        self.bssid = bssid
        self.ssid = ssid
        self.backhaulLatencyMs = backhaulLatencyMs
        self.gatewayMedianMs = gatewayMedianMs
        self.gatewayP95Ms = gatewayP95Ms
        self.gatewayLossEvents = gatewayLossEvents
        self.gatewayTotalProbes = gatewayTotalProbes
        self.gatewayConsecutiveLoss = gatewayConsecutiveLoss
        self.gatewayLossInterpretation = gatewayLossInterpretation
        self.wanMedianMs = wanMedianMs
        self.wanP95Ms = wanP95Ms
        self.wanJitterMs = wanJitterMs
        self.wanLossInterpretation = wanLossInterpretation
    }
}

// MARK: - Ponto de Acesso Detectado & Evento de Handoff

public struct DetectedAccessPoint: Identifiable, Codable, Sendable, Equatable {
    public let id: String // BSSID normalizado
    public let bssid: String // BSSID normalizado canônico
    public let ssid: String?
    public var label: String // Nome amigável ("AP 1", "AP 2")
    public var firstSeenRoomName: String?
    public var observedCount: Int

    public init(
        id: String,
        bssid: String,
        ssid: String? = nil,
        label: String,
        firstSeenRoomName: String? = nil,
        observedCount: Int = 1
    ) {
        self.id = id
        self.bssid = bssid
        self.ssid = ssid
        self.label = label
        self.firstSeenRoomName = firstSeenRoomName
        self.observedCount = observedCount
    }
}

public struct AccessPointHandoffEvent: Sendable, Equatable {
    public let fromBSSID: String
    public let toBSSID: String
    public let ssid: String?
    public let fromAPName: String
    public let toAPName: String
    public let timestamp: Date

    public init(
        fromBSSID: String,
        toBSSID: String,
        ssid: String?,
        fromAPName: String,
        toAPName: String,
        timestamp: Date = Date()
    ) {
        self.fromBSSID = fromBSSID
        self.toBSSID = toBSSID
        self.ssid = ssid
        self.fromAPName = fromAPName
        self.toAPName = toAPName
        self.timestamp = timestamp
    }
}

// MARK: - Resultado Consolidado de Medição

public struct MeasurementResult: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var roomId: UUID
    public var timestamp: Date
    public var rating: QualityRating
    public var score: Int
    public var cause: DiagnosisCause
    public var metrics: NetworkMetrics
    public var explanation: String
    public var actionableRecommendation: String

    public init(
        id: UUID = UUID(),
        roomId: UUID,
        timestamp: Date = Date(),
        rating: QualityRating,
        score: Int,
        cause: DiagnosisCause,
        metrics: NetworkMetrics,
        explanation: String,
        actionableRecommendation: String
    ) {
        self.id = id
        self.roomId = roomId
        self.timestamp = timestamp
        self.rating = rating
        self.score = score
        self.cause = cause
        self.metrics = metrics
        self.explanation = explanation
        self.actionableRecommendation = actionableRecommendation
    }

    public var diagnosisTag: DiagnosisTag {
        switch cause {
        case .allGood:
            return .healthy
        case .localWiFiDegraded, .bothDegraded, .offline:
            return .weakWiFi
        case .ispDegraded:
            return .slowProvider
        }
    }
}

// MARK: - Cômodo e Casa

public struct Room: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var gridX: Int
    public var gridY: Int
    public var hasRouter: Bool
    public var lastMeasurement: MeasurementResult?
    public var accessPoint: AccessPointNode?
    public var floorAreaSqMeters: Double?
    public var isLiDARCaptured: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "bed.double",
        gridX: Int = 0,
        gridY: Int = 0,
        hasRouter: Bool = false,
        lastMeasurement: MeasurementResult? = nil,
        accessPoint: AccessPointNode? = nil,
        floorAreaSqMeters: Double? = nil,
        isLiDARCaptured: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.gridX = gridX
        self.gridY = gridY
        self.hasRouter = hasRouter || (accessPoint?.type == .mainRouter)
        self.lastMeasurement = lastMeasurement
        self.accessPoint = accessPoint
        self.floorAreaSqMeters = floorAreaSqMeters
        self.isLiDARCaptured = isLiDARCaptured
    }

    public var currentRating: QualityRating {
        lastMeasurement?.rating ?? .unmeasured
    }

    public var currentScore: Int {
        lastMeasurement?.score ?? 0
    }

    public var diagnosisTag: DiagnosisTag {
        lastMeasurement?.diagnosisTag ?? .unmeasured
    }
}

public struct House: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var rooms: [Room]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Minha Residência",
        rooms: [Room] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rooms = rooms
        self.createdAt = createdAt
    }

    /// Pontuação média percentual calculada a partir dos cômodos efetivamente medidos
    public var totalCoveragePercent: Int {
        let measuredRooms = rooms.compactMap(\.lastMeasurement)
        guard !measuredRooms.isEmpty else { return 0 }
        let totalScore = measuredRooms.reduce(0) { $0 + $1.score }
        return Int(round(Double(totalScore) / Double(measuredRooms.count)))
    }

    public var routerRoom: Room? {
        rooms.first(where: \.hasRouter)
    }
}

// MARK: - Comparativo Antes × Depois

public struct RoomComparison: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var roomName: String
    public var roomIcon: String
    public var beforeRating: QualityRating
    public var beforeScore: Int
    public var afterRating: QualityRating
    public var afterScore: Int

    public var deltaScore: Int {
        afterScore - beforeScore
    }

    public init(
        id: UUID = UUID(),
        roomName: String,
        roomIcon: String,
        beforeRating: QualityRating,
        beforeScore: Int,
        afterRating: QualityRating,
        afterScore: Int
    ) {
        self.id = id
        self.roomName = roomName
        self.roomIcon = roomIcon
        self.beforeRating = beforeRating
        self.beforeScore = beforeScore
        self.afterRating = afterRating
        self.afterScore = afterScore
    }
}

public struct BeforeAfterComparison: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var baselineCoveragePercent: Int
    public var afterCoveragePercent: Int
    public var roomComparisons: [RoomComparison]

    public var deltaCoveragePercent: Int {
        afterCoveragePercent - baselineCoveragePercent
    }

    public init(
        id: UUID = UUID(),
        title: String = "Comparativo de Qualidade",
        date: Date = Date(),
        baselineCoveragePercent: Int,
        afterCoveragePercent: Int,
        roomComparisons: [RoomComparison]
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.baselineCoveragePercent = baselineCoveragePercent
        self.afterCoveragePercent = afterCoveragePercent
        self.roomComparisons = roomComparisons
    }
}
