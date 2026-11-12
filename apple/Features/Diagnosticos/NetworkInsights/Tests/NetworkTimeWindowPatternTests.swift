import XCTest
import NetworkCore
@testable import NetworkInsights

final class NetworkTimeWindowPatternTests: XCTestCase {
    /// UTC fixo para que `hour`/`startOfDay` não dependam do fuso-horário
    /// da máquina que roda o teste.
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Amostra insuficiente (não inventa conclusão)

    func testInsufficientSamplesWhenFewerDistinctDaysThanRequired() {
        let measurements = [
            date(day: 1, hour: 20),
            date(day: 2, hour: 20)
        ].map { measurement(measuredAt: $0, jitter: 80) }

        let outcome = NetworkTimeWindowPatternDetector.detect(
            metric: .jitterMs,
            in: measurements,
            configuration: .init(minimumDistinctDaysInHistory: 5),
            calendar: utcCalendar
        )

        XCTAssertEqual(outcome, .insufficientSamples(distinctDayCount: 2, required: 5))
    }

    // MARK: - Sem padrão (histórico estável)

    func testNoPatternDetectedWhenMetricIsFlatAcrossTheDay() {
        var measurements: [NetworkMeasurement] = []
        for day in 1...6 {
            for hour in [8, 14, 20] {
                measurements.append(measurement(measuredAt: date(day: day, hour: hour), jitter: 10))
            }
        }

        let outcome = NetworkTimeWindowPatternDetector.detect(
            metric: .jitterMs,
            in: measurements,
            calendar: utcCalendar
        )

        XCTAssertEqual(outcome, .noPatternDetected)
    }

    // MARK: - Padrão detectado (issue #125, exemplo do dono do produto)

    func testDetectsRecurringJitterSpikeInEveningWindow() throws {
        var measurements: [NetworkMeasurement] = []
        // 6 dias distintos (>= minimumDistinctDaysInHistory padrão de 5),
        // cada um com uma amostra normal de manhã e um pico de jitter entre
        // 20h e 22h (4 amostras dentro da janela, em 4 dias distintos >=
        // minimumDistinctDaysInsideWindow padrão de 3).
        for day in 1...6 {
            measurements.append(measurement(measuredAt: date(day: day, hour: 8), jitter: 10))
        }
        for day in 1...4 {
            measurements.append(measurement(measuredAt: date(day: day, hour: 21), jitter: 100))
        }

        let outcome = NetworkTimeWindowPatternDetector.detect(
            metric: .jitterMs,
            in: measurements,
            calendar: utcCalendar
        )

        guard case .detected(let pattern) = outcome else {
            return XCTFail("Esperava um padrão detectado, obteve \(outcome)")
        }
        XCTAssertEqual(pattern.metric, .jitterMs)
        XCTAssertEqual(pattern.startHour, 20)
        XCTAssertEqual(pattern.endHour, 22)
        XCTAssertEqual(pattern.distinctDayCount, 4)
        XCTAssertEqual(pattern.insideWindowAverage, 100, accuracy: 0.001)
        XCTAssertEqual(pattern.outsideWindowAverage, 10, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(pattern.degradationPercent, 20)
    }

    func testDetectsRecurringDownloadDropUsingHigherIsBetterDirection() throws {
        var measurements: [NetworkMeasurement] = []
        for day in 1...6 {
            measurements.append(measurement(measuredAt: date(day: day, hour: 8), download: 200))
        }
        for day in 1...4 {
            measurements.append(measurement(measuredAt: date(day: day, hour: 21), download: 50))
        }

        let outcome = NetworkTimeWindowPatternDetector.detect(
            metric: .downloadMbps,
            in: measurements,
            calendar: utcCalendar
        )

        guard case .detected(let pattern) = outcome else {
            return XCTFail("Esperava um padrão detectado, obteve \(outcome)")
        }
        XCTAssertEqual(pattern.startHour, 20)
        XCTAssertEqual(pattern.endHour, 22)
    }

    func testDoesNotDetectPatternBelowMinimumDegradationThreshold() {
        var measurements: [NetworkMeasurement] = []
        for day in 1...6 {
            measurements.append(measurement(measuredAt: date(day: day, hour: 8), jitter: 10))
        }
        // Variação pequena (10 -> 11 = 10%) fica abaixo do limiar padrão de 20%.
        for day in 1...4 {
            measurements.append(measurement(measuredAt: date(day: day, hour: 21), jitter: 11))
        }

        let outcome = NetworkTimeWindowPatternDetector.detect(
            metric: .jitterMs,
            in: measurements,
            calendar: utcCalendar
        )

        XCTAssertEqual(outcome, .noPatternDetected)
    }

    // MARK: - Auxiliares

    private func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = hour
        return utcCalendar.date(from: components)!
    }

    private func measurement(
        measuredAt: Date,
        jitter: Double? = nil,
        download: Double? = nil
    ) -> NetworkMeasurement {
        NetworkMeasurement(
            measuredAt: measuredAt,
            outcome: .partial,
            downloadMbps: download,
            jitterMs: jitter,
            connectionKind: .wifi,
            networkIdentifier: "Casa"
        )
    }
}
