import Foundation
import NetworkCore

public actor InMemoryMeasurementHistoryRepository: MeasurementHistoryRepository {
    private var storedMeasurements: [NetworkMeasurement] = []
    private let retentionPolicy: HistoryRetentionPolicy

    public init(retentionPolicy: HistoryRetentionPolicy = .unlimited) {
        self.retentionPolicy = retentionPolicy
    }

    public func save(_ measurement: NetworkMeasurement) async throws {
        try MeasurementHistoryCollection.validate(measurement)

        storedMeasurements.removeAll { $0.id == measurement.id }
        storedMeasurements.append(measurement)
        prune()
    }

    public func measurement(id: UUID) async throws -> NetworkMeasurement? {
        prune()
        return storedMeasurements.first { $0.id == id }
    }

    public func measurements(
        matching query: MeasurementQuery = .all
    ) async throws -> [NetworkMeasurement] {
        prune()
        return MeasurementHistoryCollection.query(storedMeasurements, matching: query)
    }

    public func totalCount() async throws -> Int {
        prune()
        return storedMeasurements.count
    }

    public func delete(id: UUID) async throws {
        storedMeasurements.removeAll { $0.id == id }
    }

    public func deleteAll() async throws {
        storedMeasurements.removeAll()
    }

    private func prune() {
        storedMeasurements = MeasurementHistoryCollection.retained(
            storedMeasurements,
            policy: retentionPolicy
        )
    }
}
