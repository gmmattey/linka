import Foundation

// MARK: - Modo de Execução da Caminhada

public enum WalkSessionMode: String, Codable, Sendable, CaseIterable {
    case regular = "Mapeamento Residencial"
    case baseline = "Gravação de Baseline"
    case comparison = "Comparativo Antes × Depois"

    public var actionTitle: String {
        switch self {
        case .regular:
            return SpatialCopy.value("spatial.walk.mapHome", defaultValue: "Mapear minha casa")
        case .baseline:
            return SpatialCopy.value("spatial.walk.recordBaseline", defaultValue: "Gravar Baseline Inicial")
        case .comparison:
            return SpatialCopy.value("spatial.walk.newComparison", defaultValue: "Nova caminhada de comparação")
        }
    }
}

// MARK: - Resumo Consolidado ao Fim da Caminhada

public struct WalkSessionSummary: Sendable, Equatable {
    public let houseCoverageScore: Int
    public let baselineCoverageScore: Int?
    public let deltaScore: Int?
    public let measuredRoomsCount: Int
    public let skippedRoomsCount: Int
    public let totalRoomsCount: Int
    public let excellentCount: Int
    public let goodCount: Int
    public let fairCount: Int
    public let poorCount: Int
    public let detectedAccessPointsCount: Int
    public let measuredRooms: [Room]
    public let mode: WalkSessionMode

    public init(
        houseCoverageScore: Int,
        baselineCoverageScore: Int? = nil,
        deltaScore: Int? = nil,
        measuredRoomsCount: Int,
        skippedRoomsCount: Int,
        totalRoomsCount: Int,
        excellentCount: Int,
        goodCount: Int,
        fairCount: Int,
        poorCount: Int,
        detectedAccessPointsCount: Int,
        measuredRooms: [Room],
        mode: WalkSessionMode = .regular
    ) {
        self.houseCoverageScore = houseCoverageScore
        self.baselineCoverageScore = baselineCoverageScore
        self.deltaScore = deltaScore
        self.measuredRoomsCount = measuredRoomsCount
        self.skippedRoomsCount = skippedRoomsCount
        self.totalRoomsCount = totalRoomsCount
        self.excellentCount = excellentCount
        self.goodCount = goodCount
        self.fairCount = fairCount
        self.poorCount = poorCount
        self.detectedAccessPointsCount = detectedAccessPointsCount
        self.measuredRooms = measuredRooms
        self.mode = mode
    }
}

// MARK: - Máquina de Estados da Caminhada Passo a Passo

public enum WalkStepState: Sendable, Equatable {
    case intro(totalRooms: Int)
    case guidingToRoom(room: Room, stepIndex: Int, totalSteps: Int)
    case measuring(room: Room, stepIndex: Int, totalSteps: Int, diagnosticStep: DiagnosticStep, progress: Double)
    case roomCompleted(room: Room, stepIndex: Int, totalSteps: Int, result: MeasurementResult, nextRoom: Room?)
    case sessionSummary(summary: WalkSessionSummary)
}

// MARK: - Entidade de Domínio da Sessão de Caminhada

public struct WalkSession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var rooms: [Room]
    public var currentRoomIndex: Int
    public var completedMeasurements: [UUID: MeasurementResult]
    public var skippedRoomIds: Set<UUID>
    public var detectedBSSIDs: Set<String>
    public var startedAt: Date
    public var mode: WalkSessionMode

    public init(
        id: UUID = UUID(),
        rooms: [Room],
        currentRoomIndex: Int = 0,
        completedMeasurements: [UUID: MeasurementResult] = [:],
        skippedRoomIds: Set<UUID> = [],
        detectedBSSIDs: Set<String> = [],
        startedAt: Date = Date(),
        mode: WalkSessionMode = .regular
    ) {
        self.id = id
        self.rooms = rooms
        self.currentRoomIndex = currentRoomIndex
        self.completedMeasurements = completedMeasurements
        self.skippedRoomIds = skippedRoomIds
        self.detectedBSSIDs = detectedBSSIDs
        self.startedAt = startedAt
        self.mode = mode
    }

    public var currentRoom: Room? {
        guard currentRoomIndex >= 0 && currentRoomIndex < rooms.count else { return nil }
        return rooms[currentRoomIndex]
    }

    public var nextRoom: Room? {
        let nextIdx = currentRoomIndex + 1
        guard nextIdx < rooms.count else { return nil }
        return rooms[nextIdx]
    }

    public var isLastRoom: Bool {
        currentRoomIndex >= rooms.count - 1
    }

    public var progressFraction: Double {
        guard !rooms.isEmpty else { return 1.0 }
        return Double(completedMeasurements.count + skippedRoomIds.count) / Double(rooms.count)
    }
}

