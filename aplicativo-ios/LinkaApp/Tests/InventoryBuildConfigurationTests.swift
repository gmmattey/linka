import XCTest
@testable import LinkaApp

final class InventoryBuildConfigurationTests: XCTestCase {
    func testCompiledChannelHasExplicitAvailability() {
        #if LINKA_INTERNAL_BETA
        XCTAssertEqual(InventoryBuildConfiguration.channel, .internalBeta)
        XCTAssertTrue(InventoryBuildConfiguration.isEnabled)
        #elseif DEBUG
        XCTAssertEqual(InventoryBuildConfiguration.channel, .development)
        XCTAssertTrue(InventoryBuildConfiguration.isEnabled)
        #else
        XCTAssertEqual(InventoryBuildConfiguration.channel, .publicRelease)
        XCTAssertFalse(InventoryBuildConfiguration.isEnabled)
        XCTAssertNil(InventoryBuildConfiguration.lookupEndpoint)
        #endif
    }

    func testBetaEndpointRequiresExactHostPathAndHTTPS() {
        let hosts: Set<String> = ["lookup.example"]
        let path = "/v1/device-specs/lookup"
        XCTAssertNotNil(InventoryBuildConfiguration.validatedEndpoint("https://lookup.example" + path, allowedHosts: hosts, requiredPath: path))
        for value in ["http://lookup.example" + path, "https://other.example" + path, "https://lookup.example/analysis", "https://user:secret@lookup.example" + path, "https://lookup.example" + path + "?token=secret", "https://lookup.example" + path + "#fragment", "https://lookup.example:8443" + path] {
            XCTAssertNil(InventoryBuildConfiguration.validatedEndpoint(value, allowedHosts: hosts, requiredPath: path), value)
        }
    }
}
