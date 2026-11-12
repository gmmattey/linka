import Foundation

public protocol NetworkProfileRepository: Sendable {
    func environments() async throws -> [NetworkEnvironment]
    func environment(id: UUID) async throws -> NetworkEnvironment?
    func create(_ environment: NetworkEnvironment) async throws
    func rename(id: UUID, to name: String, updatedAt: Date) async throws
    func remove(id: UUID) async throws
    func assignment(for measurementID: UUID) async throws -> EnvironmentMeasurementAssignment?
    func assignments(for environmentID: UUID) async throws -> [EnvironmentMeasurementAssignment]
    func assign(measurementID: UUID, to environmentID: UUID, assignedAt: Date) async throws
    func createAndAssign(_ environment: NetworkEnvironment, measurementID: UUID, assignedAt: Date) async throws
}

public enum NetworkProfileRepositoryError: Error, Equatable, Sendable {
    case corruptedStore
    case unsupportedStoreVersion(Int)
    case persistenceFailed
}
