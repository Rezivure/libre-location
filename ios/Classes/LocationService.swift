import CoreLocation
import UIKit

// MARK: - Configuration

/// Persisted configuration for location tracking, survives app restarts.
struct LocationServiceConfig: Codable {
    var accuracy: Int = 0
    var intervalMs: Int = 60000
    var distanceFilter: Double = 10.0
    var mode: Int = 1
    var enableMotionDetection: Bool = true
    var stillnessTimeoutMin: Int = 5          // minutes before declaring stationary
    var stillnessRadiusMeters: Double = 25.0
    var heartbeatInterval: Int = 0    // seconds; 0 = disabled
    var pausesLocationUpdatesAutomatically: Bool = false
    var activityType: Int = 0         // CLActivityType raw value
    var stopOnTerminate: Bool = false
    var keepAwake: Bool = false
    var significantChangesOnly: Bool = false
    var showsBackgroundLocationIndicator: Bool = true

    // GPS filtering
    var locationFilterEnabled: Bool = true
    var maxAccuracy: Double = 100.0   // meters
    var maxSpeed: Double = 83.33      // m/s (~300 km/h)

    static let userDefaultsKey = "libre_location_config"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func load() -> LocationServiceConfig? {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(LocationServiceConfig.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }
}

// MARK: - Location Buffer

/// Buffers location data to UserDefaults so nothing is lost if the app is killed.
final class LocationBuffer {
    private static let key = "libre_location_buffer"
    private static let maxSize = 1000

    static func append(_ location: [String: Any]) {
        var buffer = load()
        buffer.append(location)
        if buffer.count > maxSize {
            buffer = Array(buffer.suffix(maxSize))
        }
        if let data = try? JSONSerialization.data(withJSONObject: buffer) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr
    }

    static func flush() -> [[String: Any]] {
        let buf = load()
        UserDefaults.standard.removeObject(forKey: key)
        return buf
    }
}

// MARK: - LocationService

/// Production-grade CLLocationManager wrapper with background tracking,
/// heartbeat, significant location changes, motion-aware accuracy,
/// and app termination recovery.
final class LocationService: NSObject, CLLocationManagerDelegate {

    // MARK: Public State

    private(set) var isTracking = false
    private(set) var isMoving = true

    // MARK: Private

    private let locationManager = CLLocationManager()
    private var onPosition: (([String: Any]) -> Void)?
    private var onProviderChange: (([String: Any]) -> Void)?
    private var onMotionChange: (([String: Any]) -> Void)?
    private var onHeartbeat: (([String: Any]) -> Void)?
    private var onPermissionChange: ((Int) -> Void)?

    private var oneShotCallbacks: [(([String: Any]) -> Void)] = []
    private var oneShotSamples: [[String: Any]] = []
    private var oneShotSamplesNeeded: Int = 1
    private var oneShotTimeout: Timer?
    private var oneShotAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private var oneShotMaxAge: TimeInterval = 0

    private var permissionCallback: ((Int) -> Void)?

    private var config = LocationServiceConfig()

    // Heartbeat
    private var heartbeatTimer: Timer?
    private var lastEmittedLocation: CLLocation?
    private var keepAwakeTimer: Timer?

    // Stop detection
    private var lastMovementDate = Date()
    private var stopDetectionTimer: Timer?

    // Kalman filter
    private var kalmanFilter = KalmanFilter()

    // State persistence
    private static let isTrackingKey = "libre_location_is_tracking"

    // MARK: - Init

    init(onPosition: @escaping ([String: Any]) -> Void,
         onProviderChange: (([String: Any]) -> Void)? = nil,
         onMotionChange: (([String: Any]) -> Void)? = nil,
         onHeartbeat: (([String: Any]) -> Void)? = nil,
         onPermissionChange: ((Int) -> Void)? = nil) {
        self.onPosition = onPosition
        self.onProviderChange = onProviderChange
        self.onMotionChange = onMotionChange
        self.onHeartbeat = onHeartbeat
        self.onPermissionChange = onPermissionChange
        super.init()
        locationManager.delegate = self
        // Enable battery monitoring so we can include level/charging in every position
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Database Flush

    /// Flush undelivered locations from the database. Returns them and marks as delivered.
    func flushUndeliveredLocations() -> [[String: Any]] {
        let undelivered = LocationDatabase.shared.getUndelivered()
        if !undelivered.isEmpty {
            let ids = undelivered.compactMap { $0["_dbId"] as? Int64 }
            LocationDatabase.shared.markDelivered(ids)
            LibreLocationPlugin.log("Flushed \(undelivered.count) undelivered locations from DB")
        }
        return undelivered
    }

    // MARK: - App Termination Recovery

    func restoreTrackingIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.isTrackingKey),
              let saved = LocationServiceConfig.load()
        else { return }
        config = saved
        applyConfigAndStart()
        LibreLocationPlugin.log("Restored tracking after app relaunch")
    }

    // MARK: - Start / Stop

    func startTracking(
        accuracy: Int,
        intervalMs: Int,
        distanceFilter: Double,
        mode: Int,
        enableMotionDetection: Bool = true
    ) {
        kalmanFilter.reset()
        config.accuracy = accuracy
        config.intervalMs = intervalMs
        config.distanceFilter = distanceFilter
        config.mode = mode
        config.enableMotionDetection = enableMotionDetection
        config.save()
        UserDefaults.standard.set(true, forKey: Self.isTrackingKey)

        applyConfigAndStart()
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        UserDefaults.standard.set(false, forKey: Self.isTrackingKey)
        LocationServiceConfig.clear()

        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        stopHeartbeat()
        stopKeepAwake()
        stopStopDetectionTimer()
    }

    /// Dynamically update configuration without stopping/starting.
    func setConfig(_ args: [String: Any]) {
        if let v = args["accuracy"] as? Int { config.accuracy = v }
        if let v = args["intervalMs"] as? Int { config.intervalMs = v }
        if let v = args["distanceFilter"] as? Double { config.distanceFilter = v }
        if let v = args["mode"] as? Int { config.mode = v }
        if let v = args["enableMotionDetection"] as? Bool { config.enableMotionDetection = v }
        if let v = args["stillnessTimeoutMin"] as? Int { config.stillnessTimeoutMin = v }
        if let v = args["stillnessRadiusMeters"] as? Double { config.stillnessRadiusMeters = v }
        if let v = args["heartbeatInterval"] as? Int { config.heartbeatInterval = v }
        if let v = args["pausesLocationUpdatesAutomatically"] as? Bool {
            config.pausesLocationUpdatesAutomatically = v
        }
        if let v = args["activityType"] as? Int { config.activityType = v }
        if let v = args["stopOnTerminate"] as? Bool { config.stopOnTerminate = v }
        if let v = args["keepAwake"] as? Bool { config.keepAwake = v }
        if let v = args["significantChangesOnly"] as? Bool { config.significantChangesOnly = v }
        if let v = args["showsBackgroundLocationIndicator"] as? Bool {
            config.showsBackgroundLocationIndicator = v
        }
        if let v = args["locationFilterEnabled"] as? Bool { config.locationFilterEnabled = v }
        if let v = args["maxAccuracy"] as? Double { config.maxAccuracy = v }
        if let v = args["maxSpeed"] as? Double { config.maxSpeed = v }

        config.save()

        if isTracking {
            applyConfigAndStart()
        }
    }

    // MARK: - getCurrentPosition

    func getCurrentPosition(
        accuracy: Int,
        samples: Int = 1,
        timeout: Int = 30,
        maximumAge: Int = 0,
        callback: @escaping ([String: Any]) -> Void
    ) {
        // Check cached location first if maximumAge > 0
        if maximumAge > 0, let cached = lastEmittedLocation {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age <= Double(maximumAge) / 1000.0 {
                callback(locationToMap(cached))
                return
            }
        }

        oneShotSamplesNeeded = max(1, samples)
        oneShotSamples = []
        oneShotCallbacks.append(callback)

        switch accuracy {
        case 0: oneShotAccuracy = kCLLocationAccuracyBest
        case 1: oneShotAccuracy = kCLLocationAccuracyNearestTenMeters
        case 2: oneShotAccuracy = kCLLocationAccuracyHundredMeters
        case 3: oneShotAccuracy = kCLLocationAccuracyKilometer
        case 4: oneShotAccuracy = kCLLocationAccuracyBestForNavigation
        default: oneShotAccuracy = kCLLocationAccuracyBest
        }

        oneShotMaxAge = Double(maximumAge) / 1000.0

        // Use requestLocation for one-shot
        let savedAccuracy = locationManager.desiredAccuracy
        locationManager.desiredAccuracy = oneShotAccuracy
        locationManager.requestLocation()

        // Timeout (timeout is in seconds from Dart)
        oneShotTimeout?.invalidate()
        oneShotTimeout = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeout), repeats: false) { [weak self] _ in
            self?.resolveOneShot()
        }

        // Restore accuracy after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.isTracking == true {
                self?.locationManager.desiredAccuracy = savedAccuracy
            }
        }
    }

    // MARK: - Motion State

    func onMotionDetected() {
        guard isTracking else { return }
        lastMovementDate = Date()

        if !isMoving {
            isMoving = true

            // Emit motion change with current position
            emitMotionChange(isMoving: true)

            // Switch to active GPS
            locationManager.desiredAccuracy = accuracyForConfig()
            locationManager.distanceFilter = config.distanceFilter

            if config.mode == 2 {
                locationManager.stopMonitoringSignificantLocationChanges()
                locationManager.startUpdatingLocation()
            }
        }

        restartStopDetectionTimer()
    }

    func onStillnessDetected() {
        guard isTracking else { return }
        // Don't immediately go stationary; let stillnessTimeoutMin handle it
    }

    /// Manually override motion state (setMoving API).
    func setMoving(moving: Bool) {
        guard isTracking else { return }
        if moving {
            onMotionDetected()
        } else {
            guard isMoving else { return }
            isMoving = false
            emitMotionChange(isMoving: false)

            // Reduce power
            if config.mode != 0 {
                locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                locationManager.distanceFilter = max(config.stillnessRadiusMeters, 50.0)
            }
        }
    }

    // MARK: - Permissions

    func checkPermission() -> Int {
        return permissionInt()
    }

    func requestPermission(callback: @escaping (Int) -> Void) {
        permissionCallback = callback

        let status = permissionInt()
        if status == 0 {
            // Not determined — request WhenInUse first, then Always
            locationManager.requestWhenInUseAuthorization()
        } else if status == 2 {
            // WhenInUse granted — escalate to Always
            locationManager.requestAlwaysAuthorization()
        } else {
            callback(status)
        }
    }

    func requestAlwaysPermission(callback: @escaping (Int) -> Void) {
        let status = permissionInt()
        if status == 0 {
            // Not determined — request WhenInUse first, then Always will follow
            permissionCallback = callback
            locationManager.requestWhenInUseAuthorization()
        } else if status == 2 {
            // WhenInUse granted — escalate to Always
            permissionCallback = callback
            locationManager.requestAlwaysAuthorization()
        } else {
            // Already always (3) or denied (1) — can't re-ask, return current
            callback(status)
        }
    }

    // MARK: - Temporary Full Accuracy (iOS 14+)

    @available(iOS 14.0, *)
    func requestTemporaryFullAccuracy(purposeKey: String, callback: @escaping (Int) -> Void) {
        locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey) { [weak self] error in
            if let error = error {
                LibreLocationPlugin.log("requestTemporaryFullAccuracy error: \(error.localizedDescription)")
            }
            let auth = self?.locationManager.accuracyAuthorization ?? .reducedAccuracy
            // 0 = fullAccuracy, 1 = reducedAccuracy
            callback(auth == .fullAccuracy ? 0 : 1)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter out old/inaccurate readings
        let age = abs(location.timestamp.timeIntervalSinceNow)
        if age > 30 && oneShotCallbacks.isEmpty {
            return  // stale
        }

        // GPS filtering (skip for one-shot requests)
        if config.locationFilterEnabled && oneShotCallbacks.isEmpty {
            // Reject negative horizontalAccuracy (invalid from CLLocationManager)
            if location.horizontalAccuracy < 0 {
                return
            }

            // Reject locations with accuracy worse than threshold
            if location.horizontalAccuracy > config.maxAccuracy {
                return
            }

            // Speed/distance checks against last emitted location
            if let last = lastEmittedLocation {
                let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
                if timeDelta > 0 {
                    let distance = location.distance(from: last)
                    let impliedSpeed = distance / timeDelta

                    // Reject impossible speed
                    if impliedSpeed > config.maxSpeed {
                        return
                    }

                    // Distance filter: don't emit if distance < distanceFilter
                    if distance < config.distanceFilter {
                        return
                    }
                }
            }
        }

        // Apply Kalman filter for GPS smoothing
        let smoothed = applyKalmanFilter(location)
        let data = locationToMap(smoothed)
        lastEmittedLocation = smoothed

        // Flush any pending motion change now that we have a position
        flushPendingMotionChange()

        // One-shot handling
        if !oneShotCallbacks.isEmpty {
            oneShotSamples.append(data)
            if oneShotSamples.count >= oneShotSamplesNeeded {
                resolveOneShot()
            }
            return
        }

        // Regular tracking emission
        onPosition?(data)

        // Persist to SQLite database
        LocationDatabase.shared.insertLocation(data)

        // Update movement timestamp if actually moving
        if location.speed > 0.5 {
            lastMovementDate = Date()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        LibreLocationPlugin.log("Location error: \(error.localizedDescription)")

        // If one-shot is pending and we have no samples, resolve with error
        if !oneShotCallbacks.isEmpty && oneShotSamples.isEmpty {
            // Check if it's a definitive error
            if let clError = error as? CLError {
                switch clError.code {
                case .denied, .network:
                    resolveOneShotWithError()
                default:
                    break // requestLocation may retry
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let perm = permissionInt()

        // Handle permission callback
        if let cb = permissionCallback {
            if perm == 2 {
                // Got WhenInUse, escalate to Always
                locationManager.requestAlwaysAuthorization()
            } else {
                cb(perm)
                permissionCallback = nil
            }
        }

        // Emit permission change
        onPermissionChange?(perm)

        // Emit provider change — format must match Dart ProviderEvent
        let info: [String: Any] = [
            "enabled": CLLocationManager.locationServicesEnabled(),
            "status": perm,
            "gps": CLLocationManager.locationServicesEnabled(),
            "network": CLLocationManager.locationServicesEnabled(),
        ]
        onProviderChange?(info)
    }

    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        if let error = error {
            LibreLocationPlugin.log("Deferred update error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Config Application

    private func applyConfigAndStart() {
        isTracking = true
        isMoving = true
        lastMovementDate = Date()

        // Core settings
        locationManager.desiredAccuracy = accuracyForConfig()
        locationManager.distanceFilter = config.distanceFilter
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = config.showsBackgroundLocationIndicator
        locationManager.pausesLocationUpdatesAutomatically = config.pausesLocationUpdatesAutomatically

        if let actType = CLActivityType(rawValue: config.activityType) {
            locationManager.activityType = actType
        }

        // Stop existing updates
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()

        // Start based on mode
        if config.significantChangesOnly || config.mode == 2 {
            locationManager.startMonitoringSignificantLocationChanges()
        } else {
            locationManager.startUpdatingLocation()
            // Also start significant changes as a fallback for termination recovery
            if !config.stopOnTerminate {
                locationManager.startMonitoringSignificantLocationChanges()
            }
        }

        // Heartbeat
        configureHeartbeat()

        // Prevent suspend
        if config.keepAwake {
            startKeepAwake()
        } else {
            stopKeepAwake()
        }

        // Stop detection
        if config.stillnessTimeoutMin > 0 {
            restartStopDetectionTimer()
        }

        // Attempt deferred updates for battery savings
        attemptDeferredUpdates()
    }

    private func accuracyForConfig() -> CLLocationAccuracy {
        switch config.accuracy {
        case 0: return kCLLocationAccuracyBest
        case 1: return kCLLocationAccuracyNearestTenMeters
        case 2: return kCLLocationAccuracyHundredMeters
        case 3: return kCLLocationAccuracyKilometer
        case 4: return kCLLocationAccuracyBestForNavigation
        default: return kCLLocationAccuracyBest
        }
    }

    // MARK: - Heartbeat

    private func configureHeartbeat() {
        stopHeartbeat()

        guard config.heartbeatInterval > 0 else { return }

        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(config.heartbeatInterval),
            repeats: true
        ) { [weak self] _ in
            self?.emitHeartbeat()
        }
    }

    private func emitHeartbeat() {
        guard isTracking else { return }

        if let loc = lastEmittedLocation {
            let positionData = locationToMap(loc)
            // Emit on heartbeat channel with nested position (matches Dart HeartbeatEvent)
            let heartbeatData: [String: Any] = [
                "position": positionData,
            ]
            onHeartbeat?(heartbeatData)
        } else {
            // Request a fresh location
            locationManager.requestLocation()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Prevent Suspend

    private func startKeepAwake() {
        stopKeepAwake()
        keepAwakeTimer = Timer.scheduledTimer(
            withTimeInterval: 60.0,
            repeats: true
        ) { [weak self] _ in
            guard self?.isTracking == true else { return }
            self?.locationManager.requestLocation()
        }
    }

    private func stopKeepAwake() {
        keepAwakeTimer?.invalidate()
        keepAwakeTimer = nil
    }

    // MARK: - Motion Change Emission

    /// Queued motion change state waiting for a position fix.
    /// When `emitMotionChange` is called but no position is available yet,
    /// we queue the isMoving flag, request a one-shot location, and emit
    /// the motion change event once the first position arrives.
    private var pendingMotionChange: Bool? = nil

    /// Emits a motion change event containing the current position with isMoving flag.
    /// This must match Dart's Position.fromMap() format since motionChangeStream maps to Stream<Position>.
    ///
    /// If no position is available yet, queues the motion change and requests a
    /// one-shot location. The queued event is emitted when the first position arrives.
    private func emitMotionChange(isMoving: Bool) {
        if let loc = lastEmittedLocation {
            var data = locationToMap(loc)
            data["isMoving"] = isMoving
            onMotionChange?(data)
        } else {
            // No position available yet — queue and request a one-shot fix
            pendingMotionChange = isMoving
            locationManager.requestLocation()
        }
    }

    /// Called after a location is received to flush any pending motion change event.
    private func flushPendingMotionChange() {
        guard let pending = pendingMotionChange, let loc = lastEmittedLocation else { return }
        pendingMotionChange = nil
        var data = locationToMap(loc)
        data["isMoving"] = pending
        onMotionChange?(data)
    }

    // MARK: - Stop Detection

    private func restartStopDetectionTimer() {
        stopStopDetectionTimer()
        guard config.stillnessTimeoutMin > 0 else { return }

        // stillnessTimeoutMin is in minutes (from Dart)
        let timeout = TimeInterval(config.stillnessTimeoutMin * 60)
        stopDetectionTimer = Timer.scheduledTimer(
            withTimeInterval: timeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleStopTimeout()
        }
    }

    private func stopStopDetectionTimer() {
        stopDetectionTimer?.invalidate()
        stopDetectionTimer = nil
    }

    private func handleStopTimeout() {
        guard isTracking, isMoving else { return }

        let elapsed = Date().timeIntervalSince(lastMovementDate)
        let timeout = TimeInterval(config.stillnessTimeoutMin * 60)

        if elapsed >= timeout {
            isMoving = false

            // Emit motion change with position
            emitMotionChange(isMoving: false)

            // Reduce power: switch to lower accuracy or significant changes
            if config.mode != 0 {
                locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                locationManager.distanceFilter = max(config.stillnessRadiusMeters, 50.0)
            }
        }
    }

    // MARK: - Deferred Updates

    private func attemptDeferredUpdates() {
        if CLLocationManager.deferredLocationUpdatesAvailable() {
            let distance = max(config.distanceFilter * 10, 100.0)
            let timeout = TimeInterval(config.intervalMs) / 1000.0
            locationManager.allowDeferredLocationUpdates(untilTraveled: distance, timeout: timeout)
        }
    }

    // MARK: - One-Shot Resolution

    private func resolveOneShot() {
        oneShotTimeout?.invalidate()
        oneShotTimeout = nil

        guard !oneShotCallbacks.isEmpty else { return }

        let result: [String: Any]
        if oneShotSamples.count > 1 {
            result = averageSamples(oneShotSamples)
        } else if let first = oneShotSamples.first {
            result = first
        } else if let cached = lastEmittedLocation {
            result = locationToMap(cached)
        } else {
            resolveOneShotWithError()
            return
        }

        for cb in oneShotCallbacks {
            cb(result)
        }
        oneShotCallbacks.removeAll()
        oneShotSamples.removeAll()
    }

    private func resolveOneShotWithError() {
        for cb in oneShotCallbacks {
            cb(["error": "NO_LOCATION"])
        }
        oneShotCallbacks.removeAll()
        oneShotSamples.removeAll()
    }

    private func averageSamples(_ samples: [[String: Any]]) -> [String: Any] {
        guard !samples.isEmpty else { return [:] }

        var lat = 0.0, lng = 0.0, alt = 0.0, acc = 0.0, spd = 0.0, hdg = 0.0
        let n = Double(samples.count)

        for s in samples {
            lat += (s["latitude"] as? Double) ?? 0
            lng += (s["longitude"] as? Double) ?? 0
            alt += (s["altitude"] as? Double) ?? 0
            acc += (s["accuracy"] as? Double) ?? 0
            spd += (s["speed"] as? Double) ?? 0
            hdg += (s["heading"] as? Double) ?? 0
        }

        return [
            "latitude": lat / n,
            "longitude": lng / n,
            "altitude": alt / n,
            "accuracy": acc / n,
            "speed": spd / n,
            "heading": hdg / n,
            "timestamp": samples.last?["timestamp"] ?? Int64(Date().timeIntervalSince1970 * 1000),
            "provider": "core_location",
            "isMoving": isMoving,
        ]
    }

    // MARK: - Permission Helpers

    private func permissionInt() -> Int {
        // Returns int matching Dart LocationPermission enum:
        // 0 = denied, 1 = deniedForever, 2 = whileInUse, 3 = always
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .notDetermined: return 0        // denied (not yet asked)
        case .denied, .restricted: return 1  // deniedForever
        case .authorizedWhenInUse: return 2
        case .authorizedAlways: return 3
        @unknown default: return 0
        }
    }

    // MARK: - Helpers

    /// Apply Kalman filter to a location if filtering is enabled.
    /// Returns a new CLLocation with smoothed coordinates, or the original if filtering is off.
    private func applyKalmanFilter(_ location: CLLocation) -> CLLocation {
        guard config.locationFilterEnabled else { return location }

        // Reset if accuracy changed dramatically (>5x)
        if let lastAcc = kalmanFilter.lastAccuracy,
           location.horizontalAccuracy > 0,
           lastAcc > 0 {
            let ratio = location.horizontalAccuracy / lastAcc
            if ratio > 5.0 || ratio < 0.2 {
                kalmanFilter.reset()
            }
        }

        kalmanFilter.process(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp.timeIntervalSince1970
        )

        guard let filteredLat = kalmanFilter.lat,
              let filteredLng = kalmanFilter.lng else {
            return location
        }

        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: filteredLat, longitude: filteredLng),
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            course: location.course,
            speed: location.speed,
            timestamp: location.timestamp
        )
    }

    func locationToMap(_ location: CLLocation) -> [String: Any] {
        var map: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "accuracy": location.horizontalAccuracy,
            "speed": max(0, location.speed),
            "heading": max(0, location.course),
            "timestamp": Int64(location.timestamp.timeIntervalSince1970 * 1000),
            "provider": "core_location",
            "isMoving": isMoving,
        ]

        // Battery info — UIDevice battery monitoring must be enabled (done in init)
        let device = UIDevice.current
        if device.isBatteryMonitoringEnabled {
            let level = device.batteryLevel  // 0.0–1.0, or -1.0 if unknown
            if level >= 0 {
                map["batteryLevel"] = Int(level * 100)
            }
            let charging: Bool
            switch device.batteryState {
            case .charging, .full:
                charging = true
            default:
                charging = false
            }
            map["isCharging"] = charging
        }

        return map
    }
}

// MARK: - Kalman Filter for GPS Smoothing

/// Simple 1D Kalman filter applied independently to latitude and longitude.
/// Smooths GPS jitter while preserving real movement.
final class KalmanFilter {
    private(set) var lat: Double?
    private(set) var lng: Double?
    private var variance: Double = 0
    private var lastTimestamp: TimeInterval = 0
    private(set) var lastAccuracy: Double?

    /// Process noise in m²/s — higher = trusts new readings more.
    /// 3.0 is reasonable for walking; driving can use higher.
    private let processNoise: Double = 3.0

    func process(lat: Double, lng: Double, accuracy: Double, timestamp: TimeInterval) {
        guard accuracy > 0 else { return }

        if self.lat == nil {
            // First reading
            self.lat = lat
            self.lng = lng
            self.variance = accuracy * accuracy
            self.lastTimestamp = timestamp
            self.lastAccuracy = accuracy
            return
        }

        // Add process noise based on time elapsed
        let timeDelta = max(0, timestamp - lastTimestamp)
        variance += timeDelta * processNoise

        // Kalman gain
        let measurementVariance = accuracy * accuracy
        let K = variance / (variance + measurementVariance)

        // Update estimates
        self.lat = self.lat! + K * (lat - self.lat!)
        self.lng = self.lng! + K * (lng - self.lng!)

        // Update variance
        self.variance = (1.0 - K) * variance

        self.lastTimestamp = timestamp
        self.lastAccuracy = accuracy
    }

    func reset() {
        lat = nil
        lng = nil
        variance = 0
        lastTimestamp = 0
        lastAccuracy = nil
    }
}
