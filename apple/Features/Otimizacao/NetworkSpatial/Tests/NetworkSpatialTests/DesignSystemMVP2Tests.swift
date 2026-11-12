import XCTest
import SwiftUI
@testable import NetworkSpatial

@MainActor
final class DesignSystemMVP2Tests: XCTestCase {
    func testProBadgeViewInitialization() {
        let badge = ProBadgeView(isCompact: false)
        XCTAssertFalse(badge.isCompact)

        let compactBadge = ProBadgeView(isCompact: true)
        XCTAssertTrue(compactBadge.isCompact)
    }

    func testAPNodeBadgeViewRendering() {
        let routerBadge = APNodeBadgeView(type: .mainRouter)
        XCTAssertEqual(routerBadge.type, .mainRouter)
        XCTAssertNil(routerBadge.customName)

        let meshBadge = APNodeBadgeView(type: .meshSatellite, customName: "Satélite 1", isCompact: true)
        XCTAssertEqual(meshBadge.type, .meshSatellite)
        XCTAssertEqual(meshBadge.customName, "Satélite 1")
        XCTAssertTrue(meshBadge.isCompact)

        let repeaterBadge = APNodeBadgeView(type: .repeater)
        XCTAssertEqual(repeaterBadge.type, .repeater)
    }

    func testProBenefitRowInitialization() {
        let row = ProBenefitRow(
            icon: "sparkles",
            title: "Recurso Pro",
            subtitle: "Descrição detalhada do recurso"
        )

        XCTAssertEqual(row.icon, "sparkles")
        XCTAssertEqual(row.title, "Recurso Pro")
        XCTAssertEqual(row.subtitle, "Descrição detalhada do recurso")
    }
}
