import Foundation
import SwiftUI
import Combine

// MARK: - Máquina de Estados da Jornada Principal (Smart CTA & Flow)

public enum HomeJourneyState: Equatable, Sendable {
    case notStarted(firstRoom: Room)
    case inProgress(nextRoom: Room, measuredCount: Int, totalRooms: Int)
    case needsOptimization(roomsNeedingFix: [Room])
    case fullyOptimized
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var house: House
    @Published public var selectedRoom: Room?
    @Published public var activeMeasuringRoom: Room?
    @Published public var currentStep: DiagnosticStep = .verifyingWiFi
    @Published public var measurementProgress: Double = 0.0
    @Published public var isMeasuring: Bool = false
    @Published public var lastFinishedResult: MeasurementResult?

    @Published public var showMeasurementSheet: Bool = false
    @Published public var showDetailSheet: Bool = false
    @Published public var showRoomEditorSheet: Bool = false
    @Published public var showBeforeAfterSheet: Bool = false
    @Published public var showHistorySheet: Bool = false
    @Published public var showPaywallSheet: Bool = false
    @Published public var showHelpSheet: Bool = false
    @Published public var showAccessPointsSheet: Bool = false
    @Published public var showWalkSessionSheet: Bool = false
    @Published public var walkSessionMode: WalkSessionMode = .regular
    @Published public var activeProblemCase: HomeProblemCase? = nil
    @Published public var showProblemDiagnosticSheet: Bool = false
    @Published public var errorMessage: String?
    @Published public var lastDiagnosticError: DiagnosticError? = nil
    @Published public var activeComparisonBaseline: [Room]?
    @Published public var lastHandoffEvent: AccessPointHandoffEvent?
    @Published public var isOnboardingDismissed: Bool {
        didSet {
            userDefaults.set(isOnboardingDismissed, forKey: "LinkaApp.spatialOnboardingDismissed")
        }
    }

    public let dataStore: DataStore
    public let diagnosticEngine: WiFiDiagnosticEngine
    public let networkMonitor: NetworkMonitorService
    public let apTracker: AccessPointTracker
    private let userDefaults: UserDefaults

    public var detectedAccessPoints: [DetectedAccessPoint] {
        apTracker.detectedAccessPoints
    }

    public var hasMultipleAccessPoints: Bool {
        detectedAccessPoints.count >= 2
    }

    public static let sheetTransitionDelayNanoseconds: UInt64 = 400_000_000
    public static let networkStabilizationDelayNanoseconds: UInt64 = 500_000_000

    private var measurementTask: Task<Void, Never>?
    private var stabilizationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var wasInterruptedBySystem: Bool = false
    private var activeWalkSessionViewModel: WalkSessionViewModel?

    public var isPermissionDeniedError: Bool {
        if lastDiagnosticError == .localNetworkPermissionDenied {
            return true
        }
        if let errorMessage {
            return errorMessage.contains("Ajustes") || errorMessage.contains("Rede Local") || errorMessage.contains("autorização")
        }
        return false
    }

    public init(
        dataStore: DataStore? = nil,
        diagnosticEngine: WiFiDiagnosticEngine = .shared,
        networkMonitor: NetworkMonitorService? = nil,
        apTracker: AccessPointTracker = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        let store = dataStore ?? DataStore()
        let monitor = networkMonitor ?? NetworkMonitorService.shared
        self.dataStore = store
        self.diagnosticEngine = diagnosticEngine
        self.networkMonitor = monitor
        self.apTracker = apTracker
        self.userDefaults = userDefaults
        self.house = store.fetchOrCreateDefaultHouse()
        self.activeComparisonBaseline = store.fetchActiveComparisonBaseline()
        self.isOnboardingDismissed = userDefaults.bool(forKey: "WiFiCheck.onboardingDismissed")

        // Sincroniza APs com o histórico salvo da residência
        apTracker.syncWithHouse(self.house)

        // Monitora queda de conexão Wi-Fi durante medição ativa
        monitor.$isWiFiConnected
            .dropFirst()
            .sink { [weak self] isWiFi in
                guard let self else { return }
                if !isWiFi && self.isMeasuring {
                    self.cancelMeasurement(reason: DiagnosticError.measurementAborted.localizedDescription)
                }
            }
            .store(in: &cancellables)

        #if os(iOS)
        // Monitora perda de foco provocada por diálogos de sistema (ex: prompt de permissão de Rede Local)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isMeasuring {
                    self.wasInterruptedBySystem = true
                    // Cancela temporariamente a task para que nenhum probe seja executado em background
                    self.measurementTask?.cancel()
                    self.measurementTask = nil
                    self.currentStep = .waitingForPermission
                }
            }
            .store(in: &cancellables)

        // Ao retornar ao primeiro plano, se a medição foi pausada pela permissão, reinicia de forma limpa
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.wasInterruptedBySystem && self.isMeasuring, let room = self.activeMeasuringRoom {
                    self.wasInterruptedBySystem = false
                    self.restartMeasurementAfterInterruption(for: room)
                }
            }
            .store(in: &cancellables)
        #endif

        // Argumentos para capturas automatizadas de screenshots App Store
        if CommandLine.arguments.contains("--screen-measure") {
            let targetRoom = house.rooms.first(where: { $0.name.contains("Quarto") }) ?? house.rooms.first
            self.activeMeasuringRoom = targetRoom
            self.currentStep = .probingLAN
            self.measurementProgress = 0.62
            self.isMeasuring = true
            self.showMeasurementSheet = true
        } else if CommandLine.arguments.contains("--screen-detail") {
            let targetRoom = house.rooms.first(where: { $0.lastMeasurement?.rating == .poor }) ?? house.rooms.first
            self.selectedRoom = targetRoom
            self.showDetailSheet = true
        } else if CommandLine.arguments.contains("--screen-beforeafter") {
            self.showBeforeAfterSheet = true
        }
    }

    public var journeyState: HomeJourneyState {
        let rooms = house.rooms
        guard !rooms.isEmpty else {
            return .fullyOptimized
        }
        let measuredRooms = rooms.filter { $0.lastMeasurement != nil }
        let unmeasuredRooms = rooms.filter { $0.lastMeasurement == nil }

        if measuredRooms.isEmpty {
            let firstTarget = house.routerRoom ?? rooms[0]
            return .notStarted(firstRoom: firstTarget)
        }

        if let next = unmeasuredRooms.first {
            return .inProgress(nextRoom: next, measuredCount: measuredRooms.count, totalRooms: rooms.count)
        }

        let roomsWithIssues = rooms.filter { room in
            guard let m = room.lastMeasurement else { return false }
            return m.rating == .poor || m.rating == .fair || m.diagnosisTag.isIssue
        }

        if !roomsWithIssues.isEmpty {
            return .needsOptimization(roomsNeedingFix: roomsWithIssues)
        } else {
            return .fullyOptimized
        }
    }

    public func nextUnmeasuredRoom(excluding currentRoomId: UUID? = nil) -> Room? {
        house.rooms.first { room in
            if let currentRoomId, room.id == currentRoomId { return false }
            return room.lastMeasurement == nil
        }
    }

    public func dismissOnboarding() {
        self.isOnboardingDismissed = true
    }

    public func proceedToNextRoom(after currentRoom: Room) {
        guard let next = nextUnmeasuredRoom(excluding: currentRoom.id) else {
            showDetailSheet = false
            return
        }
        showDetailSheet = false

        stabilizationTask?.cancel()
        let targetRoomId = next.id
        // Guarda de estabilização de rede (500ms) para handoff Wi-Fi/mesh com task gerenciada e cancelável
        stabilizationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Self.networkStabilizationDelayNanoseconds)
            guard !Task.isCancelled else { return }
            // Revalida se o cômodo alvo ainda existe na residência após o delay
            guard let freshRoom = self.house.rooms.first(where: { $0.id == targetRoomId }) else { return }
            self.startMeasurement(for: freshRoom)
        }
    }

    public func reloadData() {
        self.house = dataStore.fetchOrCreateDefaultHouse()
        self.activeComparisonBaseline = dataStore.fetchActiveComparisonBaseline()
        self.apTracker.syncWithHouse(self.house)
    }

    public func apFriendlyLabel(for bssid: String?) -> String? {
        apTracker.label(for: bssid)
    }

    /// Inicia o ciclo de medição no cômodo especificado
    public func startProblemDiagnosis(_ problem: HomeProblemCase) {
        self.activeProblemCase = problem
        self.showProblemDiagnosticSheet = true
    }

    public func startMeasurement(for room: Room) {
        // Cancela qualquer transição de estabilização pendente
        stabilizationTask?.cancel()
        stabilizationTask = nil

        guard networkMonitor.isWiFiConnected else {
            self.errorMessage = DiagnosticError.notConnectedToWiFi.localizedDescription
            return
        }

        self.activeMeasuringRoom = room
        self.currentStep = .verifyingWiFi
        self.measurementProgress = 0.0
        self.isMeasuring = true
        self.errorMessage = nil
        self.wasInterruptedBySystem = false
        self.showMeasurementSheet = true

        executeMeasurementTask(for: room)
    }

    /// Reinicia a medição de forma limpa caso tenha sido pausada por prompt de permissão do sistema
    public func restartMeasurementAfterInterruption(for room: Room) {
        measurementTask?.cancel()
        measurementTask = nil
        self.currentStep = .checkingLocalNetwork
        self.measurementProgress = 0.0
        self.errorMessage = nil

        // Aguarda estabilização de rede no subsistema do iOS pós-fechamento de modal
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, self.isMeasuring, self.activeMeasuringRoom?.id == room.id else { return }
            self.executeMeasurementTask(for: room)
        }
    }

    private func executeMeasurementTask(for room: Room) {
        measurementTask?.cancel()
        measurementTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.diagnosticEngine.performMeasurement(
                    for: room.id,
                    isRouterRoom: room.hasRouter,
                    progressHandler: { [weak self] step, progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.isMeasuring, self.activeMeasuringRoom?.id == room.id else { return }
                            self.currentStep = step
                            self.measurementProgress = progress
                        }
                    }
                )

                if !Task.isCancelled {
                    let (_, handoff) = self.apTracker.registerMeasurement(result: result, roomName: room.name)
                    self.lastHandoffEvent = handoff
                    self.dataStore.saveMeasurement(result, for: room.id)
                    self.dismissOnboarding()
                    self.reloadData()
                    self.lastFinishedResult = result
                    self.isMeasuring = false

                    // Aguarda delay de 400ms para permitir visualização da conclusão antes da troca de sheet
                    try? await Task.sleep(nanoseconds: Self.sheetTransitionDelayNanoseconds)
                    self.showMeasurementSheet = false
                    self.showDetailSheet = true
                }
            } catch {
                if !Task.isCancelled {
                    self.isMeasuring = false
                    self.activeMeasuringRoom = nil
                    self.showMeasurementSheet = false
                    if let diagError = error as? DiagnosticError {
                        self.lastDiagnosticError = diagError
                    } else {
                        self.lastDiagnosticError = nil
                    }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func cancelMeasurement(reason: String? = nil) {
        stabilizationTask?.cancel()
        stabilizationTask = nil
        measurementTask?.cancel()
        measurementTask = nil
        isMeasuring = false
        activeMeasuringRoom = nil
        showMeasurementSheet = false
        if let reason {
            self.errorMessage = reason
            if reason.contains("Rede Local") || reason.contains("Ajustes") {
                self.lastDiagnosticError = .localNetworkPermissionDenied
            } else {
                self.lastDiagnosticError = nil
            }
        } else {
            self.lastDiagnosticError = nil
        }
    }

    /// Executa medição simulada (útil para testes em simulador ou demonstração rápida)
    public func runSimulatedMeasurement(
        for room: Room,
        rating: QualityRating = .good,
        bssid: String? = nil,
        ssid: String? = nil
    ) {
        let simulated = diagnosticEngine.createSimulatedMeasurement(
            roomId: room.id,
            rating: rating,
            isRouterRoom: room.hasRouter,
            bssid: bssid,
            ssid: ssid
        )
        let (_, handoff) = self.apTracker.registerMeasurement(result: simulated, roomName: room.name)
        self.lastHandoffEvent = handoff
        dataStore.saveMeasurement(simulated, for: room.id)
        dismissOnboarding()
        reloadData()
        self.lastFinishedResult = simulated
        self.selectedRoom = house.rooms.first(where: { $0.id == room.id })
        self.showDetailSheet = true
    }

    public func updateRooms(_ updatedRooms: [Room]) {
        dataStore.saveRooms(updatedRooms, for: house.id)
        reloadData()
    }

    public func recommendations() -> [String] {
        SpatialLayoutEngine.generateRecommendations(rooms: house.rooms)
    }

    // MARK: - Modo Caminhada Contínuo (Walk Mode)

    public func startWalkSession(mode: WalkSessionMode = .regular) {
        self.walkSessionMode = mode
        self.showWalkSessionSheet = true
    }

    /// Reaproveita a mesma instância enquanto a caminhada estiver ativa — o closure de conteúdo do
    /// `.fullScreenCover(isPresented:)` pode ser reavaliado a cada atualização do HomeView, e criar
    /// um novo WalkSessionViewModel a cada chamada descartaria silenciosamente o progresso da caminhada.
    public func createWalkSessionViewModel() -> WalkSessionViewModel {
        if let existing = activeWalkSessionViewModel {
            return existing
        }

        let mode = self.walkSessionMode
        let viewModel = WalkSessionViewModel(
            rooms: house.rooms,
            mode: mode,
            dataStore: dataStore,
            diagnosticEngine: diagnosticEngine,
            onFinished: { [weak self] in
                guard let self else { return }
                self.reloadData()
                self.showWalkSessionSheet = false
                self.activeWalkSessionViewModel = nil
            }
        )
        activeWalkSessionViewModel = viewModel
        return viewModel
    }
}
