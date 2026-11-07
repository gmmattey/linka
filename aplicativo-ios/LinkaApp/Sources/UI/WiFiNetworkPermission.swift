import SwiftUI
import NetworkCore
#if canImport(CoreLocation) && (os(iOS) || os(macOS))
import CoreLocation
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum WiFiNetworkIdentificationState: Equatable {
    case active
    case disabledByUser
    case permissionRequired
    case permissionDenied
    case unavailable

    var statusText: String {
        switch self {
        case .active: return LinkaCopy.value("wifi.identification.active")
        case .disabledByUser: return LinkaCopy.value("wifi.identification.disabled")
        case .permissionRequired: return LinkaCopy.value("wifi.identification.permissionRequired")
        case .permissionDenied: return LinkaCopy.value("wifi.identification.permissionDenied")
        case .unavailable: return LinkaCopy.value("common.unavailable")
        }
    }
}

public extension Notification.Name {
    static let wiFiAuthorizationDidChange = Notification.Name("linka.wifi.authorizationDidChange")
}

#if canImport(CoreLocation) && (os(iOS) || os(macOS))
private final class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionDelegate()

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        NotificationCenter.default.post(name: .wiFiAuthorizationDidChange, object: nil)
    }
}
#endif

enum WiFiNetworkPermission {
    #if canImport(CoreLocation) && (os(iOS) || os(macOS))
    private static let manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = LocationPermissionDelegate.shared
        return m
    }()

    /// No macOS a autorização concedida é sempre `.authorizedAlways`;
    /// `.authorizedWhenInUse` existe apenas no iOS.
    private static func isGranted(_ status: CLAuthorizationStatus) -> Bool {
        #if os(iOS)
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #else
        return status == .authorizedAlways
        #endif
    }

    static func state(enabled: Bool) -> WiFiNetworkIdentificationState {
        state(
            enabled: enabled,
            authorizationStatus: manager.authorizationStatus,
            accuracyAuthorization: manager.accuracyAuthorization
        )
    }

    static func state(
        enabled: Bool,
        authorizationStatus: CLAuthorizationStatus,
        accuracyAuthorization: CLAccuracyAuthorization
    ) -> WiFiNetworkIdentificationState {
        guard enabled else { return .disabledByUser }
        if isGranted(authorizationStatus) {
            return accuracyAuthorization == .fullAccuracy ? .active : .permissionRequired
        }
        switch authorizationStatus {
        case .denied, .restricted:
            return .permissionDenied
        case .notDetermined:
            return .permissionRequired
        @unknown default:
            return .permissionRequired
        }
    }

    static func statusText(enabled: Bool) -> String {
        state(enabled: enabled).statusText
    }
    static var canOpenSystemSettings: Bool { manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted }
    static var isAuthorized: Bool {
        isGranted(manager.authorizationStatus)
    }
    @MainActor static func requestIdentification() {
        if isGranted(manager.authorizationStatus) {
            if manager.accuracyAuthorization != .fullAccuracy {
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WiFiIdentification")
            }
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #else
            manager.requestAlwaysAuthorization()
            #endif
        case .denied, .restricted:
            openSystemSettings()
        @unknown default:
            break
        }
    }
    @MainActor static func openSystemSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #else
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
    #else
    static func state(enabled: Bool) -> WiFiNetworkIdentificationState { .unavailable }
    static func statusText(enabled: Bool) -> String { state(enabled: enabled).statusText }
    static var canOpenSystemSettings: Bool { false }
    static var isAuthorized: Bool { false }
    static func requestIdentification() {}
    static func openSystemSettings() {}
    #endif
}

extension WiFiSecurityType {
    var displayLabel: String {
        switch self {
        case .open: return LinkaCopy.value("wifi.security.open")
        case .wep: return "WEP"
        case .personal: return LinkaCopy.value("wifi.security.personal")
        case .enterprise: return LinkaCopy.value("wifi.security.enterprise")
        case .unknown: return LinkaCopy.value("wifi.security.unknown")
        }
    }
}
