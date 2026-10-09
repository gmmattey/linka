import Foundation
import NetworkProfiles
/// All app access to these stores goes through this coordinator. The FIFO lock spans awaits.
public actor HouseholdRepository: NetworkProfileRepository {
    private let profiles: any NetworkProfileRepository
    private let inventory: any NetworkInventoryRepository
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public init(profiles: any NetworkProfileRepository, inventory: any NetworkInventoryRepository) { self.profiles = profiles; self.inventory = inventory }
    private func acquire() async { if !locked { locked = true; return }; await withCheckedContinuation { waiters.append($0) } }
    private func release() { if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() } }
    public func devices() async throws -> [RegisteredNetworkDevice] {
        await acquire(); defer { release() }; try Task.checkCancellation()
        var devices = try await inventory.devices()
        for index in devices.indices {
            if let id = devices[index].installation.environmentID, try await profiles.environment(id: id) == nil {
                try await inventory.unlinkEnvironment(id: id, preservingLabel: nil)
                devices = try await inventory.devices()
            }
        }
        return devices
    }
    public func device(id: UUID) async throws -> RegisteredNetworkDevice? { try await devices().first { $0.id == id } }
    @discardableResult public func saveDevice(_ device: RegisteredNetworkDevice, expectedRevision: Int? = nil) async throws -> RegisteredNetworkDevice {
        await acquire(); defer { release() }; try Task.checkCancellation()
        var value = device
        if let id = value.installation.environmentID {
            guard let environment = try await profiles.environment(id: id) else { throw NetworkInventoryError.invalidDevice }
            value.installation.locationLabel = environment.name
        }
        return try await inventory.save(value, expectedRevision: expectedRevision)
    }
    public func removeDevice(id: UUID, expectedRevision: Int) async throws { await acquire(); defer { release() }; try Task.checkCancellation(); try await inventory.remove(id: id, expectedRevision: expectedRevision) }

    // MARK: - Plans

    public func plans() async throws -> [NetworkServicePlan] {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.plans()
    }

    public func plan(id: UUID) async throws -> NetworkServicePlan? {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.plan(id: id)
    }

    @discardableResult
    public func savePlan(_ plan: NetworkServicePlan) async throws -> NetworkServicePlan {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.savePlan(plan)
    }

    public func removePlan(id: UUID) async throws {
        await acquire(); defer { release() }; try Task.checkCancellation()
        try await inventory.removePlan(id: id)
    }

    // MARK: - Connections

    public func connections() async throws -> [DeviceConnection] {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.connections()
    }

    public func connection(id: UUID) async throws -> DeviceConnection? {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.connection(id: id)
    }

    public func connections(forDevice id: UUID) async throws -> [DeviceConnection] {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.connections(forDevice: id)
    }

    @discardableResult
    public func saveConnection(_ connection: DeviceConnection) async throws -> DeviceConnection {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.saveConnection(connection)
    }

    public func removeConnection(id: UUID) async throws {
        await acquire(); defer { release() }; try Task.checkCancellation()
        try await inventory.removeConnection(id: id)
    }

    // MARK: - Home Profile

    public func homeProfile() async throws -> HomeNetworkProfile? {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.homeProfile()
    }

    @discardableResult
    public func saveHomeProfile(_ profile: HomeNetworkProfile) async throws -> HomeNetworkProfile {
        await acquire(); defer { release() }; try Task.checkCancellation()
        return try await inventory.saveHomeProfile(profile)
    }

    public func environments() async throws -> [NetworkEnvironment] { await acquire(); defer { release() }; return try await profiles.environments() }
    public func environment(id: UUID) async throws -> NetworkEnvironment? { await acquire(); defer { release() }; return try await profiles.environment(id: id) }
    public func create(_ environment: NetworkEnvironment) async throws { await acquire(); defer { release() }; try Task.checkCancellation(); try await profiles.create(environment) }
    public func rename(id: UUID, to name: String, updatedAt: Date) async throws { await acquire(); defer { release() }; try Task.checkCancellation(); try await profiles.rename(id: id, to: name, updatedAt: updatedAt) }
    public func remove(id: UUID) async throws {
        await acquire(); defer { release() }; try Task.checkCancellation()
        let name = try await profiles.environment(id: id)?.name
        try await inventory.unlinkEnvironment(id: id, preservingLabel: name)
        do { try await profiles.remove(id: id) }
        catch { throw NetworkInventoryError.partialEnvironmentRemoval }
    }
    public func assignment(for measurementID: UUID) async throws -> EnvironmentMeasurementAssignment? { await acquire(); defer { release() }; return try await profiles.assignment(for: measurementID) }
    public func assignments(for environmentID: UUID) async throws -> [EnvironmentMeasurementAssignment] { await acquire(); defer { release() }; return try await profiles.assignments(for: environmentID) }
    public func assign(measurementID: UUID, to environmentID: UUID, assignedAt: Date) async throws { await acquire(); defer { release() }; try Task.checkCancellation(); try await profiles.assign(measurementID: measurementID, to: environmentID, assignedAt: assignedAt) }
    public func createAndAssign(_ environment: NetworkEnvironment, measurementID: UUID, assignedAt: Date) async throws { await acquire(); defer { release() }; try Task.checkCancellation(); try await profiles.createAndAssign(environment, measurementID: measurementID, assignedAt: assignedAt) }
}
