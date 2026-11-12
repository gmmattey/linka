import Foundation

/// Repositório local de perfis com documento JSON versionado.
///
/// Falhas de leitura e versões desconhecidas não são recuperadas nem
/// sobrescritas: o repositório falha fechado para preservar o documento.
public actor FileNetworkProfileRepository: NetworkProfileRepository {
    public static let storeSchemaVersion = 2

    private struct StoreDocument: Codable {
        let schemaVersion: Int
        let environments: [NetworkEnvironment]
        let assignments: [EnvironmentMeasurementAssignment]
    }

    private struct LegacyStoreDocument: Decodable {
        let schemaVersion: Int
        let profiles: [LegacyProfile]
    }

    /// Só existe para migrar schema 1. `identity` e referências legadas são
    /// propositalmente ignoradas e portanto não alcançam o schema 2.
    private struct LegacyProfile: Decodable {
        let id: UUID
        let name: String
        let createdAt: Date
        let updatedAt: Date
    }

    private let fileURL: URL
    private var hasLoaded = false
    private var storedEnvironments: [NetworkEnvironment] = []
    private var storedAssignments: [EnvironmentMeasurementAssignment] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func environments() async throws -> [NetworkEnvironment] {
        try loadIfNeeded()
        return storedEnvironments.sorted(by: Self.sortEnvironments)
    }

    public func environment(id: UUID) async throws -> NetworkEnvironment? {
        try loadIfNeeded()
        return storedEnvironments.first { $0.id == id }
    }

    public func create(_ environment: NetworkEnvironment) async throws {
        try loadIfNeeded()
        guard !storedEnvironments.contains(where: { $0.id == environment.id }) else {
            throw NetworkProfileRepositoryError.corruptedStore
        }
        var updated = storedEnvironments
        updated.append(environment)
        try persist(environments: updated, assignments: storedAssignments)
        storedEnvironments = updated
    }

    public func rename(id: UUID, to name: String, updatedAt: Date) async throws {
        try loadIfNeeded()
        guard let old = storedEnvironments.first(where: { $0.id == id }),
              let renamed = NetworkEnvironment(id: old.id, name: name, createdAt: old.createdAt, updatedAt: updatedAt) else {
            throw NetworkProfileRepositoryError.corruptedStore
        }
        let updated = storedEnvironments.map { $0.id == id ? renamed : $0 }
        try persist(environments: updated, assignments: storedAssignments)
        storedEnvironments = updated
    }

    public func remove(id: UUID) async throws {
        try loadIfNeeded()
        let environments = storedEnvironments.filter { $0.id != id }
        guard environments.count != storedEnvironments.count else { return }
        let assignments = storedAssignments.filter { $0.environmentID != id }
        try persist(environments: environments, assignments: assignments)
        storedEnvironments = environments
        storedAssignments = assignments
    }

    public func assignment(for measurementID: UUID) async throws -> EnvironmentMeasurementAssignment? {
        try loadIfNeeded()
        return storedAssignments.first { $0.measurementID == measurementID }
    }

    public func assignments(for environmentID: UUID) async throws -> [EnvironmentMeasurementAssignment] {
        try loadIfNeeded()
        return storedAssignments.filter { $0.environmentID == environmentID }
    }

    public func assign(measurementID: UUID, to environmentID: UUID, assignedAt: Date) async throws {
        try loadIfNeeded()
        guard storedEnvironments.contains(where: { $0.id == environmentID }) else {
            throw NetworkProfileRepositoryError.corruptedStore
        }
        let assignment = EnvironmentMeasurementAssignment(measurementID: measurementID, environmentID: environmentID, assignedAt: assignedAt)
        let assignments = storedAssignments.filter { $0.measurementID != measurementID } + [assignment]
        try persist(environments: storedEnvironments, assignments: assignments)
        storedAssignments = assignments
    }

    public func createAndAssign(_ environment: NetworkEnvironment, measurementID: UUID, assignedAt: Date) async throws {
        try loadIfNeeded()
        guard !storedEnvironments.contains(where: { $0.id == environment.id }) else {
            throw NetworkProfileRepositoryError.corruptedStore
        }
        let environments = storedEnvironments + [environment]
        let assignment = EnvironmentMeasurementAssignment(measurementID: measurementID, environmentID: environment.id, assignedAt: assignedAt)
        let assignments = storedAssignments.filter { $0.measurementID != measurementID } + [assignment]
        try persist(environments: environments, assignments: assignments)
        storedEnvironments = environments
        storedAssignments = assignments
    }

    private func loadIfNeeded() throws {
        guard !hasLoaded else { return }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            storedEnvironments = []
            storedAssignments = []
            hasLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .deferredToDate
            let version = try decoder.decode(VersionDocument.self, from: data).schemaVersion
            switch version {
            case Self.storeSchemaVersion:
                let document = try decoder.decode(StoreDocument.self, from: data)
                try validate(document.environments, assignments: document.assignments)
                storedEnvironments = document.environments.sorted(by: Self.sortEnvironments)
                storedAssignments = document.assignments
            case 1:
                let legacy = try decoder.decode(LegacyStoreDocument.self, from: data)
                guard legacy.schemaVersion == 1 else { throw NetworkProfileRepositoryError.corruptedStore }
                let environments = try legacy.profiles.map { legacy -> NetworkEnvironment in
                    guard let environment = NetworkEnvironment(id: legacy.id, name: legacy.name, createdAt: legacy.createdAt, updatedAt: legacy.updatedAt) else {
                        throw NetworkProfileRepositoryError.corruptedStore
                    }
                    return environment
                }
                try validate(environments, assignments: [])
                // A escrita atômica só acontece depois de toda a migração ter
                // sido validada; se falhar, o arquivo schema 1 fica intacto.
                try persist(environments: environments, assignments: [])
                storedEnvironments = environments.sorted(by: Self.sortEnvironments)
                storedAssignments = []
            default:
                throw NetworkProfileRepositoryError.unsupportedStoreVersion(version)
            }
            hasLoaded = true
        } catch let error as NetworkProfileRepositoryError {
            throw error
        } catch {
            throw NetworkProfileRepositoryError.corruptedStore
        }
    }

    private struct VersionDocument: Decodable { let schemaVersion: Int }

    private func validate(_ environments: [NetworkEnvironment], assignments: [EnvironmentMeasurementAssignment]) throws {
        guard Set(environments.map(\.id)).count == environments.count,
              Set(assignments.map(\.measurementID)).count == assignments.count,
              assignments.allSatisfy({ assignment in environments.contains(where: { $0.id == assignment.environmentID }) }) else {
            throw NetworkProfileRepositoryError.corruptedStore
        }
    }

    private func persist(environments: [NetworkEnvironment], assignments: [EnvironmentMeasurementAssignment]) throws {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .deferredToDate
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(StoreDocument(
                schemaVersion: Self.storeSchemaVersion,
                environments: environments.sorted(by: Self.sortEnvironments),
                assignments: assignments.sorted { $0.measurementID.uuidString < $1.measurementID.uuidString }
            ))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw NetworkProfileRepositoryError.persistenceFailed
        }
    }

    private static func sortEnvironments(_ lhs: NetworkEnvironment, _ rhs: NetworkEnvironment) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}
