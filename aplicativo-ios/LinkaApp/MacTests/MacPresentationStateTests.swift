#if os(macOS)
import XCTest

final class MacPresentationStateTests: XCTestCase {
    func testSidebarIncludesPrimaryAndToolsDestinationsFromPrototype() {
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.speedTest))
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.history))
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.assist))
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.dns))
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.optimization))
        XCTAssertTrue(MacNavigationPolicy.isSidebarDestination(.myNetwork))
        XCTAssertFalse(MacNavigationPolicy.isSidebarDestination(.settings))
    }

    func testMeasuringLocksNavigationExceptTheMeasurementWorkspace() {
        XCTAssertTrue(MacNavigationPolicy.isAvailable(.speedTest, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
        XCTAssertFalse(MacNavigationPolicy.isAvailable(.history, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
        XCTAssertFalse(MacNavigationPolicy.isAvailable(.assist, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
        XCTAssertFalse(MacNavigationPolicy.isAvailable(.dns, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
        XCTAssertFalse(MacNavigationPolicy.isAvailable(.optimization, isMeasuring: true, hasMeasurement: true, minhaRedeEnabled: true))
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

    // MARK: - Bloco 3 & 4 Tests

    func testHistoryComparisonSelectionCapAtTwoItems() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        var selection = Set<UUID>()

        let (sel1, capped1) = MacHistoryComparisonPolicy.toggleSelection(id: id1, currentSelection: selection)
        XCTAssertFalse(capped1)
        XCTAssertEqual(sel1.count, 1)
        XCTAssertFalse(MacHistoryComparisonPolicy.isComparisonReady(selectionCount: sel1.count))

        selection = sel1
        let (sel2, capped2) = MacHistoryComparisonPolicy.toggleSelection(id: id2, currentSelection: selection)
        XCTAssertFalse(capped2)
        XCTAssertEqual(sel2.count, 2)
        XCTAssertTrue(MacHistoryComparisonPolicy.isComparisonReady(selectionCount: sel2.count))

        selection = sel2
        let (sel3, capped3) = MacHistoryComparisonPolicy.toggleSelection(id: id3, currentSelection: selection)
        XCTAssertTrue(capped3, "Selecting a 3rd item must be rejected per 2-item cap")
        XCTAssertEqual(sel3.count, 2)

        // Deselection reduces count
        let (sel4, capped4) = MacHistoryComparisonPolicy.toggleSelection(id: id1, currentSelection: selection)
        XCTAssertFalse(capped4)
        XCTAssertEqual(sel4.count, 1)
        XCTAssertFalse(MacHistoryComparisonPolicy.isComparisonReady(selectionCount: sel4.count))
    }

    func testHistoryComparisonDeltaCalculation() {
        // Prototype seed values: 482.6 Mbps vs 94.2 Mbps -> delta 388.4 Mbps
        let delta = MacHistoryComparisonPolicy.calculateDeltaMbps(a: 482.6, b: 94.2)
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta!, 388.4, accuracy: 0.001)

        // Inverted order gives same positive delta
        let deltaInverted = MacHistoryComparisonPolicy.calculateDeltaMbps(a: 94.2, b: 482.6)
        XCTAssertEqual(deltaInverted!, 388.4, accuracy: 0.001)

        // Missing values return nil
        XCTAssertNil(MacHistoryComparisonPolicy.calculateDeltaMbps(a: nil, b: 94.2))
        XCTAssertNil(MacHistoryComparisonPolicy.calculateDeltaMbps(a: 482.6, b: nil))
    }

    func testOptimizationChecklistReadinessPolicy() {
        XCTAssertFalse(MacOptimizationPolicy.isReadyForRetest(checkedSteps: []))
        XCTAssertFalse(MacOptimizationPolicy.isReadyForRetest(checkedSteps: [true]))
        XCTAssertFalse(MacOptimizationPolicy.isReadyForRetest(checkedSteps: [true, true]))
        XCTAssertFalse(MacOptimizationPolicy.isReadyForRetest(checkedSteps: [true, false, true]))
        XCTAssertTrue(MacOptimizationPolicy.isReadyForRetest(checkedSteps: [true, true, true]))
        XCTAssertTrue(MacOptimizationPolicy.isReadyForRetest(checkedSteps: [true, true, true, false]))

        XCTAssertEqual(MacOptimizationPolicy.progressText(completedCount: 0), "0 de 3")
        XCTAssertEqual(MacOptimizationPolicy.progressText(completedCount: 1), "1 de 3")
        XCTAssertEqual(MacOptimizationPolicy.progressText(completedCount: 2), "2 de 3")
        XCTAssertEqual(MacOptimizationPolicy.progressText(completedCount: 3), "3 de 3")
    }

    func testDNSBenchmarkRelativeBarScaling() {
        // Median equals max -> 1.0 (100% width)
        let fullWidth = MacDNSBenchmarkPolicy.relativeBarWidth(medianMs: 40.0, maxLatencyMs: 40.0)
        XCTAssertEqual(fullWidth, 1.0, accuracy: 0.001)

        // Median is half of max -> 0.5 (50% width)
        let halfWidth = MacDNSBenchmarkPolicy.relativeBarWidth(medianMs: 20.0, maxLatencyMs: 40.0)
        XCTAssertEqual(halfWidth, 0.5, accuracy: 0.001)

        // Very low median clamps to minimum 0.05 for visual presence
        let minWidth = MacDNSBenchmarkPolicy.relativeBarWidth(medianMs: 0.1, maxLatencyMs: 100.0)
        XCTAssertEqual(minWidth, 0.05, accuracy: 0.001)

        // Fallback when max is 0 or invalid
        let fallback = MacDNSBenchmarkPolicy.relativeBarWidth(medianMs: 10.0, maxLatencyMs: 0.0)
        XCTAssertEqual(fallback, 0.05, accuracy: 0.001)
    }

    func testAssistContextInclusionPolicy() {
        XCTAssertTrue(MacAssistContextPolicy.shouldIncludeMeasurement(toggle: true, hasMeasurement: true))
        XCTAssertFalse(MacAssistContextPolicy.shouldIncludeMeasurement(toggle: false, hasMeasurement: true))
        XCTAssertFalse(MacAssistContextPolicy.shouldIncludeMeasurement(toggle: true, hasMeasurement: false))
        XCTAssertFalse(MacAssistContextPolicy.shouldIncludeMeasurement(toggle: false, hasMeasurement: false))
    }
}
#endif
