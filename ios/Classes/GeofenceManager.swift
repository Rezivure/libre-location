import CoreLocation
import Foundation

// MARK: - GeofenceManagerService

/// Production geofence manager using CLCircularRegion monitoring.
///
/// Features:
/// - Up to 20 monitored regions (iOS hard limit)
/// - Enter, exit, and dwell event types
/// - Dwell detection via timer after enter event
/// - Persistence across app restarts via UserDefaults
/// - Automatic restoration of monitored regions on launch
/// - LRU eviction when region limit is reached
final class GeofenceManagerService: NSObject, CLLocationManagerDelegate {

    // MARK: - Types

    struct GeofenceData: Codable {
        let id: String
        let latitude: Double
        let longitude: Double
        let radiusMeters: Double
        let triggers: [Int]       // 0=enter, 1=exit, 2=dwell
        let dwellDurationMs: Int?
        var addedAt: TimeInterval  // for LRU eviction
    }

    // MARK: - Properties

    private let locationManager = CLLocationManager()
    private var geofences: [String: GeofenceData] = [:]
    private var dwellTimers: [String: Timer] = [:]
    private var onGeofenceEvent: (([String: Any]) -> Void)?

    private static let maxRegions = 20
    private static let persistenceKey = "libre_location_geofences"

    // MARK: - Init

    init(onGeofenceEvent: @escaping ([String: Any]) -> Void) {
        self.onGeofenceEvent = onGeofenceEvent
        super.init()
        locationManager.delegate = self
        restoreGeofences()
    }

    // MARK: - Public API

    func addGeofence(
        id: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        triggers: [Int],
        dwellDurationMs: Int?
    ) {
        // Evict oldest if at limit and this is a new geofence
        if geofences[id] == nil && geofences.count >= Self.maxRegions {
            evictOldest()
        }

        let data = GeofenceData(
            id: id,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            triggers: triggers,
            dwellDurationMs: dwellDurationMs,
            addedAt: Date().timeIntervalSince1970
        )
        geofences[id] = data
        persistGeofences()

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let clampedRadius = min(radiusMeters, locationManager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: center, radius: clampedRadius, identifier: id)
        region.notifyOnEntry = triggers.contains(0) || triggers.contains(2)  // dwell needs enter
        region.notifyOnExit = triggers.contains(1)

        locationManager.startMonitoring(for: region)

        // Request initial state
        locationManager.requestState(for: region)

        LibreLocationPlugin.log("Added geofence: \(id) at (\(latitude), \(longitude)) r=\(clampedRadius)m")
    }

    func removeGeofence(id: String) {
        geofences.removeValue(forKey: id)
        cancelDwellTimer(id: id)
        persistGeofences()

        for region in locationManager.monitoredRegions {
            if region.identifier == id {
                locationManager.stopMonitoring(for: region)
                break
            }
        }

        LibreLocationPlugin.log("Removed geofence: \(id)")
    }

    func removeAllGeofences() {
        for region in locationManager.monitoredRegions {
            if geofences[region.identifier] != nil {
                locationManager.stopMonitoring(for: region)
            }
        }
        geofences.removeAll()
        dwellTimers.values.forEach { $0.invalidate() }
        dwellTimers.removeAll()
        persistGeofences()
    }

    func getGeofences() -> [[String: Any]] {
        return geofences.values.map { g in
            var map: [String: Any] = [
                "id": g.id,
                "latitude": g.latitude,
                "longitude": g.longitude,
                "radiusMeters": g.radiusMeters,
                "triggers": g.triggers,
            ]
            if let dwell = g.dwellDurationMs {
                map["dwellDurationMs"] = dwell
            }
            return map
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let geofence = geofences[region.identifier] else { return }

        if geofence.triggers.contains(0) {
            emitEvent(geofence: geofence, transition: 0)
        }

        // Start dwell timer if dwell is a trigger
        if geofence.triggers.contains(2), let dwellMs = geofence.dwellDurationMs, dwellMs > 0 {
            startDwellTimer(geofence: geofence, durationMs: dwellMs)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let geofence = geofences[region.identifier] else { return }

        cancelDwellTimer(id: geofence.id)

        if geofence.triggers.contains(1) {
            emitEvent(geofence: geofence, transition: 1)
        }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        // Used for initial state check after adding a geofence
        guard let geofence = geofences[region.identifier] else { return }

        if state == .inside {
            if geofence.triggers.contains(0) {
                emitEvent(geofence: geofence, transition: 0)
            }
            if geofence.triggers.contains(2), let dwellMs = geofence.dwellDurationMs, dwellMs > 0 {
                startDwellTimer(geofence: geofence, durationMs: dwellMs)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        LibreLocationPlugin.log("Geofence monitoring failed for \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
    }

    // MARK: - Dwell Timer

    private func startDwellTimer(geofence: GeofenceData, durationMs: Int) {
        cancelDwellTimer(id: geofence.id)

        let timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(durationMs) / 1000.0,
            repeats: false
        ) { [weak self] _ in
            self?.emitEvent(geofence: geofence, transition: 2)
            self?.dwellTimers.removeValue(forKey: geofence.id)
        }
        dwellTimers[geofence.id] = timer
    }

    private func cancelDwellTimer(id: String) {
        dwellTimers[id]?.invalidate()
        dwellTimers.removeValue(forKey: id)
    }

    // MARK: - Event Emission

    private func emitEvent(geofence: GeofenceData, transition: Int) {
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

    // MARK: - Persistence

    private func persistGeofences() {
        if let data = try? JSONEncoder().encode(Array(geofences.values)) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private func restoreGeofences() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
              let stored = try? JSONDecoder().decode([GeofenceData].self, from: data)
        else { return }

        for g in stored {
            geofences[g.id] = g
            // Re-register with CLLocationManager (in case app was terminated)
            let center = CLLocationCoordinate2D(latitude: g.latitude, longitude: g.longitude)
            let radius = min(g.radiusMeters, locationManager.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(center: center, radius: radius, identifier: g.id)
            region.notifyOnEntry = g.triggers.contains(0) || g.triggers.contains(2)
            region.notifyOnExit = g.triggers.contains(1)
            locationManager.startMonitoring(for: region)
        }

        LibreLocationPlugin.log("Restored \(stored.count) geofences")
    }

    // MARK: - LRU Eviction

    private func evictOldest() {
        guard let oldest = geofences.values.min(by: { $0.addedAt < $1.addedAt }) else { return }
        removeGeofence(id: oldest.id)
        LibreLocationPlugin.log("Evicted oldest geofence: \(oldest.id)")
    }
}
