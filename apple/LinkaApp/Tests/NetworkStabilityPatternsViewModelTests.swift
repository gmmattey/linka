import XCTest
import LinkaEntitlements
import NetworkCore
import LinkaModules
@testable import LinkaApp

@MainActor
final class NetworkStabilityPatternsViewModelTests: XCTestCase {
    
    func testLoadWithNoNetworkIdentity() async {
        let viewModel = NetworkStabilityPatternsViewModel(entitlements: StoreKitEntitlementProvider())
        
        let measurement = NetworkMeasurement(
            connectionKind: nil,
            networkIdentifier: nil
        )
        
        await viewModel.load(currentMeasurement: measurement)
        
        XCTAssertEqual(viewModel.state, .unavailable)
    }
}
