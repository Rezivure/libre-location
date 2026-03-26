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
 */
class LibreLocationPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val TAG = "LibreLocationPlugin"
        private const val PERMISSION_REQUEST_CODE = 34561
        private const val PERMISSION_REQUEST_BG_CODE = 34562
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 34563
    }

    private lateinit var channel: MethodChannel
    private lateinit var positionEventChannel: EventChannel
    private lateinit var geofenceEventChannel: EventChannel
    private lateinit var motionEventChannel: EventChannel
    private lateinit var activityEventChannel: EventChannel
    private lateinit var providerEventChannel: EventChannel
    private lateinit var heartbeatEventChannel: EventChannel
    private lateinit var powerSaveEventChannel: EventChannel

    private lateinit var context: Context
    private var activity: Activity? = null
    private var pendingPermissionResult: Result? = null
    private var pendingNotificationPermissionResult: Result? = null

    private var locationManagerWrapper: LocationManagerWrapper? = null
    private var motionDetector: MotionDetector? = null
    private var geofenceManager: GeofenceManager? = null
    private var locationDatabase: LocationDatabase? = null

    private var positionStreamHandler: GenericStreamHandler? = null
    private var geofenceStreamHandler: GenericStreamHandler? = null
    private var motionStreamHandler: GenericStreamHandler? = null
    private var activityStreamHandler: GenericStreamHandler? = null
    private var providerStreamHandler: GenericStreamHandler? = null
    private var heartbeatStreamHandler: GenericStreamHandler? = null
    private var powerSaveStreamHandler: GenericStreamHandler? = null

    private var powerSaveReceiver: PowerSaveReceiver? = null
    private var currentConfig: TrackingConfig? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        // Method channel
        channel = MethodChannel(binding.binaryMessenger, "libre_location")
        channel.setMethodCallHandler(this)

        // EventChannel names MUST match Dart side exactly
        positionStreamHandler = GenericStreamHandler()
        positionEventChannel = EventChannel(binding.binaryMessenger, "libre_location/position")
        positionEventChannel.setStreamHandler(positionStreamHandler)

        geofenceStreamHandler = GenericStreamHandler()
        geofenceEventChannel = EventChannel(binding.binaryMessenger, "libre_location/geofence")
        geofenceEventChannel.setStreamHandler(geofenceStreamHandler)

        motionStreamHandler = GenericStreamHandler()
        motionEventChannel = EventChannel(binding.binaryMessenger, "libre_location/motionChange")
        motionEventChannel.setStreamHandler(motionStreamHandler)

        activityStreamHandler = GenericStreamHandler()
        activityEventChannel = EventChannel(binding.binaryMessenger, "libre_location/activityChange")
        activityEventChannel.setStreamHandler(activityStreamHandler)

        providerStreamHandler = GenericStreamHandler()
        providerEventChannel = EventChannel(binding.binaryMessenger, "libre_location/providerChange")
        providerEventChannel.setStreamHandler(providerStreamHandler)

        heartbeatStreamHandler = GenericStreamHandler()
        heartbeatEventChannel = EventChannel(binding.binaryMessenger, "libre_location/heartbeat")
        heartbeatEventChannel.setStreamHandler(heartbeatStreamHandler)

        powerSaveStreamHandler = GenericStreamHandler()
        powerSaveEventChannel = EventChannel(binding.binaryMessenger, "libre_location/powerSaveChange")
        powerSaveEventChannel.setStreamHandler(powerSaveStreamHandler)

        // Initialize components
        locationDatabase = LocationDatabase(context)

        locationManagerWrapper = LocationManagerWrapper(context,
            onPosition = { position ->
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
            },
            onHeartbeat = { heartbeat ->
                mainHandler.post {
                    heartbeatStreamHandler?.send(heartbeat)
                }
            },
        )

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

        // Feed location updates to geofence manager and motion detector
        locationManagerWrapper?.addLocationUpdateListener { location ->
            geofenceManager?.onLocationUpdate(location)
            // Feed GPS speed to motion detector for improved activity recognition
            if (location.hasSpeed()) {
                motionDetector?.lastGpsSpeedMs = location.speed.toDouble()
            }
        }

        // Power save receiver
        powerSaveReceiver = PowerSaveReceiver(context) { isPowerSave ->
            mainHandler.post {
                powerSaveStreamHandler?.send(isPowerSave)
            }
        }
        powerSaveReceiver?.register()

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
        heartbeatEventChannel.setStreamHandler(null)
        powerSaveEventChannel.setStreamHandler(null)

        powerSaveReceiver?.unregister()

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

            // Headless callback registration
            "registerHeadlessDispatcher" -> {
                val args = call.arguments as Map<*, *>
                val dispatcherHandle = (args["dispatcherHandle"] as Number).toLong()
                val userCallbackHandle = (args["userCallbackHandle"] as Number).toLong()
                HeadlessCallbackDispatcher.setCallbackHandles(context, dispatcherHandle, userCallbackHandle)
                result.success(null)
            }

            // Battery optimization (OEM battery kill protection)
            "checkBatteryOptimization" -> {
                val pm = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    pm.isIgnoringBatteryOptimizations(context.packageName)
                } else {
                    true // Pre-M doesn't have battery optimization restrictions
                }
                result.success(!isIgnoring) // true = is optimized (bad), false = exempt (good)
            }

            "requestBatteryOptimizationExemption" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = android.net.Uri.parse("package:${context.packageName}")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to open battery optimization settings: ${e.message}")
                        result.success(false)
                    }
                } else {
                    result.success(true) // Not needed pre-M
                }
            }

            "isAutoStartEnabled" -> {
                // Best-effort detection of manufacturer auto-start settings
                result.success(checkAutoStartAvailability())
            }

            "getManufacturer" -> {
                result.success(Build.MANUFACTURER.lowercase())
            }

            "openPowerManagerSettings" -> {
                val opened = openManufacturerPowerSettings()
                result.success(opened)
            }

            // changePace — manual motion state override
            "changePace" -> {
                val args = call.arguments as? Map<*, *>
                val isMoving = args?.get("isMoving") as? Boolean ?: true
                locationManagerWrapper?.changePace(isMoving)
                if (isMoving) {
                    motionDetector?.let {
                        // Force the detector's state
                    }
                    locationManagerWrapper?.onMotionDetected()
                } else {
                    locationManagerWrapper?.onStillnessDetected()
                }
                // Emit motion change event
                val positionMap = locationManagerWrapper?.getLastPositionMap()?.toMutableMap()
                    ?: mutableMapOf(
                        "latitude" to 0.0,
                        "longitude" to 0.0,
                        "altitude" to 0.0,
                        "accuracy" to 0.0,
                        "speed" to 0.0,
                        "heading" to 0.0,
                        "timestamp" to System.currentTimeMillis(),
                        "provider" to "unknown",
                    )
                positionMap["isMoving"] = isMoving
                mainHandler.post { motionStreamHandler?.send(positionMap) }
                result.success(null)
            }

            // Logging
            "getLog" -> {
                result.success(LibreLocationLogger.getLog())
            }

            // Notification permission (Android 13+)
            "checkNotificationPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val granted = ContextCompat.checkSelfPermission(
                        context, android.Manifest.permission.POST_NOTIFICATIONS
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                } else {
                    result.success(true) // Pre-13 doesn't need runtime permission
                }
            }

            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val act = activity
                    if (act == null) {
                        result.error("NO_ACTIVITY", "No activity available", null)
                        return
                    }
                    val granted = ContextCompat.checkSelfPermission(
                        context, android.Manifest.permission.POST_NOTIFICATIONS
                    ) == PackageManager.PERMISSION_GRANTED
                    if (granted) {
                        result.success(true)
                    } else {
                        pendingNotificationPermissionResult = result
                        ActivityCompat.requestPermissions(
                            act,
                            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                            NOTIFICATION_PERMISSION_REQUEST_CODE
                        )
                    }
                } else {
                    result.success(true)
                }
            }

            // requestTemporaryFullAccuracy — iOS only, no-op on Android
            "requestTemporaryFullAccuracy" -> {
                result.success(0) // fullAccuracy — always full on Android
            }

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
                        // Emit motion change as Position map (Dart motionChangeStream is Stream<Position>)
                        val positionMap = locationManagerWrapper?.getLastPositionMap()?.toMutableMap()
                            ?: mutableMapOf(
                                "latitude" to 0.0,
                                "longitude" to 0.0,
                                "altitude" to 0.0,
                                "accuracy" to 0.0,
                                "speed" to 0.0,
                                "heading" to 0.0,
                                "timestamp" to System.currentTimeMillis(),
                                "provider" to "unknown",
                            )
                        positionMap["isMoving"] = isMoving
                        motionStreamHandler?.send(positionMap)
                    }
                },
                onActivityChanged = { type, confidence ->
                    if (confidence >= config.minimumActivityRecognitionConfidence) {
                        mainHandler.post {
                            // Key must be "activity" not "type" — matches Dart ActivityEvent.fromMap()
                            activityStreamHandler?.send(mapOf(
                                "activity" to type,
                                "confidence" to confidence,
                            ))
                        }
                    }
                }
            )
        }

        // Set log level
        LibreLocationLogger.logLevel = config.logLevel

        // Schedule watchdog alarm for self-healing
        WatchdogAlarmReceiver.schedule(context)

        LibreLocationLogger.info("Tracking started: mode=${config.mode}, accuracy=${config.accuracy}")
        Log.d(TAG, "Tracking started with config: mode=${config.mode}, accuracy=${config.accuracy}")
        result.success(null)
    }

    private fun handleStopTracking(result: Result) {
        locationManagerWrapper?.stopTracking()
        motionDetector?.stop()

        val serviceIntent = Intent(context, LocationService::class.java)
        context.stopService(serviceIntent)

        TrackingConfig.setTrackingEnabled(context, false)
        WatchdogAlarmReceiver.cancel(context)
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
        // Dart sends timeout in seconds
        val timeoutSec = (args?.get("timeout") as? Number)?.toLong() ?: 30L
        val timeoutMs = timeoutSec * 1000L
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
        // Returns int matching Dart LocationPermission enum:
        // 0 = denied, 1 = deniedForever, 2 = whileInUse, 3 = always
        val fineGranted = ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!fineGranted) {
            // Check if permanently denied (shouldShowRequestPermissionRationale returns false
            // when permanently denied, but also when never asked — we can't distinguish without activity)
            return 0 // denied
        }

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
            val permissions = mutableListOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION,
            )
            if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
                permissions.add(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            }
            ActivityCompat.requestPermissions(act, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
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
        // Handle notification permission result
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
            return true
        }

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

    // ----- OEM Battery Kill Protection -----

    /**
     * Checks if manufacturer-specific auto-start permission might be available.
     * Returns a map with manufacturer info and whether we can open their settings.
     */
    private fun checkAutoStartAvailability(): Map<String, Any> {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val hasAutoStart = manufacturer in listOf("xiaomi", "huawei", "oppo", "vivo", "samsung", "oneplus", "meizu", "asus", "letv")
        return mapOf(
            "manufacturer" to manufacturer,
            "hasAutoStartSetting" to hasAutoStart,
            "isBatteryOptimized" to isBatteryOptimized(),
        )
    }

    private fun isBatteryOptimized(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val pm = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        return !pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * Attempts to open the manufacturer-specific power/auto-start settings page.
     * Returns true if an intent was launched, false otherwise.
     */
    private fun openManufacturerPowerSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val intents = mutableListOf<Intent>()

        when {
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") -> {
                intents.add(Intent().setClassName("com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"))
                intents.add(Intent().setClassName("com.miui.powerkeeper",
                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"))
            }
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                intents.add(Intent().setClassName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"))
                intents.add(Intent().setClassName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"))
            }
            manufacturer.contains("samsung") -> {
                intents.add(Intent().setClassName("com.samsung.android.lool",
                    "com.samsung.android.sm.battery.ui.BatteryActivity"))
                intents.add(Intent().setClassName("com.samsung.android.sm",
                    "com.samsung.android.sm.battery.ui.BatteryActivity"))
            }
            manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
                intents.add(Intent().setClassName("com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity"))
                intents.add(Intent().setClassName("com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity"))
            }
            manufacturer.contains("vivo") -> {
                intents.add(Intent().setClassName("com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"))
                intents.add(Intent().setClassName("com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"))
            }
            manufacturer.contains("oneplus") -> {
                intents.add(Intent().setClassName("com.oneplus.security",
                    "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"))
            }
            manufacturer.contains("asus") -> {
                intents.add(Intent().setClassName("com.asus.mobilemanager",
                    "com.asus.mobilemanager.autostart.AutoStartActivity"))
            }
            manufacturer.contains("meizu") -> {
                intents.add(Intent().setClassName("com.meizu.safe",
                    "com.meizu.safe.security.SHOW_APPSEC"))
            }
        }

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(context.packageManager) != null) {
                    context.startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
                continue
            }
        }

        // Fallback: open generic battery optimization settings
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            } catch (_: Exception) {}
        }

        return false
    }
}

// ----- Stream Handler -----

/** Generic EventChannel stream handler with event buffering. */
class GenericStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private val pendingEvents = mutableListOf<Any>()
    private val maxPending = 100

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Flush pending events
        for (event in pendingEvents) {
            events?.success(event)
        }
        pendingEvents.clear()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun send(data: Any) {
        val sink = eventSink
        if (sink != null) {
            sink.success(data)
        } else if (pendingEvents.size < maxPending) {
            pendingEvents.add(data)
        }
    }
}
