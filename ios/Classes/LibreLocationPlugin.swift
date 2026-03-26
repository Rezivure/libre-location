import Flutter
import UIKit

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
            }
        )

        instance.geofenceManager = GeofenceManagerService { event in
            instance.geofenceStreamHandler?.send(event)
        }

        instance.motionDetector = MotionDetectorService()

        // Restore tracking if app was relaunched by the OS
        instance.locationService?.restoreTrackingIfNeeded()

        // Flush any buffered locations from before termination
        let buffered = LocationBuffer.flush()
        for loc in buffered {
            instance.positionStreamHandler?.send(loc)
        }

        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)

        log("Plugin registered")
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

        // ── State Queries ────────────────────────────────────────

        case "isMoving":
            result(locationService?.isMoving ?? false)

        case "getBufferedLocations":
            result(LocationBuffer.flush())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Application Delegate

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
