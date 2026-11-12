import Foundation

public struct MeasurementDelta: Codable, Equatable, Sendable {
    public let downloadPercent: Double?
    public let uploadPercent: Double?
    public let latencyPercent: Double?

    public init(
        downloadPercent: Double?,
        uploadPercent: Double?,
        latencyPercent: Double?
    ) {
        self.downloadPercent = downloadPercent
        self.uploadPercent = uploadPercent
        self.latencyPercent = latencyPercent
    }
}

public struct MeasurementComparison: Codable, Equatable, Sendable {
    public let current: NetworkMeasurement
    public let baseline: NetworkMeasurement
    public let delta: MeasurementDelta

    public init(
        current: NetworkMeasurement,
        baseline: NetworkMeasurement,
        delta: MeasurementDelta
    ) {
        self.current = current
        self.baseline = baseline
        self.delta = delta
    }
}

public protocol InsightProviding: Sendable {
    func compare(
        current: NetworkMeasurement,
        against baseline: NetworkMeasurement
    ) async -> MeasurementComparison
}

public struct BasicInsightProvider: InsightProviding {
    public init() {}

    public func compare(
        current: NetworkMeasurement,
        against baseline: NetworkMeasurement
    ) async -> MeasurementComparison {
        MeasurementComparison(
            current: current,
            baseline: baseline,
            delta: MeasurementDelta(
                downloadPercent: percentageChange(current.downloadMbps, baseline.downloadMbps),
                uploadPercent: percentageChange(current.uploadMbps, baseline.uploadMbps),
                latencyPercent: percentageChange(current.latencyMs, baseline.latencyMs)
            )
        )
    }

    private func percentageChange(_ current: Double?, _ baseline: Double?) -> Double? {
        guard let current, let baseline, baseline != 0 else { return nil }
        return ((current - baseline) / baseline) * 100
    }
}
