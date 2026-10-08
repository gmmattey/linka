import Foundation
import Combine
import NetworkCore
import NetworkInsights
import NetworkOptimization
import NetworkProfiles
import NetworkInventory

/// Coordena a associação explícita e local entre o resultado aberto e um
/// ambiente. SSID é só uma pré-condição efêmera: nunca é persistido nem usado
/// como chave de ambiente.
@MainActor
final class OptimizationProfileCoordinator: ObservableObject {
    enum CurrentNetworkState: Equatable { case identificationDisabled, notWiFi, ssidUnavailable, available }
    enum ReferenceState: Equatable { case building(sampleCount: Int), ready(sampleCount: Int) }

    @Published private(set) var environments: [NetworkEnvironment] = []
    @Published private(set) var currentNetworkState: CurrentNetworkState = .notWiFi
    @Published private(set) var currentAssignment: EnvironmentMeasurementAssignment?
    @Published private(set) var referenceSampleCounts: [UUID: Int] = [:]
    @Published private(set) var readyEnvironmentIDs: Set<UUID> = []
    @Published private(set) var currentComparisons: [UUID: [MetricComparison]] = [:]
    @Published private(set) var hasStoreError = false
    @Published private(set) var partialRemoval = false

    private let repository: any NetworkProfileRepository
    private var storeObserver: AnyCancellable?
    private var measurements: [NetworkMeasurement] = []
    private var currentMeasurement: NetworkMeasurement?
    private var assignmentsByMeasurementID: [UUID: EnvironmentMeasurementAssignment] = [:]

    init(repository: (any NetworkProfileRepository)? = nil) {
        self.repository = repository ?? LinkaHousehold.repository
        storeObserver = NotificationCenter.default.publisher(for: LinkaHousehold.didChange)
            .sink { [weak self] _ in Task { @MainActor [weak self] in await self?.loadStore() } }
    }

    func refresh(currentMeasurement: NetworkMeasurement, history: [NetworkMeasurement]) async {
        measurements = Array(Set(history + [currentMeasurement]))
        self.currentMeasurement = currentMeasurement
        currentNetworkState = networkState(for: currentMeasurement)
        await loadStore()
    }

    func retryStoreAccess() async { partialRemoval = false; await loadStore() }
    func loadEnvironments() async { await loadStore() }

    func assignCurrentMeasurement(to environment: NetworkEnvironment) async -> Bool {
        guard canAssignCurrentMeasurement, let currentMeasurement else { return false }
        do {
            try await repository.assign(measurementID: currentMeasurement.id, to: environment.id, assignedAt: Date())
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await loadStore()
            return true
        } catch { hasStoreError = true; return false }
    }

    func createAndAssignCurrentMeasurement(named name: String) async -> Bool {
        guard canAssignCurrentMeasurement, let currentMeasurement, let environment = NetworkEnvironment(name: name) else { return false }
        do {
            try await repository.createAndAssign(environment, measurementID: currentMeasurement.id, assignedAt: Date())
            NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil)
            await loadStore()
            return true
        } catch { hasStoreError = true; return false }
    }

    func rename(_ environment: NetworkEnvironment, to name: String) async -> Bool {
        do { try await repository.rename(id: environment.id, to: name, updatedAt: Date()); NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil); await loadStore(); return true }
        catch { hasStoreError = true; return false }
    }

    func remove(_ environment: NetworkEnvironment) async -> Bool {
        partialRemoval = false
        do { try await repository.remove(id: environment.id); NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil); await loadStore(); return true }
        catch {
            partialRemoval = (error as? NetworkInventoryError) == .partialEnvironmentRemoval
            if partialRemoval { NotificationCenter.default.post(name: LinkaHousehold.didChange, object: nil) }
            hasStoreError = true; return false
        }
    }

    func referenceState(for environment: NetworkEnvironment) -> ReferenceState {
        let count = referenceSampleCounts[environment.id, default: 0]
        return readyEnvironmentIDs.contains(environment.id) ? .ready(sampleCount: count) : .building(sampleCount: count)
    }

    func comparison(for environment: NetworkEnvironment) -> [MetricComparison]? { currentComparisons[environment.id] }

    var canAssignCurrentMeasurement: Bool {
        guard currentMeasurement?.outcome == .complete else { return false }
        if case .available = currentNetworkState { return true }
        return false
    }

    private func loadStore() async {
        do {
            environments = try await repository.environments()
            var assignments: [UUID: EnvironmentMeasurementAssignment] = [:]
            for environment in environments {
                for assignment in try await repository.assignments(for: environment.id) { assignments[assignment.measurementID] = assignment }
            }
            assignmentsByMeasurementID = assignments
            currentAssignment = currentMeasurement.flatMap { assignments[$0.id] }
            hasStoreError = false
            recalculateReferenceStates()
        } catch { hasStoreError = true }
    }

    private func recalculateReferenceStates() {
        let now = Date()
        let assignments = assignmentsByMeasurementID
        let builder = NetworkBaselineBuilder { assignments[$0.id]?.environmentID.uuidString }
        let comparator = NetworkBaselineComparator { assignments[$0.id]?.environmentID.uuidString }
        var counts: [UUID: Int] = [:]
        var ready: Set<UUID> = []
        var comparisons: [UUID: [MetricComparison]] = [:]
        for environment in environments {
            let identity = environment.id.uuidString
            let assigned = measurements.filter {
                assignments[$0.id]?.environmentID == environment.id && $0.outcome == .complete && $0.connectionKind == .wifi &&
                $0.measuredAt >= now.addingTimeInterval(-30 * 24 * 60 * 60) && $0.measuredAt <= now
            }
            counts[environment.id] = assigned.count
            guard let baseline = builder.build(profileIdentity: identity, measurements: assigned.filter { $0.id != currentMeasurement?.id }, referenceDate: now) else { continue }
            ready.insert(environment.id)
            guard currentAssignment?.environmentID == environment.id, let currentMeasurement,
                  case .compared(let result) = comparator.compare(current: currentMeasurement, against: baseline) else { continue }
            comparisons[environment.id] = result.metrics
        }
        referenceSampleCounts = counts
        readyEnvironmentIDs = ready
        currentComparisons = comparisons
    }

    private func networkState(for measurement: NetworkMeasurement) -> CurrentNetworkState {
        guard LinkaWiFiPreferences.isIdentificationEnabled else { return .identificationDisabled }
        guard measurement.connectionKind == .wifi else { return .notWiFi }
        guard let ssid = measurement.wifiContext?.ssid, !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .ssidUnavailable }
        return .available
    }

    private static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Linka", isDirectory: true).appendingPathComponent("network-profiles-v1.json")
    }
}
