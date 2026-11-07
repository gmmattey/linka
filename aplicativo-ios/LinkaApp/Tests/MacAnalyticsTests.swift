#if os(macOS)
import XCTest
@testable import LinkaApp

final class MacAnalyticsTests: XCTestCase {
    func testEventNamesCarryMacPrefixAndPlatform() {
        let events: [MacAnalyticsEvent] = [
            .firstLaunch, .appOpen(launchCount: 3, daysSinceFirstLaunch: 2, historyCount: 7),
            .speedtestStarted(connectionType: "wifi", trigger: "button"),
            .speedtestFailed(reason: "timeout", connectionType: "wifi"),
            .historyExported(rows: 12, success: true), .settingChanged(setting: "appearance", value: "dark"),
            .locationPermission(status: "denied"), .error(area: "export", kind: "write")
        ]
        for event in events {
            let payload = MacAnalyticsPayload(event)
            XCTAssertTrue(payload.name.hasPrefix("mac_"), payload.name)
            XCTAssertLessThanOrEqual(payload.name.count, 40, payload.name)
            XCTAssertEqual(payload.parameters["app_platform"], "macos")
            XCTAssertLessThanOrEqual(payload.parameters.count, 25)
        }
    }

    func testScreenViewNameStartsWithMacOS() {
        let payload = MacAnalyticsPayload(.screenView(MacScreenName.history))
        XCTAssertEqual(payload.name, "screen_view")
        XCTAssertEqual(payload.parameters["screen_name"], "macOS History")
        XCTAssertTrue(MacScreenName.settings("General").hasPrefix("macOS "))
    }

    func testCompletedCarriesRoundedSpeedsAndOmitsMissing() {
        let payload = MacAnalyticsPayload(.speedtestCompleted(
            connectionType: "wifi", durationSeconds: 24, hasUpload: true, hasPing: false,
            downloadMbps: 312.46, uploadMbps: nil, pingMs: nil))
        XCTAssertEqual(payload.parameters["download_mbps"], 312.5)
        XCTAssertNil(payload.parameters["upload_mbps"])
        XCTAssertEqual(payload.parameters["has_ping"], false)
    }

    func testBucketsAndSanitization() {
        XCTAssertEqual(MacAnalyticsPayload.bucket(0), "0")
        XCTAssertEqual(MacAnalyticsPayload.bucket(5), "1-5")
        XCTAssertEqual(MacAnalyticsPayload.bucket(21), "21-100")
        XCTAssertEqual(MacAnalyticsPayload.bucket(500), "100+")
        XCTAssertEqual(MacAnalyticsPayload.text("  "), "unknown")
        XCTAssertEqual(MacAnalyticsPayload.text(String(repeating: "a", count: 300)).count, 100)
        XCTAssertEqual(MacAnalyticsPayload.rounded(.nan), 0)
    }

    func testHistorySearchNeverCarriesQueryText() {
        let payload = MacAnalyticsPayload(.historySearched)
        XCTAssertEqual(Set(payload.parameters.keys), ["app_platform"])
    }

    func testSharedEventsAreTranslatedForMac() {
        let mapped = MacAnalyticsEvent(shared: .resultViewed(source: "history"))
        XCTAssertEqual(mapped, .resultViewed(source: "history"))
    }

    func testUserOptOutDisablesCollection() {
        let suite = "MacAnalyticsOptOut"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preference = AnalyticsCollectionPreference(userDefaults: defaults, arguments: [], environment: [:],
                                                       defaultCollectionEnabled: true)
        XCTAssertTrue(preference.isCollectionEnabled)
        preference.setUserOptedOut(true)
        XCTAssertFalse(preference.isCollectionEnabled)
        defaults.removePersistentDomain(forName: suite)
    }
}
#endif
