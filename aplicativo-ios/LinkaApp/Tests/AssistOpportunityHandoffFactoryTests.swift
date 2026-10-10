#if os(iOS)
import XCTest
@testable import LinkaApp
import AssistConsultation
import NetworkOptimization

final class AssistOpportunityHandoffFactoryTests: XCTestCase {
    func testMapsDeterministicOpportunityWithoutCarryingConfidence() throws {
        let baseline = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let supporting = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let opportunity = OptimizationOpportunity(
            id: "unstable-connection-v1",
            ruleVersion: 3,
            kind: .unstableConnection,
            action: .moveCloserToRouter,
            evidenceMeasurementIDs: [baseline, supporting],
            confidence: 0.85
        )
        let now = Date(timeIntervalSince1970: 1_791_547_200)

        let handoff = try AssistOpportunityHandoffFactory.make(
            opportunity: opportunity,
            baselineMeasurementID: baseline,
            createdAt: now
        )

        XCTAssertEqual(handoff.opportunityID, try PseudonymousReference("unstable-connection-v1"))
        XCTAssertEqual(handoff.kind, .unstableConnection)
        XCTAssertEqual(handoff.ruleVersion, "optimization/3")
        XCTAssertEqual(handoff.baselineMeasurementRef, try PseudonymousReference("measurement-11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(handoff.evidenceMeasurementRefs, [
            try PseudonymousReference("measurement-11111111-1111-1111-1111-111111111111"),
            try PseudonymousReference("measurement-22222222-2222-2222-2222-222222222222")
        ])
        XCTAssertEqual(handoff.suggestedAction, .moveCloserToRouter)
    }

    func testRejectsOpportunityThatDoesNotContainTheBaselineEvidence() {
        let baseline = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let unrelated = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let opportunity = OptimizationOpportunity(
            id: "below-usual-quality-v1",
            kind: .belowUsualQuality,
            action: .restartRouter,
            evidenceMeasurementIDs: [unrelated],
            confidence: 0.75
        )

        XCTAssertThrowsError(try AssistOpportunityHandoffFactory.make(
            opportunity: opportunity,
            baselineMeasurementID: baseline,
            createdAt: Date()
        ))
    }

    func testRejectsHandoffCreatedInTheFuture() {
        let baseline = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let opportunity = OptimizationOpportunity(
            id: "responsiveness-under-load-v1",
            kind: .responsivenessUnderLoad,
            action: .reduceConcurrentUse,
            evidenceMeasurementIDs: [baseline],
            confidence: 0.5
        )
        let now = Date(timeIntervalSince1970: 1_791_547_200)

        XCTAssertThrowsError(try AssistOpportunityHandoffFactory.make(
            opportunity: opportunity,
            baselineMeasurementID: baseline,
            createdAt: now.addingTimeInterval(1),
            validatedAt: now
        ))
    }
}
#endif
