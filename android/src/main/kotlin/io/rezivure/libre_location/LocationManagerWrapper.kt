package io.rezivure.libre_location

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Production-grade AOSP LocationManager wrapper. Zero Google Play Services.
 */
class LocationManagerWrapper(
    private val context: Context,
    private val onPosition: (Map<String, Any?>) -> Unit,
    private val onHeartbeat: ((Map<String, Any?>) -> Unit)? = null,
) {

    companion object {
        private const val TAG = "LibreLocationMgr"
        private const val DUPLICATE_TIME_THRESHOLD = 1000L
    }

    // GPS filter config
    private var locationFilterEnabled: Boolean = true
    private var maxAccuracy: Float = 100f
    private var maxSpeed: Float = 83.33f // ~300 km/h

    private val locationManager: LocationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())

    var isTracking = false
        private set
    var isMoving: Boolean = true
        private set

    private var config: TrackingConfig = TrackingConfig()

    private var lastEmittedLocation: Location? = null
    private var lastEmittedTime: Long = 0L
    private var cachedLocation: Location? = null

    private var providerChangeCallback: ((Map<String, Any?>) -> Unit)? = null
    private var locationUpdateListeners = mutableListOf<(Location) -> Unit>()
    private var lastProviderState = mutableMapOf<String, Boolean>()

    private var heartbeatRunnable: Runnable? = null

    private val activeListeners = CopyOnWriteArrayList<LocationListener>()

    // ----- Primary Location Listener -----

    private val primaryListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            processLocation(location)
        }

        override fun onLocationChanged(locations: MutableList<Location>) {
            locations.lastOrNull()?.let { processLocation(it) }
        }

        override fun onProviderEnabled(provider: String) {
            Log.d(TAG, "Provider enabled: $provider")
            reportProviderChange()
        }

        override fun onProviderDisabled(provider: String) {
            Log.d(TAG, "Provider disabled: $provider")
            reportProviderChange()
        }

        @Deprecated("Deprecated in API")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private val secondaryListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            processLocation(location)
        }
        override fun onProviderEnabled(provider: String) { reportProviderChange() }
        override fun onProviderDisabled(provider: String) { reportProviderChange() }
        @Deprecated("Deprecated in API")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private val providerCheckRunnable = object : Runnable {
        override fun run() {
            if (!isTracking) return
            checkProviderChanges()
            handler.postDelayed(this, 10_000L)
        }
    }

    @SuppressLint("MissingPermission")
    fun startTracking(config: TrackingConfig) {
        // Remove any existing listeners to prevent duplicates if called twice
        if (isTracking) {
            locationManager.removeUpdates(primaryListener)
            locationManager.removeUpdates(secondaryListener)
            stopHeartbeat()
            handler.removeCallbacks(providerCheckRunnable)
        }

        this.config = config
        isTracking = true
        isMoving = true
        locationFilterEnabled = config.locationFilterEnabled
        maxAccuracy = config.maxAccuracy
        maxSpeed = config.maxSpeed

        registerProviders()
        startHeartbeat()
        startProviderMonitoring()

        Log.d(TAG, "Tracking started: mode=${config.mode}, accuracy=${config.accuracy}, filter=$locationFilterEnabled")
    }

    fun stopTracking() {
        isTracking = false
        locationManager.removeUpdates(primaryListener)
        locationManager.removeUpdates(secondaryListener)
        activeListeners.forEach { locationManager.removeUpdates(it) }
        activeListeners.clear()
        stopHeartbeat()
        handler.removeCallbacks(providerCheckRunnable)
        Log.d(TAG, "Tracking stopped")
    }

    @SuppressLint("MissingPermission")
    fun setConfig(newConfig: TrackingConfig) {
        val wasTracking = isTracking
        if (wasTracking) {
            locationManager.removeUpdates(primaryListener)
            locationManager.removeUpdates(secondaryListener)
            stopHeartbeat()
        }

        this.config = newConfig

        if (wasTracking) {
            registerProviders()
            startHeartbeat()
        }

        Log.d(TAG, "Config updated dynamically")
    }

    @SuppressLint("MissingPermission")
    fun getCurrentPosition(
        accuracy: Int = 0,
        samples: Int = 1,
        timeoutMs: Long = 30_000L,
        maximumAgeMs: Long = 0L,
        persist: Boolean = false,
        callback: (Map<String, Any?>) -> Unit
    ) {
        if (maximumAgeMs > 0) {
            val cached = getCachedLocation(accuracy)
            if (cached != null) {
                val age = System.currentTimeMillis() - cached.time
                if (age <= maximumAgeMs) {
                    Log.d(TAG, "Returning cached location (age=${age}ms)")
                    callback(locationToMap(cached))
                    return
                }
            }
        }

        val provider = providerForAccuracy(accuracy)
        val collectedSamples = mutableListOf<Location>()
        var completed = false

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (completed) return
                collectedSamples.add(location)

                if (collectedSamples.size >= samples) {
                    completed = true
                    locationManager.removeUpdates(this)
                    activeListeners.remove(this)

                    val averaged = if (collectedSamples.size == 1) {
                        collectedSamples[0]
                    } else {
                        averageLocations(collectedSamples)
                    }

                    cachedLocation = averaged
                    callback(locationToMap(averaged))
                }
            }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
            @Deprecated("Deprecated in API")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }

        activeListeners.add(listener)
        try {
            locationManager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
        } catch (e: SecurityException) {
            activeListeners.remove(listener)
            callback(mapOf("error" to "PERMISSION_DENIED", "message" to "Location permission not granted"))
            return
        }

        handler.postDelayed({
            if (completed) return@postDelayed
            completed = true
            locationManager.removeUpdates(listener)
            activeListeners.remove(listener)

            if (collectedSamples.isNotEmpty()) {
                val averaged = if (collectedSamples.size == 1) collectedSamples[0]
                    else averageLocations(collectedSamples)
                cachedLocation = averaged
                callback(locationToMap(averaged))
            } else {
                val fallback = getCachedLocation(accuracy)
                if (fallback != null) {
                    callback(locationToMap(fallback))
                } else {
                    callback(mapOf(
                        "error" to "TIMEOUT",
                        "message" to "Could not obtain location within ${timeoutMs}ms"
                    ))
                }
            }
        }, timeoutMs)
    }

    // ----- Motion State -----

    @SuppressLint("MissingPermission")
    fun onMotionDetected() {
        if (!isTracking) return
        val wasStationary = !isMoving
        isMoving = true

        if (wasStationary && config.mode == 1) {
            try {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    config.intervalMs,
                    config.distanceFilter,
                    primaryListener,
                    Looper.getMainLooper()
                )
            } catch (e: Exception) {
                Log.w(TAG, "Failed to re-engage GPS: ${e.message}")
            }
            Log.d(TAG, "Motion detected — GPS re-engaged")
        }
    }

    /**
     * Manually override motion state. Used by changePace API.
     */
    fun changePace(moving: Boolean) {
        if (!isTracking) return
        if (moving) {
            onMotionDetected()
        } else {
            val wasMoving = isMoving
            isMoving = false
            if (wasMoving && config.mode == 1) {
                locationManager.removeUpdates(primaryListener)
                Log.d(TAG, "changePace: forced stationary — GPS paused")
            }
        }
    }

    fun onStillnessDetected() {
        if (!isTracking) return
        val wasMoving = isMoving
        isMoving = false

        if (wasMoving && config.mode == 1) {
            locationManager.removeUpdates(primaryListener)
            Log.d(TAG, "Stillness detected — GPS paused (network only)")
        }
    }

    /**
     * Returns the last emitted position as a map, or null if no position is available.
     * Used by the plugin to include position data in motion change events.
     */
    fun getLastPositionMap(): Map<String, Any?>? {
        val loc = lastEmittedLocation ?: cachedLocation ?: return null
        return locationToMap(loc)
    }

    fun setProviderChangeCallback(callback: (Map<String, Any?>) -> Unit) {
        providerChangeCallback = callback
    }

    /**
     * Registers a listener that receives every accepted location update.
     * Used by GeofenceManager for distance-based geofence checking.
     */
    fun addLocationUpdateListener(listener: (Location) -> Unit) {
        locationUpdateListeners.add(listener)
    }

    // ----- Internal -----

    @SuppressLint("MissingPermission")
    private fun registerProviders() {
        when (config.mode) {
            0 -> {
                requestUpdatesIfAvailable(LocationManager.GPS_PROVIDER, primaryListener)
                requestUpdatesIfAvailable(LocationManager.NETWORK_PROVIDER, secondaryListener)
            }
            1 -> {
                requestUpdatesIfAvailable(LocationManager.NETWORK_PROVIDER, primaryListener)
                if (isMoving) {
                    requestUpdatesIfAvailable(LocationManager.GPS_PROVIDER, secondaryListener)
                }
            }
            2 -> {
                requestUpdatesIfAvailable(LocationManager.PASSIVE_PROVIDER, primaryListener)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestUpdatesIfAvailable(provider: String, listener: LocationListener) {
        try {
            if (locationManager.isProviderEnabled(provider) || provider == LocationManager.PASSIVE_PROVIDER) {
                locationManager.requestLocationUpdates(
                    provider, config.intervalMs, config.distanceFilter, listener, Looper.getMainLooper()
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register $provider: ${e.message}")
        }
    }

    private fun processLocation(location: Location) {
        if (locationFilterEnabled) {
            // Reject locations with accuracy worse than threshold
            if (location.accuracy > maxAccuracy) {
                Log.v(TAG, "Filtered: accuracy ${location.accuracy}m > ${maxAccuracy}m")
                return
            }

            val last = lastEmittedLocation
            if (last != null) {
                val timeDeltaSec = (location.time - lastEmittedTime) / 1000.0
                if (timeDeltaSec > 0) {
                    val distance = location.distanceTo(last)
                    val impliedSpeed = distance / timeDeltaSec

                    // Reject impossible speed
                    if (impliedSpeed > maxSpeed) {
                        Log.v(TAG, "Filtered: implied speed ${impliedSpeed}m/s > ${maxSpeed}m/s")
                        return
                    }

                    // Distance filter: don't emit if distance < distanceFilter
                    if (distance < config.distanceFilter) {
                        // Smoothing: if within accuracy radius, weight toward previous
                        if (distance < location.accuracy) {
                            Log.v(TAG, "Filtered: within accuracy radius (${distance}m < ${location.accuracy}m)")
                        }
                        return
                    }
                }

                // Duplicate time threshold
                val timeSince = location.time - lastEmittedTime
                if (timeSince < DUPLICATE_TIME_THRESHOLD) {
                    if (location.accuracy >= last.accuracy) return
                }
            }
        } else {
            // Without filter, still do basic duplicate/distance checks
            val last = lastEmittedLocation
            if (last != null) {
                val timeSince = location.time - lastEmittedTime
                if (timeSince < DUPLICATE_TIME_THRESHOLD) {
                    if (location.accuracy >= last.accuracy) return
                }
                if (config.useSignificantChangesOnly) {
                    val distance = location.distanceTo(last)
                    if (distance < config.distanceFilter) return
                }
            }
        }

        lastEmittedLocation = location
        lastEmittedTime = location.time
        cachedLocation = location

        // Notify location update listeners (e.g., GeofenceManager for distance-based checking)
        for (listener in locationUpdateListeners) {
            listener(location)
        }

        val map = locationToMap(location).toMutableMap()
        map["isMoving"] = isMoving

        onPosition(map)
    }

    // ----- Heartbeat -----

    private fun startHeartbeat() {
        if (config.heartbeatInterval <= 0) return

        val intervalMs = config.heartbeatInterval * 1000L
        heartbeatRunnable = object : Runnable {
            @SuppressLint("MissingPermission")
            override fun run() {
                if (!isTracking) return
                Log.d(TAG, "Heartbeat — emitting current location")

                val lastKnown = try {
                    val provider = providerForAccuracy(config.accuracy)
                    locationManager.getLastKnownLocation(provider)
                        ?: locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                        ?: locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                } catch (_: SecurityException) { null }

                if (lastKnown != null) {
                    val posMap = locationToMap(lastKnown).toMutableMap()
                    posMap["isMoving"] = isMoving
                    cachedLocation = lastKnown

                    // Emit on heartbeat channel with nested position
                    // Matches Dart HeartbeatEvent.fromMap() which expects { "position": {...} }
                    onHeartbeat?.invoke(mapOf("position" to posMap))
                }

                handler.postDelayed(this, intervalMs)
            }
        }
        handler.postDelayed(heartbeatRunnable!!, intervalMs)
        Log.d(TAG, "Heartbeat started: interval=${config.heartbeatInterval}s")
    }

    private fun stopHeartbeat() {
        heartbeatRunnable?.let { handler.removeCallbacks(it) }
        heartbeatRunnable = null
    }

    // ----- Provider Monitoring -----

    private fun startProviderMonitoring() {
        lastProviderState["gps"] = isProviderEnabled(LocationManager.GPS_PROVIDER)
        lastProviderState["network"] = isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        handler.postDelayed(providerCheckRunnable, 10_000L)
    }

    private fun checkProviderChanges() {
        val gpsNow = isProviderEnabled(LocationManager.GPS_PROVIDER)
        val networkNow = isProviderEnabled(LocationManager.NETWORK_PROVIDER)

        if (gpsNow != lastProviderState["gps"] || networkNow != lastProviderState["network"]) {
            lastProviderState["gps"] = gpsNow
            lastProviderState["network"] = networkNow
            reportProviderChange()
        }
    }

    /**
     * Reports provider change matching Dart ProviderEvent format:
     * { "enabled": bool, "status": int, "gps": bool, "network": bool }
     */
    private fun reportProviderChange() {
        val gps = isProviderEnabled(LocationManager.GPS_PROVIDER)
        val network = isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        val state = mapOf(
            "enabled" to (gps || network),
            "status" to if (gps && network) 3 else if (gps || network) 2 else 0,
            "gps" to gps,
            "network" to network,
        )
        providerChangeCallback?.invoke(state)
    }

    private fun isProviderEnabled(provider: String): Boolean {
        return try { locationManager.isProviderEnabled(provider) } catch (_: Exception) { false }
    }

    // ----- Helpers -----

    @SuppressLint("MissingPermission")
    private fun getCachedLocation(accuracy: Int): Location? {
        cachedLocation?.let { return it }
        val provider = providerForAccuracy(accuracy)
        return try {
            locationManager.getLastKnownLocation(provider)
                ?: locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                ?: locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
        } catch (_: SecurityException) { null }
    }

    private fun providerForAccuracy(accuracy: Int): String = when (accuracy) {
        0 -> LocationManager.GPS_PROVIDER
        3 -> LocationManager.PASSIVE_PROVIDER
        else -> LocationManager.NETWORK_PROVIDER
    }

    private fun averageLocations(locations: List<Location>): Location {
        val result = Location(locations.first().provider)
        result.latitude = locations.map { it.latitude }.average()
        result.longitude = locations.map { it.longitude }.average()
        result.altitude = locations.map { it.altitude }.average()
        result.accuracy = locations.map { it.accuracy }.average().toFloat()
        result.speed = locations.map { it.speed }.average().toFloat()
        result.bearing = locations.map { it.bearing.toDouble() }.average().toFloat()
        result.time = locations.maxOf { it.time }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            result.elapsedRealtimeNanos = locations.maxOf { it.elapsedRealtimeNanos }
        }
        return result
    }

    private fun locationToMap(location: Location): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "altitude" to location.altitude,
            "accuracy" to location.accuracy.toDouble(),
            "speed" to location.speed.toDouble(),
            "heading" to location.bearing.toDouble(),
            "timestamp" to location.time,
            "provider" to (location.provider ?: "unknown"),
            "isMoving" to isMoving,
        )

        // Battery info via sticky broadcast (works without registering a receiver)
        try {
            val batteryIntent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (batteryIntent != null) {
                val level = batteryIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = batteryIntent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                if (level >= 0 && scale > 0) {
                    map["batteryLevel"] = (level * 100) / scale
                }
                val status = batteryIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                map["isCharging"] = (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read battery info: ${e.message}")
        }

        return map
    }
}
