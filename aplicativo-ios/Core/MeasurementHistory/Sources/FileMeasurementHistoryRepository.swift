import Foundation
import NetworkCore

public actor FileMeasurementHistoryRepository: MeasurementHistoryRepository {
    public static let storeSchemaVersion = 1

    private struct StoreDocument: Codable {
        let schemaVersion: Int
        let measurements: [NetworkMeasurement]
    }

    private let fileURL: URL
    private let retentionPolicy: HistoryRetentionPolicy
    private var hasLoaded = false
    private var storedMeasurements: [NetworkMeasurement] = []

    public init(
        fileURL: URL,
        retentionPolicy: HistoryRetentionPolicy = .unlimited
    ) {
        self.fileURL = fileURL
        self.retentionPolicy = retentionPolicy
    }

    public func save(_ measurement: NetworkMeasurement) async throws {
        try MeasurementHistoryCollection.validate(measurement)
        try loadIfNeeded()

        storedMeasurements.removeAll { $0.id == measurement.id }
        storedMeasurements.append(measurement)
        try pruneAndPersistIfNeeded(forcePersist: true)
    }

    public func measurement(id: UUID) async throws -> NetworkMeasurement? {
        try loadIfNeeded()
        try pruneAndPersistIfNeeded()
        return storedMeasurements.first { $0.id == id }
    }

    public func measurements(
        matching query: MeasurementQuery = .all
    ) async throws -> [NetworkMeasurement] {
        try loadIfNeeded()
        try pruneAndPersistIfNeeded()
        return MeasurementHistoryCollection.query(storedMeasurements, matching: query)
    }

    public func totalCount() async throws -> Int {
        try loadIfNeeded()
        try pruneAndPersistIfNeeded()
        return storedMeasurements.count
    }

    public func delete(id: UUID) async throws {
        try loadIfNeeded()
        let originalCount = storedMeasurements.count
        storedMeasurements.removeAll { $0.id == id }

        if storedMeasurements.count != originalCount {
            try persist()
        }
    }

    public func deleteAll() async throws {
        try loadIfNeeded()
        guard !storedMeasurements.isEmpty else { return }
        storedMeasurements.removeAll()
        try persist()
    }

    private func loadIfNeeded() throws {
        guard !hasLoaded else { return }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            storedMeasurements = []
            hasLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            // O store interno preserva a precisão de `Date` usando o formato
            // Foundation nativo. O schema interoperável externo continua ISO-8601.
            decoder.dateDecodingStrategy = .deferredToDate
            let document = try decoder.decode(StoreDocument.self, from: data)

            guard document.schemaVersion == Self.storeSchemaVersion else {
                throw MeasurementHistoryError.unsupportedStoreVersion(document.schemaVersion)
            }

            for measurement in document.measurements {
                guard NetworkMeasurementContract.isValid(measurement) else {
                    throw MeasurementHistoryError.corruptedStore
                }
            }

            // Mantém o documento como foi carregado. A retenção é aplicada pela
            // operação pública seguinte e, se remover algo, a poda é persistida.
            storedMeasurements = document.measurements
            hasLoaded = true
        } catch let error as MeasurementHistoryError {
            throw error
        } catch {
            throw MeasurementHistoryError.corruptedStore
        }
    }

    private func pruneAndPersistIfNeeded(forcePersist: Bool = false) throws {
        let retained = MeasurementHistoryCollection.retained(
            storedMeasurements,
            policy: retentionPolicy
        )
        let changed = retained != storedMeasurements
        storedMeasurements = retained

        if changed || forcePersist {
            try persist()
        }
    }

    private func persist() throws {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )

            let document = StoreDocument(
                schemaVersion: Self.storeSchemaVersion,
                measurements: storedMeasurements
            )
            let encoder = JSONEncoder()
            // ISO-8601 do Foundation perde precisão subsegundo em round-trip.
            // Como este documento é storage interno (não o contrato de troca),
            // preservamos `Date` exatamente com o formato Foundation nativo.
            encoder.dateEncodingStrategy = .deferredToDate
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw MeasurementHistoryError.persistenceFailed
        }
    }
}
