import XCTest
import WidgetKit
@testable import LinkaWidget
import LinkaWidgetShared

final class LinkaWidgetTimelineProviderTests: XCTestCase {
    private let suiteName = "LinkaWidgetTimelineProviderTests.suite"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testSnapshotReadsTheSummaryMirroredInTheAppGroup() {
        let summary = LinkaWidgetShared.LatestMeasurementSummary(
            downloadMbps: 321.5,
            uploadMbps: 42.25,
            latencyMs: 9,
            measuredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        LinkaWidgetShared.writeLatestSummary(summary, userDefaults: defaults)

        let provider = LinkaWidgetTimelineProvider {
            LinkaWidgetShared.readLatestSummary(userDefaults: self.defaults)
        }
        XCTAssertEqual(provider.snapshotEntry(isPreview: false).summary, summary)
    }

    func testTimelineHasOneEntryAndNeverPollsForANewMeasurement() {
        let provider = LinkaWidgetTimelineProvider { nil }
        let timeline = provider.timeline()
        XCTAssertEqual(timeline.entries.count, 1)
        XCTAssertNil(timeline.entries[0].summary)
        if case .never = timeline.policy {
            // O host recarrega explicitamente depois de salvar o resultado.
        } else {
            XCTFail("O widget não deve fazer polling sem uma nova medição")
        }
    }

    func testPlaceholderNeverLeaksAStoredMeasurement() {
        let provider = LinkaWidgetTimelineProvider()
        XCTAssertNil(provider.snapshotEntry(isPreview: true).summary)
    }
}
