import CoreLocation

/// CLLocationManager wrapper for background location tracking.
class LocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var onPosition: (([String: Any]) -> Void)?
    private var oneShotCallback: (([String: Any]) -> Void)?
    private var permissionCallback: ((Int) -> Void)?
    private(set) var isTracking = false
    private var currentMode = 1

    init(onPosition: @escaping ([String: Any]) -> Void) {
        self.onPosition = onPosition
        super.init()
        locationManager.delegate = self
    }

    func startTracking(accuracy: Int, intervalMs: Int, distanceFilter: Double, mode: Int) {
        currentMode = mode
        isTracking = true

        switch accuracy {
        case 0: locationManager.desiredAccuracy = kCLLocationAccuracyBest
        case 1: locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case 2: locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        default: locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        }

        locationManager.distanceFilter = distanceFilter
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true

        switch mode {
        case 0: // Active
            locationManager.startUpdatingLocation()
        case 1: // Balanced
            locationManager.startUpdatingLocation()
        case 2: // Passive
            locationManager.startMonitoringSignificantLocationChanges()
        default:
            locationManager.startUpdatingLocation()
        }
    }

    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    func getCurrentPosition(accuracy: Int, callback: @escaping ([String: Any]) -> Void) {
        oneShotCallback = callback
        locationManager.desiredAccuracy = accuracy == 0
            ? kCLLocationAccuracyBest
            : kCLLocationAccuracyHundredMeters
        locationManager.requestLocation()
    }

    func onMotionDetected() {
        guard isTracking, currentMode == 1 else { return }
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func onStillnessDetected() {
        guard isTracking, currentMode == 1 else { return }
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func checkPermission() -> Int {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .notDetermined, .denied: return 0
        case .restricted: return 1  // deniedForever
        case .authorizedWhenInUse: return 2
        case .authorizedAlways: return 3
        @unknown default: return 0
        }
    }

    func requestPermission(callback: @escaping (Int) -> Void) {
        permissionCallback = callback
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let data = locationToMap(location)

        if let cb = oneShotCallback {
            cb(data)
            oneShotCallback = nil
        } else {
            onPosition?(data)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently handle errors — position stream continues
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permissionCallback?(checkPermission())
        permissionCallback = nil
    }

    private func locationToMap(_ location: CLLocation) -> [String: Any] {
        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "accuracy": location.horizontalAccuracy,
            "speed": max(0, location.speed),
            "heading": max(0, location.course),
            "timestamp": Int64(location.timestamp.timeIntervalSince1970 * 1000),
            "provider": "core_location",
        ]
    }
}
