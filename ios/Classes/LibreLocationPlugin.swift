import Flutter
import UIKit
import BackgroundTasks
import CoreLocation

/// Flutter plugin for production-grade background location tracking on iOS.
///
/// Capabilities:
/// - Background location with `allowsBackgroundLocationUpdates`
/// - Significant location change monitoring for termination recovery
/// - CMMotionActivity-based motion detection with confidence
/// - Heartbeat (periodic location emission even when stationary)
/// - Dynamic config changes at runtime via `setConfig()`
/// - `getCurrentPosition` with multi-sample averaging, timeout, maximumAge
/// - Geofencing with enter/exit/dwell, persistence, and LRU eviction
/// - Provider/authorization change notifications
/// - Local persistence for config and location buffering
///
/// Required Info.plist keys:
/// - NSLocationAlwaysAndWhenInUseUsageDescription
/// - NSLocationWhenInUseUsageDescription
/// - NSMotionUsageDescription
/// - UIBackgroundModes: [location]
public class LibreLocationPlugin: NSObject, FlutterPlugin {

    // MARK: - Properties

    private var locationService: LocationService?
    private var motionDetector: MotionDetectorService?
    private var geofenceManager: GeofenceManagerService?

    private var positionStreamHandler: StreamHandler?
    private var geofenceStreamHandler: StreamHandler?
    private var providerStreamHandler: StreamHandler?
    private var activityStreamHandler: StreamHandler?
    private var motionChangeStreamHandler: StreamHandler?
    private var heartbeatStreamHandler: StreamHandler?
    private var powerSaveStreamHandler: StreamHandler?
    private var permissionChangeStreamHandler: StreamHandler?

    // BGTaskScheduler
    static let bgTaskIdentifier = "io.rezivure.libre_location.heartbeat"
    private static var heartbeatIntervalForBG: TimeInterval = 0

    // Logging
    static var enableLogging = false

    static func log(_ message: String) {
        #if DEBUG
        print("[LibreLocation] \(message)")
        #else
        if enableLogging {
            print("[LibreLocation] \(message)")
        }
        #endif
    }

    // MARK: - Plugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "libre_location",
            binaryMessenger: registrar.messenger()
        )
        let instance = LibreLocationPlugin()

        // Position stream
        instance.positionStreamHandler = StreamHandler()
        FlutterEventChannel(
            name: "libre_location/position",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance.positionStreamHandler)

        // Geofence stream
        instance.geofenceStreamHandler = StreamHandler()
        FlutterEventChannel(
            name: "libre_location/geofence",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance.geofenceStreamHandler)

        // Provider change stream — must match Dart EventChannel name
        instance.providerStreamHandler = StreamHandler()
        FlutterEventChannel(
            name: "libre_location/providerChange",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance.providerStreamHandler)

        // Activity change stream — must match Dart EventChannel name
        instance.activityStreamHandler = StreamHandler()
        FlutterEventChannel(
            name: "libre_location/activityChange",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance.activityStreamHandler)

        // Motion change stream — must match Dart EventChannel name
        instance.motionChangeStreamHandler = StreamHandler()
        FlutterEventChannel(
            name: "libre_location/motionChange",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance.motionChangeStreamHandler)

        // Heartbeat stream — must match Dart EventChannel name
        instance.heartbeatStreamHandler = StreamHandler()
        FlutterEventChannel(
            name: "libre_location/heartbeat",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance.heartbeatStreamHandler)

        // Power save change stream
        instance.powerSaveStreamHandler = StreamHandler()
        FlutterEventChannel(
            name: "libre_location/powerSaveChange",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance.powerSaveStreamHandler)

        // Permission change stream
        instance.permissionChangeStreamHandler = StreamHandler()
        FlutterEventChannel(
            name: "libre_location/permissionChange",
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance.permissionChangeStreamHandler)

        // Observe low power mode changes
        NotificationCenter.default.addObserver(
            instance,
            selector: #selector(instance.powerStateDidChange),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )

        // Initialize services
        instance.locationService = LocationService(
            onPosition: { position in
                instance.positionStreamHandler?.send(position)
            },
            onProviderChange: { info in
                instance.providerStreamHandler?.send(info)
            },
            onMotionChange: { info in
                instance.motionChangeStreamHandler?.send(info)
            },
            onHeartbeat: { info in
                instance.heartbeatStreamHandler?.send(info)
            },
            onPermissionChange: { status in
                instance.permissionChangeStreamHandler?.send(status)
            }
        )

        instance.geofenceManager = GeofenceManagerService { event in
            instance.geofenceStreamHandler?.send(event)
        }

        instance.motionDetector = MotionDetectorService()

        // Restore tracking if app was relaunched by the OS
        instance.locationService?.restoreTrackingIfNeeded()

        // Flush any buffered locations from SQLite database
        let buffered = instance.locationService?.flushUndeliveredLocations() ?? []
        for loc in buffered {
            instance.positionStreamHandler?.send(loc)
        }

        // Also flush legacy UserDefaults buffer (migration)
        let legacyBuffered = LocationBuffer.flush()
        for loc in legacyBuffered {
            instance.positionStreamHandler?.send(loc)
        }

        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)

        // Register BGAppRefreshTask for background heartbeat (iOS 13+).
        // The host app must add "io.rezivure.libre_location.heartbeat" to
        // BGTaskSchedulerPermittedIdentifiers in Info.plist.
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: bgTaskIdentifier,
                using: nil
            ) { task in
                guard let refreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                instance.handleBGHeartbeat(task: refreshTask)
            }
        }

        log("Plugin registered")
    }

    // MARK: - BGTaskScheduler Heartbeat

    @available(iOS 13.0, *)
    static func scheduleBGHeartbeat(interval: TimeInterval) {
        heartbeatIntervalForBG = interval
        guard interval > 0 else { return }

        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        // earliestBeginDate is a hint; system decides actual timing
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
            log("BGAppRefreshTask scheduled (earliest: \(interval)s)")
        } catch {
            log("Failed to schedule BGAppRefreshTask: \(error.localizedDescription)")
        }
    }

    @available(iOS 13.0, *)
    private func handleBGHeartbeat(task: BGAppRefreshTask) {
        Self.log("BGAppRefreshTask fired — emitting heartbeat location")

        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Get current location and emit on heartbeat channel
        locationService?.getCurrentPosition(accuracy: 1, samples: 1, timeout: 15, maximumAge: 60000) { [weak self] position in
            if position["error"] == nil {
                let heartbeatData: [String: Any] = ["position": position]
                self?.heartbeatStreamHandler?.send(heartbeatData)
                // Also emit on position stream so it's captured
                self?.positionStreamHandler?.send(position)
            }
            task.setTaskCompleted(success: position["error"] == nil)
        }

        // Re-schedule the next one
        Self.scheduleBGHeartbeat(interval: Self.heartbeatIntervalForBG)
    }

    // MARK: - Method Call Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {

        // ── Tracking ──────────────────────────────────────────────

        case "startTracking":
            guard let args = args else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected map arguments", details: nil))
                return
            }
            let accuracy = args["accuracy"] as? Int ?? 0
            let intervalMs = args["intervalMs"] as? Int ?? 60000
            let distanceFilter = args["distanceFilter"] as? Double ?? 10.0
            let mode = args["mode"] as? Int ?? 1
            let enableMotion = args["enableMotionDetection"] as? Bool ?? true
            let stopTimeout = args["stopTimeout"] as? Int ?? 5
            let stationaryRadius = args["stationaryRadius"] as? Double ?? 25.0
            let heartbeatInterval = args["heartbeatInterval"] as? Int ?? 0
            let pausesAuto = args["pausesLocationUpdatesAutomatically"] as? Bool ?? false
            let activityType = args["activityType"] as? Int ?? 0
            let stopOnTerminate = args["stopOnTerminate"] as? Bool ?? true
            let preventSuspend = args["preventSuspend"] as? Bool ?? false
            let useSignificantChangesOnly = args["useSignificantChangesOnly"] as? Bool ?? false

            locationService?.startTracking(
                accuracy: accuracy,
                intervalMs: intervalMs,
                distanceFilter: distanceFilter,
                mode: mode,
                enableMotionDetection: enableMotion
            )

            // Apply additional config fields
            locationService?.setConfig([
                "stopTimeout": stopTimeout,
                "stationaryRadius": stationaryRadius,
                "heartbeatInterval": heartbeatInterval,
                "pausesLocationUpdatesAutomatically": pausesAuto,
                "activityType": activityType,
                "stopOnTerminate": stopOnTerminate,
                "preventSuspend": preventSuspend,
                "useSignificantChangesOnly": useSignificantChangesOnly,
            ])

            // Schedule BGTaskScheduler heartbeat for when app is suspended
            if heartbeatInterval > 0 {
                if #available(iOS 13.0, *) {
                    Self.scheduleBGHeartbeat(interval: TimeInterval(heartbeatInterval))
                }
            }

            if enableMotion {
                motionDetector?.start(
                    onMotionChanged: { [weak self] isMoving in
                        if isMoving {
                            self?.locationService?.onMotionDetected()
                        } else {
                            self?.locationService?.onStillnessDetected()
                        }
                    },
                    onActivityChanged: { [weak self] activity in
                        self?.activityStreamHandler?.send(activity)
                    }
                )
            }

            result(nil)

        case "stopTracking":
            locationService?.stopTracking()
            motionDetector?.stop()
            if #available(iOS 13.0, *) {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgTaskIdentifier)
            }
            result(nil)

        case "isTracking":
            result(locationService?.isTracking ?? false)

        // ── Dynamic Config ────────────────────────────────────────

        case "setConfig":
            guard let args = args else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected map arguments", details: nil))
                return
            }
            locationService?.setConfig(args)

            // Update motion detector if relevant config changed
            if let delay = args["motionTriggerDelay"] as? Double {
                motionDetector?.configure(motionTriggerDelay: delay)
            }
            if let disable = args["disableMotionActivityUpdates"] as? Bool {
                motionDetector?.configure(disableMotionActivityUpdates: disable)
            }

            result(nil)

        // ── Current Position ──────────────────────────────────────

        case "getCurrentPosition":
            let accuracy = args?["accuracy"] as? Int ?? 0
            let samples = args?["samples"] as? Int ?? 1
            let timeout = args?["timeout"] as? Int ?? 30
            let maximumAge = args?["maximumAge"] as? Int ?? 0

            locationService?.getCurrentPosition(
                accuracy: accuracy,
                samples: samples,
                timeout: timeout,
                maximumAge: maximumAge
            ) { position in
                if position["error"] != nil {
                    result(FlutterError(code: "LOCATION_ERROR", message: "Could not get position", details: nil))
                } else {
                    result(position)
                }
            }

        // ── Geofencing ───────────────────────────────────────────

        case "addGeofence":
            guard let args = args else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            geofenceManager?.addGeofence(
                id: args["id"] as? String ?? "",
                latitude: args["latitude"] as? Double ?? 0,
                longitude: args["longitude"] as? Double ?? 0,
                radiusMeters: args["radiusMeters"] as? Double ?? 100,
                triggers: args["triggers"] as? [Int] ?? [0, 1],
                dwellDurationMs: args["dwellDurationMs"] as? Int
            )
            result(nil)

        case "removeGeofence":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            geofenceManager?.removeGeofence(id: id)
            result(nil)

        case "removeAllGeofences":
            geofenceManager?.removeAllGeofences()
            result(nil)

        case "getGeofences":
            result(geofenceManager?.getGeofences() ?? [])

        // ── Permissions ──────────────────────────────────────────

        case "checkPermission":
            result(locationService?.checkPermission() ?? 0)

        case "requestPermission":
            locationService?.requestPermission { status in
                result(status)
            }

        case "requestAlwaysPermission":
            locationService?.requestAlwaysPermission { status in
                result(status)
            }

        case "openAppSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:]) { success in
                    result(success)
                }
            } else {
                result(false)
            }

        case "openLocationSettings":
            // iOS doesn't allow deep-linking to location settings directly;
            // best we can do is open the app's settings page.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:]) { success in
                    result(success)
                }
            } else {
                result(false)
            }

        case "shouldShowRequestRationale":
            result(false) // Android-only concept

        case "isLocationServiceEnabled":
            result(CLLocationManager.locationServicesEnabled())

        // ── State Queries ────────────────────────────────────────

        case "requestTemporaryFullAccuracy":
            if #available(iOS 14.0, *) {
                guard let purposeKey = args?["purposeKey"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "purposeKey required", details: nil))
                    return
                }
                locationService?.requestTemporaryFullAccuracy(purposeKey: purposeKey) { accuracyAuth in
                    result(accuracyAuth)
                }
            } else {
                result(0) // fullAccuracy on pre-14
            }

        case "changePace":
            let moving = args?["isMoving"] as? Bool ?? true
            locationService?.changePace(moving: moving)
            result(nil)

        case "getLog":
            result(LibreLocationNativeLogger.getLog())

        case "checkNotificationPermission":
            result(true) // iOS doesn't need notification permission for location

        case "requestNotificationPermission":
            result(true) // no-op on iOS

        case "isMoving":
            result(locationService?.isMoving ?? false)

        case "getBufferedLocations":
            result(locationService?.flushUndeliveredLocations() ?? [])

        // ── Android-only methods (no-op on iOS) ──────────────────

        case "checkBatteryOptimization":
            result(false) // iOS doesn't have battery optimization restrictions

        case "requestBatteryOptimizationExemption":
            result(true) // no-op on iOS

        case "isAutoStartEnabled":
            result([
                "manufacturer": "apple",
                "hasAutoStartSetting": false,
                "isBatteryOptimized": false,
            ] as [String: Any])

        case "openPowerManagerSettings":
            result(false) // no manufacturer-specific settings on iOS

        case "registerHeadlessDispatcher":
            // iOS uses significant location changes for termination recovery,
            // no headless Dart engine needed. Accept and ignore.
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Power Save Observer

    @objc private func powerStateDidChange() {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        Self.log("Low power mode changed: \(isLowPower)")
        powerSaveStreamHandler?.send(isLowPower)
    }

    // MARK: - Application Delegate

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]?
    ) -> Bool {
        // Check if relaunched due to a significant location change event
        if let options = launchOptions as? [UIApplication.LaunchOptionsKey: Any],
           options[.location] != nil {
            Self.log("App relaunched from termination due to location event — restoring tracking")
            locationService?.restoreTrackingIfNeeded()
        }
        return true
    }

    public func applicationWillEnterForeground(_ application: UIApplication) {
        // Flush undelivered locations from DB when app returns to foreground
        if let undelivered = locationService?.flushUndeliveredLocations() {
            for loc in undelivered {
                positionStreamHandler?.send(loc)
            }
        }
    }

    public func applicationWillTerminate(_ application: UIApplication) {
        Self.log("App terminating — tracking will be restored via significant location changes if configured")
    }
}

// MARK: - StreamHandler

/// Generic EventChannel stream handler for sending events to Dart.
class StreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var pendingEvents: [Any] = []
    private let maxPending = 100

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        // Flush any pending events
        for event in pendingEvents {
            events(event)
        }
        pendingEvents.removeAll()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    func send(_ data: Any) {
        if let sink = eventSink {
            DispatchQueue.main.async {
                sink(data)
            }
        } else {
            // Buffer events until a listener attaches
            if pendingEvents.count < maxPending {
                pendingEvents.append(data)
            }
        }
    }
}
