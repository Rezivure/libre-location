import CoreLocation

/// Geofence manager using CLCircularRegion.
/// Supports up to 20 monitored regions (iOS limit).
class GeofenceManagerService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var geofences: [String: GeofenceData] = [:]
    private var onGeofenceEvent: (([String: Any]) -> Void)?

    struct GeofenceData {
        let id: String
        let latitude: Double
        let longitude: Double
        let radiusMeters: Double
        let triggers: [Int]
        let dwellDurationMs: Int?
    }

    init(onGeofenceEvent: @escaping ([String: Any]) -> Void) {
        self.onGeofenceEvent = onGeofenceEvent
        super.init()
        locationManager.delegate = self
    }

    func addGeofence(
        id: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        triggers: [Int],
        dwellDurationMs: Int?
    ) {
        let data = GeofenceData(
            id: id,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            triggers: triggers,
            dwellDurationMs: dwellDurationMs
        )
        geofences[id] = data

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: center,
            radius: min(radiusMeters, locationManager.maximumRegionMonitoringDistance),
            identifier: id
        )
        region.notifyOnEntry = triggers.contains(0)
        region.notifyOnExit = triggers.contains(1)

        locationManager.startMonitoring(for: region)
    }

    func removeGeofence(id: String) {
        geofences.removeValue(forKey: id)
        for region in locationManager.monitoredRegions {
            if region.identifier == id {
                locationManager.stopMonitoring(for: region)
                break
            }
        }
    }

    func getGeofences() -> [[String: Any]] {
        return geofences.values.map { g in
            [
                "id": g.id,
                "latitude": g.latitude,
                "longitude": g.longitude,
                "radiusMeters": g.radiusMeters,
                "triggers": g.triggers,
                "dwellDurationMs": g.dwellDurationMs as Any,
            ]
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        emitEvent(regionId: region.identifier, transition: 0)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        emitEvent(regionId: region.identifier, transition: 1)
    }

    private func emitEvent(regionId: String, transition: Int) {
        guard let geofence = geofences[regionId] else { return }
        onGeofenceEvent?([
            "geofence": [
                "id": geofence.id,
                "latitude": geofence.latitude,
                "longitude": geofence.longitude,
                "radiusMeters": geofence.radiusMeters,
                "triggers": geofence.triggers,
            ],
            "transition": transition,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        ])
    }
}
