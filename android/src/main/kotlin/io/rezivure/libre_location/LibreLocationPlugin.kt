package io.rezivure.libre_location

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
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
 * LibreLocationPlugin — Production-grade Flutter plugin for background location
 * tracking using pure AOSP LocationManager. Zero Google Play Services dependencies.
 *
 * Supports:
 * - Foreground service with configurable notification
 * - Activity recognition (accelerometer-based)
 * - Motion change detection with configurable thresholds
 * - Heartbeat emissions (guaranteed periodic updates)
 * - Dynamic config changes via setConfig()
 * - getCurrentPosition with multi-sample averaging, timeout, maximumAge
 * - Provider change detection (GPS on/off)
 * - Boot receiver for auto-restart
 * - Headless mode (background execution after app termination)
 * - Local SQLite persistence for location buffering
 * - Android 12-14+ compatibility
 */
class LibreLocationPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val TAG = "LibreLocationPlugin"
        private const val PERMISSION_REQUEST_CODE = 34561
        private const val PERMISSION_REQUEST_BG_CODE = 34562
    }

    private lateinit var channel: MethodChannel
    private lateinit var positionEventChannel: EventChannel
    private lateinit var geofenceEventChannel: EventChannel
    private lateinit var motionEventChannel: EventChannel
    private lateinit var activityEventChannel: EventChannel
    private lateinit var providerEventChannel: EventChannel

    private lateinit var context: Context
    private var activity: Activity? = null
    private var pendingPermissionResult: Result? = null

    private var locationManagerWrapper: LocationManagerWrapper? = null
    private var motionDetector: MotionDetector? = null
    private var geofenceManager: GeofenceManager? = null
    private var locationDatabase: LocationDatabase? = null

    private var positionStreamHandler: PositionStreamHandler? = null
    private var geofenceStreamHandler: GeofenceStreamHandler? = null
    private var motionStreamHandler: GenericStreamHandler? = null
    private var activityStreamHandler: GenericStreamHandler? = null
    private var providerStreamHandler: GenericStreamHandler? = null

    private var currentConfig: TrackingConfig? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        // Method channel
        channel = MethodChannel(binding.binaryMessenger, "libre_location")
        channel.setMethodCallHandler(this)

        // Position event channel
        positionStreamHandler = PositionStreamHandler()
        positionEventChannel = EventChannel(binding.binaryMessenger, "libre_location/position")
        positionEventChannel.setStreamHandler(positionStreamHandler)

        // Geofence event channel
        geofenceStreamHandler = GeofenceStreamHandler()
        geofenceEventChannel = EventChannel(binding.binaryMessenger, "libre_location/geofence")
        geofenceEventChannel.setStreamHandler(geofenceStreamHandler)

        // Motion change event channel
        motionStreamHandler = GenericStreamHandler()
        motionEventChannel = EventChannel(binding.binaryMessenger, "libre_location/motion")
        motionEventChannel.setStreamHandler(motionStreamHandler)

        // Activity change event channel
        activityStreamHandler = GenericStreamHandler()
        activityEventChannel = EventChannel(binding.binaryMessenger, "libre_location/activity")
        activityEventChannel.setStreamHandler(activityStreamHandler)

        // Provider change event channel
        providerStreamHandler = GenericStreamHandler()
        providerEventChannel = EventChannel(binding.binaryMessenger, "libre_location/provider")
        providerEventChannel.setStreamHandler(providerStreamHandler)

        // Initialize components
        locationDatabase = LocationDatabase(context)

        locationManagerWrapper = LocationManagerWrapper(context) { position ->
            mainHandler.post {
                positionStreamHandler?.send(position)

                // Persist if configured
                if (currentConfig?.persistLocations == true) {
                    try {
                        locationDatabase?.insertLocationMap(position)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to persist location: ${e.message}")
                    }
                }
            }
        }

        locationManagerWrapper?.setProviderChangeCallback { providerState ->
            mainHandler.post {
                providerStreamHandler?.send(providerState)
            }
        }

        motionDetector = MotionDetector(context)

        geofenceManager = GeofenceManager(context) { event ->
            mainHandler.post {
                geofenceStreamHandler?.send(event)
            }
        }

        // Deliver any buffered locations from headless/boot mode
        deliverBufferedLocations()

        Log.d(TAG, "Plugin attached to engine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        positionEventChannel.setStreamHandler(null)
        geofenceEventChannel.setStreamHandler(null)
        motionEventChannel.setStreamHandler(null)
        activityEventChannel.setStreamHandler(null)
        providerEventChannel.setStreamHandler(null)

        // Only stop if stopOnTerminate is true
        if (currentConfig?.stopOnTerminate != false) {
            locationManagerWrapper?.stopTracking()
            motionDetector?.stop()
            context.stopService(Intent(context, LocationService::class.java))
            TrackingConfig.setTrackingEnabled(context, false)
        }

        locationDatabase?.close()
        Log.d(TAG, "Plugin detached from engine")
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startTracking" -> handleStartTracking(call, result)
            "stopTracking" -> handleStopTracking(result)
            "getCurrentPosition" -> handleGetCurrentPosition(call, result)
            "isTracking" -> result.success(locationManagerWrapper?.isTracking ?: false)
            "setConfig" -> handleSetConfig(call, result)
            "getConfig" -> result.success(currentConfig?.toMap())

            // Geofence
            "addGeofence" -> handleAddGeofence(call, result)
            "removeGeofence" -> handleRemoveGeofence(call, result)
            "getGeofences" -> result.success(geofenceManager?.getGeofences() ?: emptyList<Map<String, Any>>())

            // Permissions
            "checkPermission" -> result.success(checkPermissionStatus())
            "requestPermission" -> requestLocationPermission(result)

            // State queries
            "isMoving" -> result.success(motionDetector?.isMoving ?: true)
            "getCurrentActivity" -> result.success(motionDetector?.getCurrentActivity())

            // Persistence
            "getLocations" -> handleGetLocations(call, result)
            "getLocationCount" -> result.success(locationDatabase?.getRecordCount() ?: 0)
            "clearLocations" -> {
                locationDatabase?.clearAll()
                result.success(null)
            }
            "purgeDeliveredLocations" -> {
                locationDatabase?.purgeDelivered()
                result.success(null)
            }

            // Notification
            "updateNotification" -> handleUpdateNotification(call, result)

            else -> result.notImplemented()
        }
    }

    // ----- Method Handlers -----

    private fun handleStartTracking(call: MethodCall, result: Result) {
        val args = call.arguments as Map<*, *>
        val config = TrackingConfig.fromMap(args)
        currentConfig = config

        // Persist config for boot restoration
        config.persist(context)
        TrackingConfig.setTrackingEnabled(context, true)

        // Start foreground service
        val serviceIntent = Intent(context, LocationService::class.java).apply {
            action = LocationService.ACTION_START
            putExtra(LocationService.EXTRA_NOTIFICATION_TITLE, config.notificationTitle)
            putExtra(LocationService.EXTRA_NOTIFICATION_BODY, config.notificationBody)
            putExtra(LocationService.EXTRA_NOTIFICATION_PRIORITY, config.notificationPriority)
            putExtra(LocationService.EXTRA_NOTIFICATION_STICKY, config.notificationSticky)
            putExtra(LocationService.EXTRA_HEARTBEAT_INTERVAL, config.heartbeatInterval)
            putExtra(LocationService.EXTRA_PREVENT_SUSPEND, config.preventSuspend)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service: ${e.message}")
            result.error("SERVICE_ERROR", "Failed to start foreground service: ${e.message}", null)
            return
        }

        // Start location tracking
        locationManagerWrapper?.startTracking(config)

        // Start motion detection if enabled
        if (config.enableMotionDetection && !config.disableMotionActivityUpdates) {
            motionDetector?.updateConfig(config)
            motionDetector?.start(
                onMotionChanged = { isMoving ->
                    mainHandler.post {
                        if (isMoving) {
                            locationManagerWrapper?.onMotionDetected()
                        } else {
                            locationManagerWrapper?.onStillnessDetected()
                        }
                        motionStreamHandler?.send(mapOf(
                            "isMoving" to isMoving,
                            "timestamp" to System.currentTimeMillis(),
                        ))
                    }
                },
                onActivityChanged = { type, confidence ->
                    if (confidence >= config.minimumActivityRecognitionConfidence) {
                        mainHandler.post {
                            activityStreamHandler?.send(mapOf(
                                "type" to type,
                                "confidence" to confidence,
                                "timestamp" to System.currentTimeMillis(),
                            ))
                        }
                    }
                }
            )
        }

        Log.d(TAG, "Tracking started with config: mode=${config.mode}, accuracy=${config.accuracy}")
        result.success(null)
    }

    private fun handleStopTracking(result: Result) {
        locationManagerWrapper?.stopTracking()
        motionDetector?.stop()

        val serviceIntent = Intent(context, LocationService::class.java)
        context.stopService(serviceIntent)

        TrackingConfig.setTrackingEnabled(context, false)
        currentConfig = null

        // Enforce retention on stop
        locationDatabase?.let { db ->
            val config = TrackingConfig.restore(context)
            if (config != null) {
                db.enforceRetention(config.maxDaysToPersist, config.maxRecordsToPersist)
            }
        }

        Log.d(TAG, "Tracking stopped")
        result.success(null)
    }

    private fun handleGetCurrentPosition(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val accuracy = args?.get("accuracy") as? Int ?: 0
        val samples = args?.get("samples") as? Int ?: 1
        val timeoutMs = (args?.get("timeout") as? Number)?.toLong() ?: 30_000L
        val maximumAgeMs = (args?.get("maximumAge") as? Number)?.toLong() ?: 0L
        val persist = args?.get("persist") as? Boolean ?: false

        locationManagerWrapper?.getCurrentPosition(
            accuracy = accuracy,
            samples = samples,
            timeoutMs = timeoutMs,
            maximumAgeMs = maximumAgeMs,
            persist = persist,
        ) { position ->
            mainHandler.post {
                if (position.containsKey("error")) {
                    result.error(
                        position["error"] as String,
                        position["message"] as? String,
                        null
                    )
                } else {
                    if (persist) {
                        try { locationDatabase?.insertLocationMap(position) }
                        catch (e: Exception) { Log.w(TAG, "Persist failed: ${e.message}") }
                    }
                    result.success(position)
                }
            }
        }
    }

    private fun handleSetConfig(call: MethodCall, result: Result) {
        val args = call.arguments as Map<*, *>
        val newConfig = TrackingConfig.fromMap(args)
        currentConfig = newConfig

        // Persist
        newConfig.persist(context)

        // Apply to location manager
        if (locationManagerWrapper?.isTracking == true) {
            locationManagerWrapper?.setConfig(newConfig)
        }

        // Apply to motion detector
        if (motionDetector != null) {
            motionDetector?.updateConfig(newConfig)
        }

        // Update notification if service is running
        if (LocationService.isRunning()) {
            val serviceIntent = Intent(context, LocationService::class.java).apply {
                action = LocationService.ACTION_UPDATE_NOTIFICATION
                putExtra(LocationService.EXTRA_NOTIFICATION_TITLE, newConfig.notificationTitle)
                putExtra(LocationService.EXTRA_NOTIFICATION_BODY, newConfig.notificationBody)
                putExtra(LocationService.EXTRA_NOTIFICATION_PRIORITY, newConfig.notificationPriority)
            }
            context.startService(serviceIntent)
        }

        Log.d(TAG, "Config updated dynamically")
        result.success(null)
    }

    private fun handleAddGeofence(call: MethodCall, result: Result) {
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

    private fun handleRemoveGeofence(call: MethodCall, result: Result) {
        val args = call.arguments as Map<*, *>
        geofenceManager?.removeGeofence(args["id"] as String)
        result.success(null)
    }

    private fun handleGetLocations(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val limit = args?.get("limit") as? Int ?: 1000
        val locations = locationDatabase?.getUndeliveredLocations(limit) ?: emptyList()
        result.success(locations)
    }

    private fun handleUpdateNotification(call: MethodCall, result: Result) {
        val args = call.arguments as Map<*, *>
        val title = args["title"] as? String ?: return result.success(null)
        val body = args["body"] as? String ?: ""

        if (LocationService.isRunning()) {
            val serviceIntent = Intent(context, LocationService::class.java).apply {
                action = LocationService.ACTION_UPDATE_NOTIFICATION
                putExtra(LocationService.EXTRA_NOTIFICATION_TITLE, title)
                putExtra(LocationService.EXTRA_NOTIFICATION_BODY, body)
            }
            context.startService(serviceIntent)
        }
        result.success(null)
    }

    // ----- Buffered Location Delivery -----

    private fun deliverBufferedLocations() {
        val db = locationDatabase ?: return
        val undelivered = db.getUndeliveredLocations(500)
        if (undelivered.isEmpty()) return

        Log.d(TAG, "Delivering ${undelivered.size} buffered locations")
        val ids = mutableListOf<Long>()
        for (loc in undelivered) {
            val id = loc["id"] as? Long
            if (id != null) ids.add(id)
            positionStreamHandler?.send(loc)
        }
        if (ids.isNotEmpty()) {
            db.markDelivered(ids)
        }
    }

    // ----- Permissions -----

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

        val fineGranted = ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!fineGranted) {
            // Request foreground location first
            val permissions = mutableListOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION,
            )
            // On Android 10, we can bundle background with foreground
            if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
                permissions.add(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            }
            ActivityCompat.requestPermissions(act, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Foreground already granted; request background separately (Android 11+)
            val bgGranted = ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            if (!bgGranted) {
                ActivityCompat.requestPermissions(
                    act,
                    arrayOf(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                    PERMISSION_REQUEST_BG_CODE
                )
            } else {
                result.success(3)
                pendingPermissionResult = null
            }
        } else {
            result.success(checkPermissionStatus())
            pendingPermissionResult = null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE && requestCode != PERMISSION_REQUEST_BG_CODE) return false

        val status = checkPermissionStatus()

        // If foreground was just granted on Android 11+, request background next
        if (requestCode == PERMISSION_REQUEST_CODE && status == 2 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity?.let { act ->
                ActivityCompat.requestPermissions(
                    act,
                    arrayOf(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                    PERMISSION_REQUEST_BG_CODE
                )
                return true
            }
        }

        pendingPermissionResult?.success(status)
        pendingPermissionResult = null
        return true
    }

    // ----- ActivityAware -----

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
}

// ----- Stream Handlers -----

/** EventChannel stream handler for position updates. */
class PositionStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null }
    fun send(position: Map<String, Any?>) { eventSink?.success(position) }
}

/** EventChannel stream handler for geofence events. */
class GeofenceStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null }
    fun send(event: Map<String, Any?>) { eventSink?.success(event) }
}

/** Generic EventChannel stream handler for motion, activity, provider events. */
class GenericStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null }
    fun send(data: Map<String, Any?>) { eventSink?.success(data) }
}
