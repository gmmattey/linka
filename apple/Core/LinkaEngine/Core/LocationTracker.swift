import Foundation
import CoreLocation


public final class LocationTracker: NSObject, CLLocationManagerDelegate, Sendable {
    private let manager: CLLocationManager
    
    // We cannot use isolated actor here since CLLocationManagerDelegate runs on main queue typically.
    // Instead, we just fetch the last known location if authorization is already granted.
    
    public override init() {
        self.manager = CLLocationManager()
        super.init()
    }
    
    public func getCurrentLocationIfPermitted() -> (latitude: Double, longitude: Double)? {
        guard UserDefaults.standard.bool(forKey: "isBackgroundAutomationEnabled") else {
            return nil
        }
        
        // We only return location if the user has already authorized it.
        // We DO NOT call requestWhenInUseAuthorization() to avoid interrupting the UI flow.
        
        let status = manager.authorizationStatus
        #if os(iOS)
        let isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        #else
        let isAuthorized = status == .authorized
        #endif
        guard isAuthorized else {
            return nil
        }
        
        guard let loc = manager.location else {
            return nil
        }
        
        return (latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }
}
