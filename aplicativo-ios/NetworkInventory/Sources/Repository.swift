import Foundation
public enum NetworkInventoryError: Error, Equatable { case partialEnvironmentRemoval, invalidDevice, conflict, notFound, corruptedStore, unsupportedSchema(Int), persistenceFailed, invalidResponse, unavailable }
public protocol NetworkInventoryRepository: Sendable {
    func devices() async throws -> [RegisteredNetworkDevice]
    func device(id: UUID) async throws -> RegisteredNetworkDevice?
    func save(_ device: RegisteredNetworkDevice, expectedRevision: Int?) async throws -> RegisteredNetworkDevice
    func remove(id: UUID, expectedRevision: Int) async throws
    func unlinkEnvironment(id: UUID, preservingLabel: String?) async throws
}
/// Compose a single instance per file. A schema mismatch or unreadable document is never overwritten.
public actor FileNetworkInventoryRepository: NetworkInventoryRepository {
    private struct Document: Codable { var schemaVersion: Int; var devices: [RegisteredNetworkDevice] }
    private struct Version: Decodable { var schemaVersion: Int }
    private let fileURL: URL
    private var document: Document?
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func devices() throws -> [RegisteredNetworkDevice] { try load().devices.sorted { $0.createdAt < $1.createdAt } }
    public func device(id: UUID) throws -> RegisteredNetworkDevice? { try load().devices.first { $0.id == id } }
    @discardableResult public func save(_ device: RegisteredNetworkDevice, expectedRevision: Int? = nil) throws -> RegisteredNetworkDevice {
        var current = try load()
        try Self.validate(device)
        var saved = device
        if let index = current.devices.firstIndex(where: { $0.id == device.id }) {
            let previous = current.devices[index]
            guard expectedRevision == previous.revision, previous.revision < Int.max else { throw NetworkInventoryError.conflict }
            saved.revision = previous.revision + 1; saved.createdAt = previous.createdAt; saved.updatedAt = Date()
            current.devices[index] = saved
        } else {
            guard expectedRevision == nil else { throw NetworkInventoryError.notFound }
            saved.revision = 1; saved.updatedAt = Date(); current.devices.append(saved)
        }
        try persist(current); return saved
    }
    public func remove(id: UUID, expectedRevision: Int) throws {
        var current = try load()
        guard let existing = current.devices.first(where: { $0.id == id }) else { throw NetworkInventoryError.notFound }
        guard existing.revision == expectedRevision else { throw NetworkInventoryError.conflict }
        current.devices.removeAll { $0.id == id }; try persist(current)
    }
    public func unlinkEnvironment(id: UUID, preservingLabel: String? = nil) throws {
        var current = try load(); var changed = false
        for index in current.devices.indices where current.devices[index].installation.environmentID == id {
            guard current.devices[index].revision < Int.max else { throw NetworkInventoryError.conflict }
            current.devices[index].installation.environmentID = nil
            if let preservingLabel { current.devices[index].installation.locationLabel = preservingLabel }
            current.devices[index].revision += 1; current.devices[index].updatedAt = Date(); changed = true
        }
        if changed { try persist(current) }
    }
    private static func validate(_ device: RegisteredNetworkDevice) throws {
        guard (device.installation.role == .mainRouter) == (device.installation.mainRouterAnswer == .yes), device.identity.isValid, device.revision >= 0, (device.nickname?.count ?? 0) <= 200, (device.installation.locationLabel?.count ?? 0) <= 200 else { throw NetworkInventoryError.invalidDevice }
        if let snapshot = device.specifications { try snapshot.validate(for: device.identity) }
    }
    private func load() throws -> Document {
        if let document { return document }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { let empty = Document(schemaVersion: 1, devices: []); document = empty; return empty }
        do {
            let data = try Data(contentsOf: fileURL); let decoder = JSONDecoder()
            let version = try decoder.decode(Version.self, from: data).schemaVersion
            guard version == 1 else { throw NetworkInventoryError.unsupportedSchema(version) }
            let decoded = try decoder.decode(Document.self, from: data)
            guard Set(decoded.devices.map(\.id)).count == decoded.devices.count else { throw NetworkInventoryError.corruptedStore }
            for device in decoded.devices { try Self.validate(device); guard device.revision > 0 else { throw NetworkInventoryError.corruptedStore } }
            document = decoded; return decoded
        } catch let error as NetworkInventoryError {
            if case .unsupportedSchema = error { throw error }; throw NetworkInventoryError.corruptedStore
        } catch { throw NetworkInventoryError.corruptedStore }
    }
    private func persist(_ next: Document) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(next).write(to: fileURL, options: .atomic)
            document = next
        } catch { throw NetworkInventoryError.persistenceFailed }
    }
}
