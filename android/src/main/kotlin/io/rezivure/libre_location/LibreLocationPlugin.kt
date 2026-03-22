package io.rezivure.libre_location

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * LibreLocationPlugin — Flutter plugin for background location tracking
 * using pure AOSP LocationManager. Zero Google Play Services dependencies.
 */
class LibreLocationPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var positionEventChannel: EventChannel
    private lateinit var geofenceEventChannel: EventChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var pendingPermissionResult: Result? = null

    private var locationManagerWrapper: LocationManagerWrapper? = null
    private var motionDetector: MotionDetector? = null
    private var geofenceManager: GeofenceManager? = null
    private var positionStreamHandler: PositionStreamHandler? = null
    private var geofenceStreamHandler: GeofenceStreamHandler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "libre_location")
        channel.setMethodCallHandler(this)

        positionStreamHandler = PositionStreamHandler()
        positionEventChannel = EventChannel(binding.binaryMessenger, "libre_location/position")
        positionEventChannel.setStreamHandler(positionStreamHandler)

        geofenceStreamHandler = GeofenceStreamHandler()
        geofenceEventChannel = EventChannel(binding.binaryMessenger, "libre_location/geofence")
        geofenceEventChannel.setStreamHandler(geofenceStreamHandler)

        locationManagerWrapper = LocationManagerWrapper(context) { position ->
            positionStreamHandler?.send(position)
        }
        motionDetector = MotionDetector(context)
        geofenceManager = GeofenceManager(context) { event ->
            geofenceStreamHandler?.send(event)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        positionEventChannel.setStreamHandler(null)
        geofenceEventChannel.setStreamHandler(null)
        locationManagerWrapper?.stopTracking()
        motionDetector?.stop()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startTracking" -> {
                val args = call.arguments as Map<*, *>
                val accuracy = args["accuracy"] as? Int ?: 0
                val intervalMs = (args["intervalMs"] as? Number)?.toLong() ?: 60000L
                val distanceFilter = (args["distanceFilter"] as? Number)?.toFloat() ?: 10f
                val mode = args["mode"] as? Int ?: 1
                val enableMotion = args["enableMotionDetection"] as? Boolean ?: true
                val notifTitle = args["notificationTitle"] as? String ?: "Location Tracking"
                val notifBody = args["notificationBody"] as? String ?: "Tracking your location in the background"

                // Start foreground service
                val serviceIntent = Intent(context, LocationService::class.java).apply {
                    putExtra("notificationTitle", notifTitle)
                    putExtra("notificationBody", notifBody)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }

                locationManagerWrapper?.startTracking(accuracy, intervalMs, distanceFilter, mode)

                if (enableMotion) {
                    motionDetector?.start { isMoving ->
                        if (isMoving) {
                            locationManagerWrapper?.onMotionDetected()
                        } else {
                            locationManagerWrapper?.onStillnessDetected()
                        }
                    }
                }

                result.success(null)
            }
            "stopTracking" -> {
                locationManagerWrapper?.stopTracking()
                motionDetector?.stop()
                context.stopService(Intent(context, LocationService::class.java))
                result.success(null)
            }
            "getCurrentPosition" -> {
                val args = call.arguments as? Map<*, *>
                val accuracy = args?.get("accuracy") as? Int ?: 0
                locationManagerWrapper?.getCurrentPosition(accuracy) { position ->
                    result.success(position)
                }
            }
            "isTracking" -> {
                result.success(locationManagerWrapper?.isTracking ?: false)
            }
            "addGeofence" -> {
                val args = call.arguments as Map<*, *>
                geofenceManager?.addGeofence(
                    id = args["id"] as String,
                    latitude = (args["latitude"] as Number).toDouble(),
                    longitude = (args["longitude"] as Number).toDouble(),
                    radiusMeters = (args["radiusMeters"] as Number).toFloat(),
                    triggers = (args["triggers"] as? List<*>)?.map { it as Int } ?: listOf(0, 1),
                    dwellDurationMs = (args["dwellDurationMs"] as? Number)?.toLong()
                )
                result.success(null)
            }
            "removeGeofence" -> {
                val args = call.arguments as Map<*, *>
                geofenceManager?.removeGeofence(args["id"] as String)
                result.success(null)
            }
            "getGeofences" -> {
                result.success(geofenceManager?.getGeofences() ?: emptyList<Map<String, Any>>())
            }
            "checkPermission" -> {
                result.success(checkPermissionStatus())
            }
            "requestPermission" -> {
                requestLocationPermission(result)
            }
            else -> result.notImplemented()
        }
    }

    private fun checkPermissionStatus(): Int {
        val fineGranted = ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!fineGranted) return 0 // denied

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val bgGranted = ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            return if (bgGranted) 3 else 2 // always : whileInUse
        }

        return 3 // always (pre-Q doesn't have background distinction)
    }

    private fun requestLocationPermission(result: Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "No activity available to request permissions", null)
            return
        }

        pendingPermissionResult = result

        val permissions = mutableListOf(
            android.Manifest.permission.ACCESS_FINE_LOCATION,
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Background location must be requested separately on Android 11+
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                permissions.add(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            }
        }

        ActivityCompat.requestPermissions(act, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        pendingPermissionResult?.success(checkPermissionStatus())
        pendingPermissionResult = null
        return true
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivity() { activity = null }

    companion object {
        private const val PERMISSION_REQUEST_CODE = 34561
    }
}

/** EventChannel stream handler for position updates. */
class PositionStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun send(position: Map<String, Any?>) {
        eventSink?.success(position)
    }
}

/** EventChannel stream handler for geofence events. */
class GeofenceStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun send(event: Map<String, Any?>) {
        eventSink?.success(event)
    }
}
