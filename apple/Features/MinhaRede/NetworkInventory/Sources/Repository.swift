import Foundation

public enum NetworkInventoryError: Error, Equatable {
    case partialEnvironmentRemoval
    case invalidDevice
    case invalidPlan
    case invalidConnection
    case invalidProfile
    case duplicateConnection
    case conflict
    case notFound
    case corruptedStore
    case unsupportedSchema(Int)
    case persistenceFailed
    case invalidResponse
    case unavailable
}

public protocol NetworkInventoryRepository: Sendable {
    func devices() async throws -> [RegisteredNetworkDevice]
    func device(id: UUID) async throws -> RegisteredNetworkDevice?
    func save(_ device: RegisteredNetworkDevice, expectedRevision: Int?) async throws -> RegisteredNetworkDevice
    func remove(id: UUID, expectedRevision: Int) async throws
    func unlinkEnvironment(id: UUID, preservingLabel: String?) async throws

    // Planos
    func plans() async throws -> [NetworkServicePlan]
    func plan(id: UUID) async throws -> NetworkServicePlan?
    func savePlan(_ plan: NetworkServicePlan) async throws -> NetworkServicePlan
    func removePlan(id: UUID) async throws

    // Conexões
    func connections() async throws -> [DeviceConnection]
    func connection(id: UUID) async throws -> DeviceConnection?
    func connections(forDevice id: UUID) async throws -> [DeviceConnection]
    func saveConnection(_ connection: DeviceConnection) async throws -> DeviceConnection
    func removeConnection(id: UUID) async throws

    // Perfil Doméstico
    func homeProfile() async throws -> HomeNetworkProfile?
    func saveHomeProfile(_ profile: HomeNetworkProfile) async throws -> HomeNetworkProfile
}

/// Compose a single instance per file. A schema mismatch or unreadable document is never overwritten.
public actor FileNetworkInventoryRepository: NetworkInventoryRepository {
    private struct DocumentV2: Codable {
        var schemaVersion: Int
        var devices: [RegisteredNetworkDevice]
        var profiles: [HomeNetworkProfile]
        var plans: [NetworkServicePlan]
        var connections: [DeviceConnection]
    }

    private struct DocumentV1: Decodable {
        var schemaVersion: Int
        var devices: [RegisteredNetworkDevice]
    }

    private struct VersionHeader: Decodable {
        var schemaVersion: Int
    }

    private let fileURL: URL
    private var document: DocumentV2?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Devices

    public func devices() throws -> [RegisteredNetworkDevice] {
        try load().devices.sorted { $0.createdAt < $1.createdAt }
    }

    public func device(id: UUID) throws -> RegisteredNetworkDevice? {
        try load().devices.first { $0.id == id }
    }

    @discardableResult
    public func save(_ device: RegisteredNetworkDevice, expectedRevision: Int? = nil) throws -> RegisteredNetworkDevice {
        var current = try load()
        try Self.validate(device)
        var saved = device
        if let index = current.devices.firstIndex(where: { $0.id == device.id }) {
            let previous = current.devices[index]
            guard expectedRevision == previous.revision, previous.revision < Int.max else {
                throw NetworkInventoryError.conflict
            }
            saved.revision = previous.revision + 1
            saved.createdAt = previous.createdAt
            saved.updatedAt = Date()
            current.devices[index] = saved
        } else {
            guard expectedRevision == nil else {
                throw NetworkInventoryError.notFound
            }
            saved.revision = 1
            saved.updatedAt = Date()
            current.devices.append(saved)
        }
        try persist(current)
        return saved
    }

    public func remove(id: UUID, expectedRevision: Int) throws {
        var current = try load()
        guard let existing = current.devices.first(where: { $0.id == id }) else {
            throw NetworkInventoryError.notFound
        }
        guard existing.revision == expectedRevision else {
            throw NetworkInventoryError.conflict
        }
        current.devices.removeAll { $0.id == id }
        // Cascata atômica: remove todas as conexões vinculadas a este nó
        current.connections.removeAll { $0.endpointADeviceID == id || $0.endpointBDeviceID == id }
        try persist(current)
    }

    public func unlinkEnvironment(id: UUID, preservingLabel: String? = nil) throws {
        var current = try load()
        var changed = false
        for index in current.devices.indices where current.devices[index].installation.environmentID == id {
            guard current.devices[index].revision < Int.max else {
                throw NetworkInventoryError.conflict
            }
            current.devices[index].installation.environmentID = nil
            if let preservingLabel {
                current.devices[index].installation.locationLabel = preservingLabel
            }
            current.devices[index].revision += 1
            current.devices[index].updatedAt = Date()
            changed = true
        }
        if changed {
            try persist(current)
        }
    }

    // MARK: - Plans

    public func plans() throws -> [NetworkServicePlan] {
        try load().plans.sorted { $0.createdAt < $1.createdAt }
    }

    public func plan(id: UUID) throws -> NetworkServicePlan? {
        try load().plans.first { $0.id == id }
    }

    @discardableResult
    public func savePlan(_ plan: NetworkServicePlan) throws -> NetworkServicePlan {
        var current = try load()
        guard plan.isValid else {
            throw NetworkInventoryError.invalidPlan
        }
        var saved = plan
        if let index = current.plans.firstIndex(where: { $0.id == plan.id }) {
            saved.updatedAt = Date()
            current.plans[index] = saved
        } else {
            saved.updatedAt = Date()
            current.plans.append(saved)
        }
        try persist(current)
        return saved
    }

    public func removePlan(id: UUID) throws {
        var current = try load()
        guard current.plans.contains(where: { $0.id == id }) else {
            throw NetworkInventoryError.notFound
        }
        current.plans.removeAll { $0.id == id }
        // Cascata atômica: desassocia de perfis que apontavam para este plano
        for index in current.profiles.indices where current.profiles[index].activePlanID == id {
            current.profiles[index].activePlanID = nil
            current.profiles[index].updatedAt = Date()
        }
        try persist(current)
    }

    // MARK: - Connections

    public func connections() throws -> [DeviceConnection] {
        try load().connections.sorted { $0.createdAt < $1.createdAt }
    }

    public func connection(id: UUID) throws -> DeviceConnection? {
        try load().connections.first { $0.id == id }
    }

    public func connections(forDevice id: UUID) throws -> [DeviceConnection] {
        try load().connections.filter { $0.endpointADeviceID == id || $0.endpointBDeviceID == id }.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func saveConnection(_ connection: DeviceConnection) throws -> DeviceConnection {
        var current = try load()
        guard connection.isValid else {
            throw NetworkInventoryError.invalidConnection
        }
        let deviceIDs = Set(current.devices.map(\.id))
        guard deviceIDs.contains(connection.endpointADeviceID),
              deviceIDs.contains(connection.endpointBDeviceID) else {
            throw NetworkInventoryError.invalidConnection
        }

        let linkKey = connection.normalizedLinkKey
        if let duplicate = current.connections.first(where: { $0.normalizedLinkKey == linkKey }) {
            guard duplicate.id == connection.id else {
                throw NetworkInventoryError.duplicateConnection
            }
        }

        var saved = connection
        if let index = current.connections.firstIndex(where: { $0.id == connection.id }) {
            saved.updatedAt = Date()
            current.connections[index] = saved
        } else {
            saved.updatedAt = Date()
            current.connections.append(saved)
        }
        try persist(current)
        return saved
    }

    public func removeConnection(id: UUID) throws {
        var current = try load()
        guard current.connections.contains(where: { $0.id == id }) else {
            throw NetworkInventoryError.notFound
        }
        current.connections.removeAll { $0.id == id }
        try persist(current)
    }

    // MARK: - Home Network Profile

    public func homeProfile() throws -> HomeNetworkProfile? {
        try load().profiles.first
    }

    @discardableResult
    public func saveHomeProfile(_ profile: HomeNetworkProfile) throws -> HomeNetworkProfile {
        var current = try load()
        guard profile.isValid else {
            throw NetworkInventoryError.invalidProfile
        }
        if let activePlanID = profile.activePlanID {
            guard current.plans.contains(where: { $0.id == activePlanID }) else {
                throw NetworkInventoryError.invalidProfile
            }
        }
        var saved = profile
        saved.updatedAt = Date()
        if let index = current.profiles.firstIndex(where: { $0.id == profile.id }) {
            current.profiles[index] = saved
        } else if !current.profiles.isEmpty {
            current.profiles[0] = saved
        } else {
            current.profiles.append(saved)
        }
        try persist(current)
        return saved
    }

    // MARK: - Validations

    private static func validate(_ device: RegisteredNetworkDevice) throws {
        guard (device.installation.role == .mainRouter) == (device.installation.mainRouterAnswer == .yes),
              device.identity.isValid,
              device.revision >= 0,
              (device.nickname?.count ?? 0) <= 200,
              (device.installation.locationLabel?.count ?? 0) <= 200 else {
            throw NetworkInventoryError.invalidDevice
        }
        if let snapshot = device.specifications {
            try snapshot.validate(for: device.identity)
        }
    }

    private static func validateDocumentV2(_ doc: DocumentV2) throws {
        guard doc.schemaVersion == 2 else { throw NetworkInventoryError.corruptedStore }

        let deviceIDs = Set(doc.devices.map(\.id))
        guard deviceIDs.count == doc.devices.count else { throw NetworkInventoryError.corruptedStore }
        for device in doc.devices {
            try validate(device)
            guard device.revision > 0 else { throw NetworkInventoryError.corruptedStore }
        }

        let planIDs = Set(doc.plans.map(\.id))
        guard planIDs.count == doc.plans.count else { throw NetworkInventoryError.corruptedStore }
        for plan in doc.plans {
            guard plan.isValid else { throw NetworkInventoryError.corruptedStore }
        }

        let profileIDs = Set(doc.profiles.map(\.id))
        guard profileIDs.count == doc.profiles.count else { throw NetworkInventoryError.corruptedStore }
        for profile in doc.profiles {
            guard profile.isValid else { throw NetworkInventoryError.corruptedStore }
            if let activePlanID = profile.activePlanID {
                guard planIDs.contains(activePlanID) else { throw NetworkInventoryError.corruptedStore }
            }
        }

        let connectionIDs = Set(doc.connections.map(\.id))
        guard connectionIDs.count == doc.connections.count else { throw NetworkInventoryError.corruptedStore }
        var seenNormalizedKeys = Set<String>()
        for connection in doc.connections {
            guard connection.isValid else { throw NetworkInventoryError.corruptedStore }
            guard deviceIDs.contains(connection.endpointADeviceID),
                  deviceIDs.contains(connection.endpointBDeviceID) else {
                throw NetworkInventoryError.corruptedStore
            }
            let key = connection.normalizedLinkKey
            guard seenNormalizedKeys.insert(key).inserted else {
                throw NetworkInventoryError.corruptedStore
            }
        }
    }

    // MARK: - Storage

    private func load() throws -> DocumentV2 {
        if let document { return document }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = DocumentV2(schemaVersion: 2, devices: [], profiles: [], plans: [], connections: [])
            document = empty
            return empty
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let version = try decoder.decode(VersionHeader.self, from: data).schemaVersion
            guard version == 1 || version == 2 else {
                throw NetworkInventoryError.unsupportedSchema(version)
            }
            if version == 1 {
                let decodedV1 = try decoder.decode(DocumentV1.self, from: data)
                guard Set(decodedV1.devices.map(\.id)).count == decodedV1.devices.count else {
                    throw NetworkInventoryError.corruptedStore
                }
                for device in decodedV1.devices {
                    try Self.validate(device)
                    guard device.revision > 0 else { throw NetworkInventoryError.corruptedStore }
                }
                let promoted = DocumentV2(
                    schemaVersion: 2,
                    devices: decodedV1.devices,
                    profiles: [],
                    plans: [],
                    connections: []
                )
                document = promoted
                return promoted
            } else {
                let decodedV2 = try decoder.decode(DocumentV2.self, from: data)
                try Self.validateDocumentV2(decodedV2)
                document = decodedV2
                return decodedV2
            }
        } catch let error as NetworkInventoryError {
            throw error
        } catch {
            throw NetworkInventoryError.corruptedStore
        }
    }

    private func persist(_ next: DocumentV2) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(next).write(to: fileURL, options: .atomic)
            document = next
        } catch {
            throw NetworkInventoryError.persistenceFailed
        }
    }
}
