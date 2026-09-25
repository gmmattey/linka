import Foundation
@testable import NetscopeTransport
import XCTest

/// Only the phone-gating half is testable here: it is pure and needs neither
/// UIKit nor a physical device. The DeviceCheck half (`DCAppAttestService`)
/// can only be verified on real hardware, exactly as before this change —
/// see the physical iPhone test evidence tracked elsewhere for that half.
final class NetscopeSystemAppAttestAvailabilityTests: XCTestCase {
    func test_rejectsNonPhoneIdiomBeforeConsultingDeviceCheck() {
        XCTAssertFalse(NetscopeSystemAppAttestAvailability.isSupported(idiom: .other))
    }

    #if !canImport(DeviceCheck)
    func test_onAPlatformWithoutDeviceCheckPhoneAloneIsNotEnough() {
        // Documents the fail-closed default on any host without DeviceCheck
        // (e.g. this package's macOS target): phone idiom alone must never
        // be treated as supported.
        XCTAssertFalse(NetscopeSystemAppAttestAvailability.isSupported(idiom: .phone))
    }
    #endif
}
