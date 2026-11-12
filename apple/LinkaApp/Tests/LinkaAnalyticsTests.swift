import XCTest
@testable import LinkaApp

final class LinkaAnalyticsTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private let suiteName = "LinkaAnalyticsTestsSuite"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        super.tearDown()
    }

    func testPreference_whenAutomatedTest_isAlwaysDisabled() {
        let preference = AnalyticsCollectionPreference(
            userDefaults: testDefaults,
            arguments: ["-linka-firebase-debug"],
            environment: ["XCTestConfigurationFilePath": "/path/to/test.xctestconfiguration"],
            defaultCollectionEnabled: true
        )

        XCTAssertFalse(preference.isCollectionEnabled, "Coleta deve ser desabilitada durante testes automatizados")
    }

    func testPreference_whenFixtureArgumentPassed_isAlwaysDisabled() {
        let preference = AnalyticsCollectionPreference(
            userDefaults: testDefaults,
            arguments: ["-ui-fixture-speedtest", "-linka-firebase-debug"],
            environment: [:],
            defaultCollectionEnabled: true
        )

        XCTAssertFalse(preference.isCollectionEnabled, "Coleta deve ser desabilitada quando fixture UI for passada")
    }

    func testPreference_whenDisableArgumentPassed_isAlwaysDisabled() {
        let preference = AnalyticsCollectionPreference(
            userDefaults: testDefaults,
            arguments: ["-linka-analytics-disabled", "-linka-firebase-debug"],
            environment: [:],
            defaultCollectionEnabled: true
        )

        XCTAssertFalse(preference.isCollectionEnabled, "Coleta deve ser desabilitada com -linka-analytics-disabled")
    }

    func testPreference_whenOwnerExcluded_isAlwaysDisabled() {
        let preference = AnalyticsCollectionPreference(
            userDefaults: testDefaults,
            arguments: [],
            environment: [:],
            defaultCollectionEnabled: true
        )

        XCTAssertFalse(preference.isOwnerExcluded)
        XCTAssertTrue(preference.isCollectionEnabled)

        preference.setOwnerExcluded(true)
        XCTAssertTrue(preference.isOwnerExcluded)
        XCTAssertFalse(preference.isCollectionEnabled)

        preference.setOwnerExcluded(false)
        XCTAssertFalse(preference.isOwnerExcluded)
        XCTAssertTrue(preference.isCollectionEnabled)
    }

    func testPreference_debugWithoutFlag_isCollectionDisabled() {
        // Sem o argumento -linka-firebase-debug ou -FIRDebugEnabled
        let preference = AnalyticsCollectionPreference(
            userDefaults: testDefaults,
            arguments: ["LinkaApp"],
            environment: [:],
            defaultCollectionEnabled: false
        )

        XCTAssertFalse(preference.isCollectionEnabled)
    }

    func testPurchaseEntryPoint_analyticsIdentifiers() {
        XCTAssertEqual(PurchaseEntryPoint.settings.analyticsIdentifier, "settings")
        XCTAssertEqual(PurchaseEntryPoint.assist.analyticsIdentifier, "assist")
        XCTAssertEqual(PurchaseEntryPoint.historyInsights.analyticsIdentifier, "history_insights")
        XCTAssertEqual(PurchaseEntryPoint.advancedWiFi.analyticsIdentifier, "advanced_wifi")
        XCTAssertEqual(PurchaseEntryPoint.optimization.analyticsIdentifier, "optimization")
        XCTAssertEqual(PurchaseEntryPoint.shortcut.analyticsIdentifier, "shortcut")
        XCTAssertEqual(PurchaseEntryPoint.appIntent.analyticsIdentifier, "app_intent")
    }
}
