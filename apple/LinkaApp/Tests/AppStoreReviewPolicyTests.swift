import XCTest
@testable import LinkaApp

final class AppStoreReviewPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var policy: AppStoreReviewPolicy!
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "AppStoreReviewPolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        policy = AppStoreReviewPolicy(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        policy = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNeverRequestsOnFirstOrSecondCompletedResult() {
        XCTAssertFalse(eligible(count: 1, firstMeasurementDaysAgo: 30, interacted: true))
        XCTAssertFalse(eligible(count: 2, firstMeasurementDaysAgo: 30, interacted: true))
    }

    func testRequiresSevenDaysAndAnInteractionWithTheResult() {
        XCTAssertFalse(eligible(count: 3, firstMeasurementDaysAgo: 6, interacted: true))
        XCTAssertFalse(eligible(count: 3, firstMeasurementDaysAgo: 7, interacted: false))
        XCTAssertTrue(eligible(count: 3, firstMeasurementDaysAgo: 7, interacted: true))
    }

    func testAutomaticRequestHasVersionAndTimeCooldown() {
        policy.recordAutomaticRequest(now: now, appVersion: "1.1.1")

        XCTAssertFalse(eligible(count: 3, firstMeasurementDaysAgo: 7, interacted: true))
        XCTAssertFalse(eligible(count: 3, firstMeasurementDaysAgo: 7, interacted: true, version: "1.1.2", at: now.addingTimeInterval(119 * 24 * 60 * 60)))
        XCTAssertTrue(eligible(count: 3, firstMeasurementDaysAgo: 7, interacted: true, version: "1.1.2", at: now.addingTimeInterval(120 * 24 * 60 * 60)))
    }

    func testPromptRequiresTheResultToRemainVisibleWithoutAnotherPresentation() {
        XCTAssertTrue(
            AppStoreReviewPromptPresentationPolicy.isSafe(
                sceneIsActive: true,
                resultIsVisible: true,
                hasBlockingPresentation: false
            )
        )
        XCTAssertFalse(
            AppStoreReviewPromptPresentationPolicy.isSafe(
                sceneIsActive: true,
                resultIsVisible: false,
                hasBlockingPresentation: false
            )
        )
        XCTAssertFalse(
            AppStoreReviewPromptPresentationPolicy.isSafe(
                sceneIsActive: true,
                resultIsVisible: true,
                hasBlockingPresentation: true
            )
        )
    }

    private func eligible(
        count: Int,
        firstMeasurementDaysAgo: Int,
        interacted: Bool,
        version: String = "1.1.1",
        at date: Date? = nil
    ) -> Bool {
        let evaluationDate = date ?? now
        return policy.shouldRequestReview(
            completedMeasurementCount: count,
            firstCompletedMeasurementAt: evaluationDate.addingTimeInterval(TimeInterval(-firstMeasurementDaysAgo * 24 * 60 * 60)),
            hasInteractedWithCurrentResult: interacted,
            now: evaluationDate,
            appVersion: version
        )
    }
}
