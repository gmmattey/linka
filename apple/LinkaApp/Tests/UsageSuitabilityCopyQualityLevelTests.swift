import XCTest
import NetworkInsights
@testable import LinkaApp

/// Issue "qualidade de uso Boa/Média/Ruim" (2026-08-29): `qualityLevel(for:)`
/// agrega os veredictos por caso de uso num resumo de uma palavra para a
/// linha "Qualidade de uso" da tela de resultado.
final class UsageSuitabilityCopyQualityLevelTests: XCTestCase {
    func testHistoryVisualizationOnlyShowsTrendWithTwoOrMoreMeasurements() {
        XCTAssertEqual(HistoryVisualizationState.resolve(measurementCount: 0), .empty)
        XCTAssertEqual(HistoryVisualizationState.resolve(measurementCount: 1), .singleMeasurement)
        XCTAssertEqual(HistoryVisualizationState.resolve(measurementCount: 2), .trend)
    }

    func testAllAdequateIsGood() {
        let report = report(levels: [.adequate, .adequate, .adequate, .adequate, .adequate])
        XCTAssertEqual(UsageSuitabilityCopy.qualityLevel(for: report), .good)
    }

    func testMostlyAdequateIsGood() {
        // 4/5 adequado = 80% >= 75%.
        let report = report(levels: [.adequate, .adequate, .adequate, .adequate, .limited])
        XCTAssertEqual(UsageSuitabilityCopy.qualityLevel(for: report), .good)
    }

    func testHalfAdequateIsMedium() {
        let report = report(levels: [.adequate, .adequate, .limited, .limited, .limited])
        XCTAssertEqual(UsageSuitabilityCopy.qualityLevel(for: report), .medium)
    }

    func testMostlyLimitedIsPoor() {
        let report = report(levels: [.limited, .limited, .limited, .limited, .adequate])
        XCTAssertEqual(UsageSuitabilityCopy.qualityLevel(for: report), .poor)
    }

    func testAllLimitedIsPoor() {
        let report = report(levels: [.limited, .limited, .limited, .limited, .limited])
        XCTAssertEqual(UsageSuitabilityCopy.qualityLevel(for: report), .poor)
    }

    func testNotAssessedNeverCountsTowardTheRatio() {
        // 1 adequado, 4 não avaliados — o único caso avaliável é adequado,
        // então o nível é Boa, não penalizado pelos não avaliados.
        let report = report(levels: [.adequate, .notAssessed, .notAssessed, .notAssessed, .notAssessed])
        XCTAssertEqual(UsageSuitabilityCopy.qualityLevel(for: report), .good)
    }

    func testAllNotAssessedReturnsNil() {
        let report = report(levels: [.notAssessed, .notAssessed, .notAssessed, .notAssessed, .notAssessed])
        XCTAssertNil(UsageSuitabilityCopy.qualityLevel(for: report))
    }

    private func report(levels: [SuitabilityLevel]) -> UsageSuitabilityReport {
        let cases: [UsageCase] = [.videoCall, .streamingHD, .streaming4K, .onlineGaming, .workUpload]
        let verdicts = zip(cases, levels).map { usageCase, level in
            UsageCaseVerdict(usageCase: usageCase, level: level, limitingMetric: level == .limited ? .downloadMbps : nil)
        }
        return UsageSuitabilityReport(verdicts: verdicts)
    }
}
