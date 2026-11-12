import Foundation

/// Um ponto de medição nomeado manualmente, como Sala ou Escritório.
/// O ambiente nunca contém SSID, BSSID/MAC, localização ou métricas.
public struct NetworkEnvironment: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date

    public init?(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, updatedAt >= createdAt else { return nil }
        self.id = id
        self.name = trimmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = Self(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        ) else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: "Invalid environment")
        }
        self = value
    }
}

/// Associação local e explícita entre uma leitura já existente e um ambiente.
public struct EnvironmentMeasurementAssignment: Codable, Equatable, Hashable, Sendable {
    public let measurementID: UUID
    public let environmentID: UUID
    public let assignedAt: Date

    public init(measurementID: UUID, environmentID: UUID, assignedAt: Date = Date()) {
        self.measurementID = measurementID
        self.environmentID = environmentID
        self.assignedAt = assignedAt
    }
}
