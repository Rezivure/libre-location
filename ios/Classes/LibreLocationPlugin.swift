import Flutter
import UIKit

/// Flutter plugin for background location tracking using CoreLocation.
/// Zero Google Play Services dependencies.
public class LibreLocationPlugin: NSObject, FlutterPlugin {
    private var locationService: LocationService?
    private var motionDetector: MotionDetectorService?
    private var geofenceManager: GeofenceManagerService?

    private var positionStreamHandler: StreamHandler?
    private var geofenceStreamHandler: StreamHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "libre_location",
            binaryMessenger: registrar.messenger()
        )
        let instance = LibreLocationPlugin()

        instance.positionStreamHandler = StreamHandler()
        let positionChannel = FlutterEventChannel(
            name: "libre_location/position",
            binaryMessenger: registrar.messenger()
        )
        positionChannel.setStreamHandler(instance.positionStreamHandler)

        instance.geofenceStreamHandler = StreamHandler()
        let geofenceChannel = FlutterEventChannel(
            name: "libre_location/geofence",
            binaryMessenger: registrar.messenger()
        )
        geofenceChannel.setStreamHandler(instance.geofenceStreamHandler)

        instance.locationService = LocationService { position in
            instance.positionStreamHandler?.send(position)
        }

        instance.geofenceManager = GeofenceManagerService { event in
            instance.geofenceStreamHandler?.send(event)
        }

        instance.motionDetector = MotionDetectorService()

        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startTracking":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let accuracy = args["accuracy"] as? Int ?? 0
            let intervalMs = args["intervalMs"] as? Int ?? 60000
            let distanceFilter = args["distanceFilter"] as? Double ?? 10.0
            let mode = args["mode"] as? Int ?? 1
            let enableMotion = args["enableMotionDetection"] as? Bool ?? true

            locationService?.startTracking(
                accuracy: accuracy,
                intervalMs: intervalMs,
                distanceFilter: distanceFilter,
                mode: mode
            )

            if enableMotion {
                motionDetector?.start { [weak self] isMoving in
                    if isMoving {
                        self?.locationService?.onMotionDetected()
                    } else {
                        self?.locationService?.onStillnessDetected()
                    }
                }
            }

            result(nil)

        case "stopTracking":
            locationService?.stopTracking()
            motionDetector?.stop()
            result(nil)

        case "getCurrentPosition":
            let args = call.arguments as? [String: Any]
            let accuracy = args?["accuracy"] as? Int ?? 0
            locationService?.getCurrentPosition(accuracy: accuracy) { position in
                result(position)
            }

        case "isTracking":
            result(locationService?.isTracking ?? false)

        case "addGeofence":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            geofenceManager?.addGeofence(
                id: args["id"] as! String,
                latitude: args["latitude"] as! Double,
                longitude: args["longitude"] as! Double,
                radiusMeters: args["radiusMeters"] as! Double,
                triggers: args["triggers"] as? [Int] ?? [0, 1],
                dwellDurationMs: args["dwellDurationMs"] as? Int
            )
            result(nil)

        case "removeGeofence":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            geofenceManager?.removeGeofence(id: args["id"] as! String)
            result(nil)

        case "getGeofences":
            result(geofenceManager?.getGeofences() ?? [])

        case "checkPermission":
            result(locationService?.checkPermission() ?? 0)

        case "requestPermission":
            locationService?.requestPermission { status in
                result(status)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Generic EventChannel stream handler.
class StreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    func send(_ data: Any) {
        eventSink?(data)
    }
}
