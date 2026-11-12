import Foundation
import NetworkCore

public protocol MeasurementHistoryRepository: Sendable {
    func save(_ measurement: NetworkMeasurement) async throws
    func measurement(id: UUID) async throws -> NetworkMeasurement?
    func measurements(matching query: MeasurementQuery) async throws -> [NetworkMeasurement]
    func totalCount() async throws -> Int
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

public enum MeasurementHistoryError: Error, Equatable, Sendable {
    case invalidMeasurement([String])
    case corruptedStore
    case unsupportedStoreVersion(Int)
    case persistenceFailed
}

public enum MeasurementSortOrder: String, Codable, Equatable, Sendable {
    case newestFirst
    case oldestFirst
}

public struct MeasurementQuery: Equatable, Sendable {
    public let measuredFrom: Date?
    public let measuredUntil: Date?
    public let connectionKinds: Set<NetworkConnectionKind>
    public let outcomes: Set<MeasurementOutcome>
    public let offset: Int
    public let limit: Int?
    public let sortOrder: MeasurementSortOrder

    public init(
        measuredFrom: Date? = nil,
        measuredUntil: Date? = nil,
        connectionKinds: Set<NetworkConnectionKind> = [],
        outcomes: Set<MeasurementOutcome> = [],
        offset: Int = 0,
        limit: Int? = nil,
        sortOrder: MeasurementSortOrder = .newestFirst
    ) {
        self.measuredFrom = measuredFrom
        self.measuredUntil = measuredUntil
        self.connectionKinds = connectionKinds
        self.outcomes = outcomes
        self.offset = max(0, offset)
        self.limit = limit.map { max(0, $0) }
        self.sortOrder = sortOrder
    }

    public static let all = MeasurementQuery()
}

public struct HistoryRetentionPolicy: Equatable, Sendable {
    public let maximumEntries: Int?
    public let maximumAge: TimeInterval?

    public init(
        maximumEntries: Int? = nil,
        maximumAge: TimeInterval? = nil
    ) {
        self.maximumEntries = maximumEntries.map { max(0, $0) }
        self.maximumAge = maximumAge.map { max(0, $0) }
    }

    public static let unlimited = HistoryRetentionPolicy()
}

internal enum MeasurementHistoryCollection {
    static func validate(_ measurement: NetworkMeasurement) throws {
        let violations = NetworkMeasurementContract.violations(for: measurement)
        guard violations.isEmpty else {
            throw MeasurementHistoryError.invalidMeasurement(violations)
        }
    }

    static func retained(
        _ measurements: [NetworkMeasurement],
        policy: HistoryRetentionPolicy,
        now: Date = Date()
    ) -> [NetworkMeasurement] {
        var result = measurements

        if let maximumAge = policy.maximumAge {
            let cutoff = now.addingTimeInterval(-maximumAge)
            result.removeAll { $0.measuredAt < cutoff }
        }

        result.sort(by: newestFirst)

        if let maximumEntries = policy.maximumEntries,
           result.count > maximumEntries {
            result = Array(result.prefix(maximumEntries))
        }

        return result
    }

    static func query(
        _ measurements: [NetworkMeasurement],
        matching query: MeasurementQuery
    ) -> [NetworkMeasurement] {
        var result = measurements.filter { measurement in
            if let measuredFrom = query.measuredFrom,
               measurement.measuredAt < measuredFrom {
                return false
            }

            if let measuredUntil = query.measuredUntil,
               measurement.measuredAt > measuredUntil {
                return false
            }

            if !query.connectionKinds.isEmpty {
                guard let connectionKind = measurement.connectionKind,
                      query.connectionKinds.contains(connectionKind) else {
                    return false
                }
            }

            if !query.outcomes.isEmpty,
               !query.outcomes.contains(measurement.outcome) {
                return false
            }

            return true
        }

        switch query.sortOrder {
        case .newestFirst:
            result.sort(by: newestFirst)
        case .oldestFirst:
            result.sort(by: oldestFirst)
        }

        let start = min(query.offset, result.count)
        let tail = result.dropFirst(start)

        guard let limit = query.limit else {
            return Array(tail)
        }

        return Array(tail.prefix(limit))
    }

    private static func newestFirst(
        _ lhs: NetworkMeasurement,
        _ rhs: NetworkMeasurement
    ) -> Bool {
        if lhs.measuredAt == rhs.measuredAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.measuredAt > rhs.measuredAt
    }

    private static func oldestFirst(
        _ lhs: NetworkMeasurement,
        _ rhs: NetworkMeasurement
    ) -> Bool {
        if lhs.measuredAt == rhs.measuredAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.measuredAt < rhs.measuredAt
    }
}
