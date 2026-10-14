#if os(macOS)
import XCTest
@testable import LinkaApp

final class MacPresentationStateTests: XCTestCase {
    func testSidebarKeepsPrimaryTasksAndMovesContextualToolsOut() {
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.speedTest))
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.history))
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.myNetwork))
        XCTAssertFalse(MacNavigationPolicy.isSidebarDestination(.assist))
        XCTAssertFalse(MacNavigationPolicy.isSidebarDestination(.optimization))
        XCTAssertFalse(MacNavigationPolicy.isSidebarDestination(.settings))
    }

    func testMeasuringLocksNavigationExceptTheMeasurementWorkspace() {
        XCTAssertTrue(MacNavigationPolicy.isAvailable(.speedTest, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
        XCTAssertFalse(MacNavigationPolicy.isAvailable(.history, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
        XCTAssertFalse(MacNavigationPolicy.isAvailable(.myNetwork, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
        XCTAssertFalse(MacNavigationPolicy.isAvailable(.settings, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
    }

    func testGlobalMeasurementAlwaysReturnsToTheMeasurementWorkspace() {
        XCTAssertEqual(MacNavigationPolicy.measurementDestination, .speedTest)
    }

    func testInspectorIsContextualToAResultAndNeverCompressesNarrowContent() {
        XCTAssertFalse(MacHomeLayout.showsInspector(contentWidth: 1_600, hasMeasurement: false))
        XCTAssertFalse(MacHomeLayout.showsInspector(contentWidth: 1_179, hasMeasurement: true))
        XCTAssertTrue(MacHomeLayout.showsInspector(contentWidth: 1_180, hasMeasurement: true))
    }
}
#endif
