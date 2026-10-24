import Foundation
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class WalkSessionViewModel: ObservableObject {
    @Published public var state: WalkStepState
    @Published public var session: WalkSession
    @Published public var errorMessage: String?
    @Published public var isMeasuring: Bool = false

    private let dataStore: DataStore
    private let diagnosticEngine: WiFiDiagnosticEngine
    private var measurementTask: Task<Void, Never>?
    public var onFinished: (() -> Void)?

    public init(
        rooms: [Room],
        mode: WalkSessionMode = .regular,
        dataStore: DataStore = DataStore(),
        diagnosticEngine: WiFiDiagnosticEngine = .shared,
        onFinished: (() -> Void)? = nil
    ) {
        self.dataStore = dataStore
        self.diagnosticEngine = diagnosticEngine
        self.onFinished = onFinished

        // Roteamento lógico espacial (Roteador principal primeiro + Manhattan TSP)
        let route = SpatialLayoutEngine.buildWalkRoute(rooms: rooms)
        let newSession = WalkSession(rooms: route, mode: mode)
        self.session = newSession

        if route.isEmpty {
            let emptySummary = WalkSessionSummary(
                houseCoverageScore: 0,
                measuredRoomsCount: 0,
                skippedRoomsCount: 0,
                totalRoomsCount: 0,
                excellentCount: 0,
                goodCount: 0,
                fairCount: 0,
                poorCount: 0,
                detectedAccessPointsCount: 0,
                measuredRooms: [],
                mode: mode
            )
            self.state = .sessionSummary(summary: emptySummary)
        } else {
            self.state = .intro(totalRooms: route.count)
        }
    }

    // MARK: - Ações de Fluxo da Caminhada

    /// Inicia o percurso e guia para o primeiro cômodo
    public func startWalk() {
        guard let firstRoom = session.currentRoom else {
            completeSession()
            return
        }
        state = .guidingToRoom(
            room: firstRoom,
            stepIndex: 1,
            totalSteps: session.rooms.count
        )
    }

    /// Usuário chegou ao cômodo e tocou em "Estou aqui"
    public func confirmAtLocation() {
        guard let room = session.currentRoom else { return }
        isMeasuring = true
        errorMessage = nil

        let stepIndex = session.currentRoomIndex + 1
        let totalSteps = session.rooms.count

        state = .measuring(
            room: room,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            diagnosticStep: .verifyingWiFi,
            progress: 0.1
        )

        measurementTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                let result = try await self.diagnosticEngine.performMeasurement(
                    for: room.id,
                    isRouterRoom: room.hasRouter
                ) { [weak self] step, progress in
                    Task { @MainActor in
                        guard let self = self, !Task.isCancelled else { return }
                        self.state = .measuring(
                            room: room,
                            stepIndex: stepIndex,
                            totalSteps: totalSteps,
                            diagnosticStep: step,
                            progress: progress
                        )
                    }
                }

                guard !Task.isCancelled else { return }

                // Registra medição no estado da caminhada e persiste localmente no SwiftData
                self.session.completedMeasurements[room.id] = result
                if let bssid = result.metrics.bssid {
                    self.session.detectedBSSIDs.insert(bssid)
                }
                self.dataStore.saveMeasurement(result, for: room.id)

                self.isMeasuring = false
                self.state = .roomCompleted(
                    room: room,
                    stepIndex: stepIndex,
                    totalSteps: totalSteps,
                    result: result,
                    nextRoom: self.session.nextRoom
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.isMeasuring = false
                self.errorMessage = error.localizedDescription
                // Permite ao usuário tentar novamente naquele cômodo
                self.state = .guidingToRoom(
                    room: room,
                    stepIndex: stepIndex,
                    totalSteps: totalSteps
                )
            }
        }
    }

    /// Usuário toca em "Continuar caminhada" após ver o resultado do cômodo
    public func continueWalk() {
        if session.isLastRoom {
            completeSession()
        } else {
            session.currentRoomIndex += 1
            if let nextRoom = session.currentRoom {
                state = .guidingToRoom(
                    room: nextRoom,
                    stepIndex: session.currentRoomIndex + 1,
                    totalSteps: session.rooms.count
                )
            } else {
                completeSession()
            }
        }
    }

    /// Usuário opta por pular um cômodo trancado ou inacessível
    public func skipCurrentRoom() {
        guard let current = session.currentRoom else {
            completeSession()
            return
        }

        session.skippedRoomIds.insert(current.id)

        if session.isLastRoom {
            completeSession()
        } else {
            session.currentRoomIndex += 1
            if let next = session.currentRoom {
                state = .guidingToRoom(
                    room: next,
                    stepIndex: session.currentRoomIndex + 1,
                    totalSteps: session.rooms.count
                )
            } else {
                completeSession()
            }
        }
    }

    /// Usuário encerra a caminhada mais cedo preservando os cômodos já medidos
    public func finishEarly() {
        measurementTask?.cancel()
        isMeasuring = false
        completeSession()
    }

    /// Aborta e descarta a sessão ativa
    public func cancelSession() {
        measurementTask?.cancel()
        isMeasuring = false
        onFinished?()
    }

    // MARK: - Conclusão e Cálculo do Resumo Residencial

    private func completeSession() {
        var updatedRooms: [Room] = []
        var excellentCount = 0
        var goodCount = 0
        var fairCount = 0
        var poorCount = 0

        for room in session.rooms {
            var r = room
            if let m = session.completedMeasurements[room.id] {
                r.lastMeasurement = m
                switch m.rating {
                case .excellent: excellentCount += 1
                case .good: goodCount += 1
                case .fair: fairCount += 1
                case .poor: poorCount += 1
                case .unmeasured: break
                }
            }
            updatedRooms.append(r)
        }

        let coverageScore = SpatialLayoutEngine.calculateHouseCoverage(rooms: updatedRooms)

        // Verificação do modo comparativo Antes × Depois
        var baselineCoverage: Int? = nil
        var deltaScore: Int? = nil

        if session.mode == .comparison {
            if let baselineRooms = dataStore.fetchActiveComparisonBaseline() {
                let comparison = SpatialLayoutEngine.generateComparison(
                    title: "Comparativo de Cobertura",
                    baselineRooms: baselineRooms,
                    afterRooms: updatedRooms
                )
                dataStore.saveComparison(comparison)
                baselineCoverage = comparison.baselineCoveragePercent
                deltaScore = comparison.deltaCoveragePercent
            }
        }

        let summary = WalkSessionSummary(
            houseCoverageScore: coverageScore,
            baselineCoverageScore: baselineCoverage,
            deltaScore: deltaScore,
            measuredRoomsCount: session.completedMeasurements.count,
            skippedRoomsCount: session.skippedRoomIds.count,
            totalRoomsCount: session.rooms.count,
            excellentCount: excellentCount,
            goodCount: goodCount,
            fairCount: fairCount,
            poorCount: poorCount,
            detectedAccessPointsCount: max(1, session.detectedBSSIDs.count),
            measuredRooms: updatedRooms,
            mode: session.mode
        )

        state = .sessionSummary(summary: summary)
    }
}
