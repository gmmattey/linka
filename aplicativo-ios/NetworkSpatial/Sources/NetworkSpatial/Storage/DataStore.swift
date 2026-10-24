import Foundation
#if canImport(SwiftData)
import SwiftData
import os

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class DataStore: ObservableObject {
    public let modelContainer: ModelContainer
    private let logger = Logger(subsystem: "com.linka.assist", category: "SpatialDataStore")

    public var modelContext: ModelContext {
        modelContainer.mainContext
    }

    public init(inMemory: Bool = false) {
        let schema = Schema([
            HouseEntity.self,
            RoomEntity.self,
            MeasurementEntity.self,
            ComparisonSessionEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            self.modelContainer = container
        } else {
            logger.error("Falha ao inicializar ModelContainer em disco; utilizando fallback em memória.")
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                self.modelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Falha crítica ao inicializar ModelContainer mesmo em memória: \(error)")
            }
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            logger.error("Erro ao persistir alterações no SwiftData: \(error.localizedDescription)")
        }
    }

    /// Cria uma instância default ou recupera a casa existente
    public func fetchOrCreateDefaultHouse() -> House {
        let descriptor = FetchDescriptor<HouseEntity>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        do {
            if let houseEntity = try modelContext.fetch(descriptor).first {
                return mapToHouseDomain(houseEntity)
            }
        } catch {
            logger.error("Erro ao buscar residência salva: \(error.localizedDescription)")
        }

        // Cria uma casa inicial com cômodos padrão acolhedores
        let defaultHouseEntity = HouseEntity(name: "Minha Residência")
        let sala = RoomEntity(name: "Sala de Estar", icon: "sofa", gridX: 0, gridY: 0, hasRouter: true)
        let quarto = RoomEntity(name: "Quarto Principal", icon: "bed.double", gridX: 1, gridY: 0, hasRouter: false)
        let cozinha = RoomEntity(name: "Cozinha", icon: "fork.knife", gridX: 0, gridY: 1, hasRouter: false)
        let escritorio = RoomEntity(name: "Escritório", icon: "laptopcomputer", gridX: 1, gridY: 1, hasRouter: false)
        
        let defaultRooms = [sala, quarto, cozinha, escritorio]

        for room in defaultRooms {
            room.house = defaultHouseEntity
            defaultHouseEntity.rooms.append(room)
            modelContext.insert(room)
        }

        // Se rodar com argumento de mock ou demo, popula medições realistas para gerar dados visuais
        if CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--uitesting") {
            let mSala = MeasurementEntity(
                ratingRaw: QualityRating.excellent.rawValue,
                score: 96,
                causeRaw: DiagnosisCause.allGood.rawValue,
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 3.8,
                gatewayJitterMs: 1.2,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 19.4,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 240.0,
                explanation: "Conexão excelente no cômodo do roteador.",
                actionableRecommendation: "Sinal pleno e estável.",
                bssid: "AA:BB:CC:10:01:01",
                ssid: "MinhaCasa"
            )
            mSala.room = sala
            sala.measurements.append(mSala)
            modelContext.insert(mSala)

            let mCozinha = MeasurementEntity(
                ratingRaw: QualityRating.good.rawValue,
                score: 82,
                causeRaw: DiagnosisCause.allGood.rawValue,
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 16.5,
                gatewayJitterMs: 4.1,
                gatewayPacketLossPercent: 0.0,
                wanLatencyMs: 31.0,
                wanPacketLossPercent: 0.0,
                downloadThroughputMbps: 165.0,
                explanation: "Sinal bom para streaming e trabalho.",
                actionableRecommendation: "Ótima navegação.",
                bssid: "AA:BB:CC:10:01:01",
                ssid: "MinhaCasa"
            )
            mCozinha.room = cozinha
            cozinha.measurements.append(mCozinha)
            modelContext.insert(mCozinha)

            let mQuarto = MeasurementEntity(
                ratingRaw: QualityRating.poor.rawValue,
                score: 38,
                causeRaw: DiagnosisCause.localWiFiDegraded.rawValue,
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 142.0,
                gatewayJitterMs: 36.5,
                gatewayPacketLossPercent: 7.2,
                wanLatencyMs: 178.0,
                wanPacketLossPercent: 6.0,
                downloadThroughputMbps: 12.0,
                explanation: "Latência elevada até o roteador Wi-Fi devido a paredes e distância.",
                actionableRecommendation: "Mover o roteador cerca de 2m em direção ao corredor ou adicionar um nó mesh.",
                bssid: "AA:BB:CC:20:01:01",
                ssid: "MinhaCasa"
            )
            mQuarto.room = quarto
            quarto.measurements.append(mQuarto)
            modelContext.insert(mQuarto)

            let mEscritorio = MeasurementEntity(
                ratingRaw: QualityRating.fair.rawValue,
                score: 64,
                causeRaw: DiagnosisCause.localWiFiDegraded.rawValue,
                gatewayIP: "192.168.1.1",
                gatewayLatencyMs: 48.0,
                gatewayJitterMs: 12.8,
                gatewayPacketLossPercent: 1.0,
                wanLatencyMs: 65.0,
                wanPacketLossPercent: 0.5,
                downloadThroughputMbps: 54.0,
                explanation: "Sinal regular com oscilações ocasionais.",
                actionableRecommendation: "Aproximar o ponto de acesso.",
                bssid: "AA:BB:CC:20:01:01",
                ssid: "MinhaCasa"
            )
            mEscritorio.room = escritorio
            escritorio.measurements.append(mEscritorio)
            modelContext.insert(mEscritorio)
        }

        modelContext.insert(defaultHouseEntity)
        saveContext()

        return mapToHouseDomain(defaultHouseEntity)
    }

    /// Salva ou atualiza a estrutura de cômodos da casa
    public func saveRooms(_ rooms: [Room], for houseId: UUID) {
        let houseDescriptor = FetchDescriptor<HouseEntity>(predicate: #Predicate { $0.id == houseId })
        guard let houseEntity = try? modelContext.fetch(houseDescriptor).first else { return }

        // Mapeia e atualiza
        for room in rooms {
            let isRouter = room.hasRouter || (room.accessPoint?.type == .mainRouter)
            let nodeTypeRaw: String
            let nodeName: String?
            let backhaulTypeRaw: String?

            if let ap = room.accessPoint {
                nodeTypeRaw = ap.type.rawValue
                nodeName = ap.name
                backhaulTypeRaw = ap.backhaulType.rawValue
            } else {
                nodeTypeRaw = isRouter ? AccessPointType.mainRouter.rawValue : AccessPointType.none.rawValue
                nodeName = nil
                backhaulTypeRaw = nil
            }

            if let existingEntity = houseEntity.rooms.first(where: { $0.id == room.id }) {
                existingEntity.name = room.name
                existingEntity.icon = room.icon
                existingEntity.gridX = room.gridX
                existingEntity.gridY = room.gridY
                existingEntity.hasRouter = isRouter
                existingEntity.nodeTypeRaw = nodeTypeRaw
                existingEntity.nodeName = nodeName
                existingEntity.backhaulTypeRaw = backhaulTypeRaw
                existingEntity.capturedViaLiDAR = room.isLiDARCaptured
                existingEntity.floorAreaSqMeters = room.floorAreaSqMeters
            } else {
                let newEntity = RoomEntity(
                    id: room.id,
                    name: room.name,
                    icon: room.icon,
                    gridX: room.gridX,
                    gridY: room.gridY,
                    hasRouter: isRouter,
                    nodeTypeRaw: nodeTypeRaw,
                    nodeName: nodeName,
                    backhaulTypeRaw: backhaulTypeRaw,
                    capturedViaLiDAR: room.isLiDARCaptured,
                    floorAreaSqMeters: room.floorAreaSqMeters
                )
                newEntity.house = houseEntity
                houseEntity.rooms.append(newEntity)
                modelContext.insert(newEntity)
            }
        }

        // Remove cômodos que foram deletados
        let currentIds = Set(rooms.map(\.id))
        let toRemove = houseEntity.rooms.filter { !currentIds.contains($0.id) }
        for roomToRemove in toRemove {
            modelContext.delete(roomToRemove)
        }

        saveContext()
    }

    /// Adiciona uma nova medição ao cômodo
    public func saveMeasurement(_ result: MeasurementResult, for roomId: UUID) {
        let roomDescriptor = FetchDescriptor<RoomEntity>(predicate: #Predicate { $0.id == roomId })
        guard let roomEntity = (try? modelContext.fetch(roomDescriptor))?.first else {
            logger.error("Cômodo \(roomId) não encontrado para persistir medição")
            return
        }

        let measurementEntity = MeasurementEntity(
            id: result.id,
            timestamp: result.timestamp,
            ratingRaw: result.rating.rawValue,
            score: result.score,
            causeRaw: result.cause.rawValue,
            gatewayIP: result.metrics.gatewayIP,
            gatewayLatencyMs: result.metrics.gatewayLatencyMs,
            gatewayJitterMs: result.metrics.gatewayJitterMs,
            gatewayPacketLossPercent: result.metrics.gatewayPacketLossPercent,
            wanLatencyMs: result.metrics.wanLatencyMs,
            wanPacketLossPercent: result.metrics.wanPacketLossPercent,
            downloadThroughputMbps: result.metrics.downloadThroughputMbps,
            explanation: result.explanation,
            actionableRecommendation: result.actionableRecommendation,
            connectedNodeName: result.metrics.connectedNodeName,
            bssid: result.metrics.bssid,
            ssid: result.metrics.ssid,
            backhaulLatencyMs: result.metrics.backhaulLatencyMs,
            gatewayMedianMs: result.metrics.gatewayMedianMs,
            gatewayP95Ms: result.metrics.gatewayP95Ms,
            wanMedianMs: result.metrics.wanMedianMs,
            wanP95Ms: result.metrics.wanP95Ms,
            wanJitterMs: result.metrics.wanJitterMs,
            gatewayLossEvents: result.metrics.gatewayLossEvents,
            gatewayTotalProbes: result.metrics.gatewayTotalProbes,
            lossInterpretationRaw: result.metrics.gatewayLossInterpretation?.rawValue
        )

        measurementEntity.room = roomEntity
        roomEntity.measurements.append(measurementEntity)
        modelContext.insert(measurementEntity)
        saveContext()
    }

    /// Salva uma sessão Antes × Depois
    public func saveComparison(_ comparison: BeforeAfterComparison) {
        let encoder = JSONEncoder()
        let jsonString: String
        if let data = try? encoder.encode(comparison.roomComparisons), let str = String(data: data, encoding: .utf8) {
            jsonString = str
        } else {
            jsonString = "[]"
        }

        let entity = ComparisonSessionEntity(
            id: comparison.id,
            title: comparison.title,
            date: comparison.date,
            baselineCoveragePercent: comparison.baselineCoveragePercent,
            afterCoveragePercent: comparison.afterCoveragePercent,
            deltaCoveragePercent: comparison.deltaCoveragePercent,
            comparisonsJSON: jsonString
        )

        modelContext.insert(entity)
        saveContext()
    }

    // MARK: - Sessão Ativa de Comparativo Antes × Depois

    public func saveActiveComparisonBaseline(_ rooms: [Room]) {
        if let data = try? JSONEncoder().encode(rooms) {
            UserDefaults.standard.set(data, forKey: "active_comparison_baseline")
        }
    }

    public func fetchActiveComparisonBaseline() -> [Room]? {
        guard let data = UserDefaults.standard.data(forKey: "active_comparison_baseline") else { return nil }
        return try? JSONDecoder().decode([Room].self, from: data)
    }

    public func clearActiveComparisonBaseline() {
        UserDefaults.standard.removeObject(forKey: "active_comparison_baseline")
    }

    /// Carrega as comparações salvas
    public func fetchComparisons() -> [BeforeAfterComparison] {
        let descriptor = FetchDescriptor<ComparisonSessionEntity>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let entities = try? modelContext.fetch(descriptor) else { return [] }

        let decoder = JSONDecoder()
        return entities.compactMap { entity in
            let rooms: [RoomComparison]
            if let data = entity.comparisonsJSON.data(using: .utf8),
               let decoded = try? decoder.decode([RoomComparison].self, from: data) {
                rooms = decoded
            } else {
                rooms = []
            }

            return BeforeAfterComparison(
                id: entity.id,
                title: entity.title,
                date: entity.date,
                baselineCoveragePercent: entity.baselineCoveragePercent,
                afterCoveragePercent: entity.afterCoveragePercent,
                roomComparisons: rooms
            )
        }
    }

    // MARK: - Mapeamento de Domínio

    private func mapToHouseDomain(_ entity: HouseEntity) -> House {
        let rooms = entity.rooms.map { roomEntity -> Room in
            let latestMeasurementEntity = roomEntity.measurements.max(by: { $0.timestamp < $1.timestamp })
            let measurementResult: MeasurementResult?
            if let m = latestMeasurementEntity {
                measurementResult = MeasurementResult(
                    id: m.id,
                    roomId: roomEntity.id,
                    timestamp: m.timestamp,
                    rating: QualityRating(rawValue: m.ratingRaw) ?? .fair,
                    score: m.score,
                    cause: DiagnosisCause(rawValue: m.causeRaw) ?? .allGood,
                    metrics: NetworkMetrics(
                        gatewayIP: m.gatewayIP,
                        gatewayLatencyMs: m.gatewayLatencyMs,
                        gatewayJitterMs: m.gatewayJitterMs,
                        gatewayPacketLossPercent: m.gatewayPacketLossPercent,
                        wanLatencyMs: m.wanLatencyMs,
                        wanPacketLossPercent: m.wanPacketLossPercent,
                        downloadThroughputMbps: m.downloadThroughputMbps,
                        connectedNodeName: m.connectedNodeName,
                        bssid: m.bssid,
                        ssid: m.ssid,
                        backhaulLatencyMs: m.backhaulLatencyMs,
                        gatewayMedianMs: m.gatewayMedianMs,
                        gatewayP95Ms: m.gatewayP95Ms,
                        gatewayLossEvents: m.gatewayLossEvents,
                        gatewayTotalProbes: m.gatewayTotalProbes,
                        gatewayConsecutiveLoss: nil,
                        gatewayLossInterpretation: m.lossInterpretationRaw.flatMap { LossInterpretation(rawValue: $0) },
                        wanMedianMs: m.wanMedianMs,
                        wanP95Ms: m.wanP95Ms,
                        wanJitterMs: m.wanJitterMs,
                        wanLossInterpretation: nil
                    ),
                    explanation: m.explanation,
                    actionableRecommendation: m.actionableRecommendation
                )
            } else {
                measurementResult = nil
            }

            let apNode: AccessPointNode?
            if let apType = AccessPointType(rawValue: roomEntity.nodeTypeRaw), apType.isAccessPoint {
                let backhaul = roomEntity.backhaulTypeRaw.flatMap { BackhaulType(rawValue: $0) } ?? .wifi
                apNode = AccessPointNode(
                    name: roomEntity.nodeName ?? (apType == .mainRouter ? "Roteador Principal" : roomEntity.name),
                    type: apType,
                    backhaulType: backhaul,
                    roomId: roomEntity.id
                )
            } else if roomEntity.hasRouter {
                apNode = AccessPointNode(
                    name: roomEntity.nodeName ?? "Roteador Principal",
                    type: .mainRouter,
                    backhaulType: .wifi,
                    roomId: roomEntity.id
                )
            } else {
                apNode = nil
            }

            return Room(
                id: roomEntity.id,
                name: roomEntity.name,
                icon: roomEntity.icon,
                gridX: roomEntity.gridX,
                gridY: roomEntity.gridY,
                hasRouter: roomEntity.hasRouter || (apNode?.type == .mainRouter),
                lastMeasurement: measurementResult,
                accessPoint: apNode,
                floorAreaSqMeters: roomEntity.floorAreaSqMeters,
                isLiDARCaptured: roomEntity.capturedViaLiDAR
            )
        }

        return House(
            id: entity.id,
            name: entity.name,
            rooms: rooms,
            createdAt: entity.createdAt
        )
    }
}
#endif
