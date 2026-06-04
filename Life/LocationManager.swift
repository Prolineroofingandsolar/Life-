import CoreLocation
import Observation

// MARK: - Location Manager

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {

    var authStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authStatus = manager.authorizationStatus
    }

    func requestPermissionAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startTracking()
        default:
            break
        }
    }

    private func startTracking() {
        manager.startMonitoringSignificantLocationChanges()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
        if authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways {
            startTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        appState?.recordVisit(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
    }
}
