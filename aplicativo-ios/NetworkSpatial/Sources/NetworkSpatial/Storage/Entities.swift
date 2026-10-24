import Foundation
#if canImport(SwiftData)
import SwiftData

@available(iOS 17.0, macOS 14.0, *)
@Model
public final class HouseEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \RoomEntity.house)
    public var rooms: [RoomEntity] = []

    public init(id: UUID = UUID(), name: String = "Minha Casa", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.rooms = []
    }
}

@available(iOS 17.0, macOS 14.0, *)
@Model
public final class RoomEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var icon: String
    public var gridX: Int
    public var gridY: Int
    public var hasRouter: Bool
    public var nodeTypeRaw: String = "none"
    public var nodeName: String? = nil
    public var backhaulTypeRaw: String? = nil
    public var capturedViaLiDAR: Bool = false
    public var floorAreaSqMeters: Double? = nil
    public var dimensionsJSON: String? = nil
    public var house: HouseEntity?

    @Relationship(deleteRule: .cascade, inverse: \MeasurementEntity.room)
    public var measurements: [MeasurementEntity] = []

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "bed.double",
        gridX: Int = 0,
        gridY: Int = 0,
        hasRouter: Bool = false,
        nodeTypeRaw: String = "none",
        nodeName: String? = nil,
        backhaulTypeRaw: String? = nil,
        capturedViaLiDAR: Bool = false,
        floorAreaSqMeters: Double? = nil,
        dimensionsJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.gridX = gridX
        self.gridY = gridY
        self.hasRouter = hasRouter
        self.nodeTypeRaw = nodeTypeRaw
        self.nodeName = nodeName
        self.backhaulTypeRaw = backhaulTypeRaw
        self.capturedViaLiDAR = capturedViaLiDAR
        self.floorAreaSqMeters = floorAreaSqMeters
        self.dimensionsJSON = dimensionsJSON
        self.measurements = []
    }
}

@available(iOS 17.0, macOS 14.0, *)
@Model
public final class MeasurementEntity {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var ratingRaw: String
    public var score: Int
    public var causeRaw: String
    public var gatewayIP: String
    public var gatewayLatencyMs: Double
    public var gatewayJitterMs: Double
    public var gatewayPacketLossPercent: Double
    public var wanLatencyMs: Double
    public var wanPacketLossPercent: Double
    public var downloadThroughputMbps: Double?
    public var explanation: String
    public var actionableRecommendation: String
    public var connectedNodeName: String? = nil
    public var bssid: String? = nil
    public var ssid: String? = nil
    public var backhaulLatencyMs: Double? = nil
    public var gatewayMedianMs: Double? = nil
    public var gatewayP95Ms: Double? = nil
    public var wanMedianMs: Double? = nil
    public var wanP95Ms: Double? = nil
    public var wanJitterMs: Double? = nil
    public var gatewayLossEvents: Int? = nil
    public var gatewayTotalProbes: Int? = nil
    public var lossInterpretationRaw: String? = nil
    public var room: RoomEntity?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        ratingRaw: String,
        score: Int,
        causeRaw: String,
        gatewayIP: String,
        gatewayLatencyMs: Double,
        gatewayJitterMs: Double,
        gatewayPacketLossPercent: Double,
        wanLatencyMs: Double,
        wanPacketLossPercent: Double,
        downloadThroughputMbps: Double? = nil,
        explanation: String,
        actionableRecommendation: String,
        connectedNodeName: String? = nil,
        bssid: String? = nil,
        ssid: String? = nil,
        backhaulLatencyMs: Double? = nil,
        gatewayMedianMs: Double? = nil,
        gatewayP95Ms: Double? = nil,
        wanMedianMs: Double? = nil,
        wanP95Ms: Double? = nil,
        wanJitterMs: Double? = nil,
        gatewayLossEvents: Int? = nil,
        gatewayTotalProbes: Int? = nil,
        lossInterpretationRaw: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.ratingRaw = ratingRaw
        self.score = score
        self.causeRaw = causeRaw
        self.gatewayIP = gatewayIP
        self.gatewayLatencyMs = gatewayLatencyMs
        self.gatewayJitterMs = gatewayJitterMs
        self.gatewayPacketLossPercent = gatewayPacketLossPercent
        self.wanLatencyMs = wanLatencyMs
        self.wanPacketLossPercent = wanPacketLossPercent
        self.downloadThroughputMbps = downloadThroughputMbps
        self.explanation = explanation
        self.actionableRecommendation = actionableRecommendation
        self.connectedNodeName = connectedNodeName
        self.bssid = bssid
        self.ssid = ssid
        self.backhaulLatencyMs = backhaulLatencyMs
        self.gatewayMedianMs = gatewayMedianMs
        self.gatewayP95Ms = gatewayP95Ms
        self.wanMedianMs = wanMedianMs
        self.wanP95Ms = wanP95Ms
        self.wanJitterMs = wanJitterMs
        self.gatewayLossEvents = gatewayLossEvents
        self.gatewayTotalProbes = gatewayTotalProbes
        self.lossInterpretationRaw = lossInterpretationRaw
    }
}

@available(iOS 17.0, macOS 14.0, *)
@Model
public final class ComparisonSessionEntity {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var date: Date
    public var baselineCoveragePercent: Int
    public var afterCoveragePercent: Int
    public var deltaCoveragePercent: Int
    public var comparisonsJSON: String

    public init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        baselineCoveragePercent: Int,
        afterCoveragePercent: Int,
        deltaCoveragePercent: Int,
        comparisonsJSON: String
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.baselineCoveragePercent = baselineCoveragePercent
        self.afterCoveragePercent = afterCoveragePercent
        self.deltaCoveragePercent = deltaCoveragePercent
        self.comparisonsJSON = comparisonsJSON
    }
}
#endif
