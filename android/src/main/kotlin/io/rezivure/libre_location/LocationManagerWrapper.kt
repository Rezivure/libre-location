package io.rezivure.libre_location

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.LocationProvider
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Production-grade AOSP LocationManager wrapper. Zero Google Play Services.
 *
 * Features:
 * - Multi-provider tracking (GPS, Network, Passive) with automatic selection
 * - getCurrentPosition with multi-sample averaging, timeout, and maximumAge caching
 * - Dynamic configuration updates without restart
 * - Provider change detection and reporting
 * - Heartbeat emissions for guaranteed periodic updates
 * - isMoving state tracking with motion-adaptive accuracy
 * - Location filtering (accuracy gate, duplicate suppression)
 */
class LocationManagerWrapper(
    private val context: Context,
    private val onPosition: (Map<String, Any?>) -> Unit,
) {

    companion object {
        private const val TAG = "LibreLocationMgr"
        private const val MIN_ACCURACY_THRESHOLD = 100f  // reject locations > 100m accuracy
        private const val DUPLICATE_TIME_THRESHOLD = 1000L  // 1s duplicate suppression
    }

    private val locationManager: LocationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())

    var isTracking = false
        private set
    var isMoving: Boolean = true
        private set

    // Current configuration
    private var config: TrackingConfig = TrackingConfig()

    // Last emitted location for duplicate/distance filtering
    private var lastEmittedLocation: Location? = null
    private var lastEmittedTime: Long = 0L

    // Cached last known location (for maximumAge queries)
    private var cachedLocation: Location? = null

    // Provider state tracking
    private var providerChangeCallback: ((Map<String, Any?>) -> Unit)? = null
    private var lastProviderState = mutableMapOf<String, Boolean>()

    // Heartbeat
    private var heartbeatRunnable: Runnable? = null

    // Active listeners for cleanup
    private val activeListeners = CopyOnWriteArrayList<LocationListener>()

    // ----- Primary Location Listener -----

    private val primaryListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            processLocation(location)
        }

        override fun onLocationChanged(locations: MutableList<Location>) {
            // Batch delivery (API 31+): process the most recent
            locations.lastOrNull()?.let { processLocation(it) }
        }

        override fun onProviderEnabled(provider: String) {
            Log.d(TAG, "Provider enabled: $provider")
            reportProviderChange(provider, true)
        }

        override fun onProviderDisabled(provider: String) {
            Log.d(TAG, "Provider disabled: $provider")
            reportProviderChange(provider, false)
        }

        @Deprecated("Deprecated in API")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
            Log.d(TAG, "Provider status changed: $provider -> $status")
        }
    }

    private val secondaryListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            processLocation(location)
        }
        override fun onProviderEnabled(provider: String) { reportProviderChange(provider, true) }
        override fun onProviderDisabled(provider: String) { reportProviderChange(provider, false) }
        @Deprecated("Deprecated in API")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    // ----- Provider Change Detection -----

    private val providerCheckRunnable = object : Runnable {
        override fun run() {
            if (!isTracking) return
            checkProviderChanges()
            handler.postDelayed(this, 10_000L) // check every 10s
        }
    }

    /**
     * Starts location tracking with the given configuration.
     */
    @SuppressLint("MissingPermission")
    fun startTracking(config: TrackingConfig) {
        this.config = config
        isTracking = true
        isMoving = true

        registerProviders()
        startHeartbeat()
        startProviderMonitoring()

        Log.d(TAG, "Tracking started: mode=${config.mode}, accuracy=${config.accuracy}, " +
                "interval=${config.intervalMs}ms, distance=${config.distanceFilter}m")
    }

    /**
     * Legacy signature for backward compatibility.
     */
    @SuppressLint("MissingPermission")
    fun startTracking(accuracy: Int, intervalMs: Long, distanceFilter: Float, mode: Int) {
        startTracking(TrackingConfig(
            accuracy = accuracy,
            intervalMs = intervalMs,
            distanceFilter = distanceFilter,
            mode = mode,
        ))
    }

    /**
     * Stops all location tracking.
     */
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

    /**
     * Dynamically reconfigures tracking parameters without restart.
     */
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

    /**
     * Gets the current position with optional multi-sample averaging.
     *
     * @param accuracy Desired accuracy (0=high/GPS, 1=balanced, 2=low, 3=passive)
     * @param samples Number of readings to average (1=single)
     * @param timeoutMs Maximum time to wait for a fix
     * @param maximumAgeMs Return cached location if fresher than this
     * @param persist Whether to persist the result to the database
     * @param callback Delivers the position map
     */
    @SuppressLint("MissingPermission")
    fun getCurrentPosition(
        accuracy: Int = 0,
        samples: Int = 1,
        timeoutMs: Long = 30_000L,
        maximumAgeMs: Long = 0L,
        persist: Boolean = false,
        callback: (Map<String, Any?>) -> Unit
    ) {
        // Check cached location first
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
                    val map = locationToMap(averaged)
                    callback(map)
                }
            }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
            @Deprecated("Deprecated in API")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }

        activeListeners.add(listener)
        locationManager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())

        // Timeout handler
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
                // Fall back to last known
                val fallback = getCachedLocation(accuracy)
                if (fallback != null) {
                    callback(locationToMap(fallback))
                } else {
                    callback(mapOf(
                        "error" to "timeout",
                        "message" to "Could not obtain location within ${timeoutMs}ms"
                    ))
                }
            }
        }, timeoutMs)
    }

    /**
     * Legacy getCurrentPosition signature for backward compatibility.
     */
    @SuppressLint("MissingPermission")
    fun getCurrentPosition(accuracy: Int, callback: (Map<String, Any?>) -> Unit) {
        getCurrentPosition(accuracy = accuracy, callback = callback)
    }

    // ----- Motion State -----

    /**
     * Called by MotionDetector when motion is detected.
     */
    @SuppressLint("MissingPermission")
    fun onMotionDetected() {
        if (!isTracking) return
        val wasStationary = !isMoving
        isMoving = true

        if (wasStationary && config.mode == 1) {
            // Re-enable GPS for balanced mode
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                config.intervalMs,
                config.distanceFilter,
                primaryListener,
                Looper.getMainLooper()
            )
            Log.d(TAG, "Motion detected — GPS re-engaged")
        }
    }

    /**
     * Called by MotionDetector when stillness is detected.
     */
    fun onStillnessDetected() {
        if (!isTracking) return
        val wasMoving = isMoving
        isMoving = false

        if (wasMoving && config.mode == 1) {
            // Remove GPS in balanced mode to save battery
            locationManager.removeUpdates(primaryListener)
            Log.d(TAG, "Stillness detected — GPS paused (network only)")
        }
    }

    /**
     * Sets a callback for provider changes (GPS on/off, etc.).
     */
    fun setProviderChangeCallback(callback: (Map<String, Any?>) -> Unit) {
        providerChangeCallback = callback
    }

    // ----- Internal -----

    @SuppressLint("MissingPermission")
    private fun registerProviders() {
        when (config.mode) {
            0 -> { // Active — GPS primary + network secondary
                requestUpdatesIfAvailable(LocationManager.GPS_PROVIDER, primaryListener)
                requestUpdatesIfAvailable(LocationManager.NETWORK_PROVIDER, secondaryListener)
            }
            1 -> { // Balanced — network primary, GPS on motion
                requestUpdatesIfAvailable(LocationManager.NETWORK_PROVIDER, primaryListener)
                if (isMoving) {
                    requestUpdatesIfAvailable(LocationManager.GPS_PROVIDER, secondaryListener)
                }
            }
            2 -> { // Passive
                requestUpdatesIfAvailable(LocationManager.PASSIVE_PROVIDER, primaryListener)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestUpdatesIfAvailable(provider: String, listener: LocationListener) {
        try {
            if (locationManager.isProviderEnabled(provider)) {
                locationManager.requestLocationUpdates(
                    provider, config.intervalMs, config.distanceFilter, listener, Looper.getMainLooper()
                )
            } else if (provider == LocationManager.PASSIVE_PROVIDER) {
                // Passive is always available
                locationManager.requestLocationUpdates(
                    provider, config.intervalMs, config.distanceFilter, listener, Looper.getMainLooper()
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register $provider: ${e.message}")
        }
    }

    private fun processLocation(location: Location) {
        // Accuracy gate
        if (location.accuracy > MIN_ACCURACY_THRESHOLD && config.accuracy <= 1) {
            Log.v(TAG, "Rejected location: accuracy ${location.accuracy}m > threshold")
            return
        }

        // Duplicate suppression
        val now = SystemClock.elapsedRealtime()
        val last = lastEmittedLocation
        if (last != null) {
            val timeSince = location.time - lastEmittedTime
            if (timeSince < DUPLICATE_TIME_THRESHOLD) {
                // Keep the more accurate one
                if (location.accuracy >= last.accuracy) return
            }

            // Distance filter (for significant changes mode)
            if (config.useSignificantChangesOnly) {
                val distance = location.distanceTo(last)
                if (distance < config.distanceFilter) return
            }
        }

        lastEmittedLocation = location
        lastEmittedTime = location.time
        cachedLocation = location

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

                // Try to get a fresh location; fall back to cached
                val provider = providerForAccuracy(config.accuracy)
                val lastKnown = try {
                    locationManager.getLastKnownLocation(provider)
                        ?: locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                        ?: locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                } catch (_: SecurityException) { null }

                if (lastKnown != null) {
                    val map = locationToMap(lastKnown).toMutableMap()
                    map["isMoving"] = isMoving
                    map["isHeartbeat"] = true
                    onPosition(map)
                    cachedLocation = lastKnown
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
        // Capture initial state
        lastProviderState["gps"] = isProviderEnabled(LocationManager.GPS_PROVIDER)
        lastProviderState["network"] = isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        handler.postDelayed(providerCheckRunnable, 10_000L)
    }

    private fun checkProviderChanges() {
        val gpsNow = isProviderEnabled(LocationManager.GPS_PROVIDER)
        val networkNow = isProviderEnabled(LocationManager.NETWORK_PROVIDER)

        if (gpsNow != lastProviderState["gps"]) {
            reportProviderChange(LocationManager.GPS_PROVIDER, gpsNow)
            lastProviderState["gps"] = gpsNow
        }
        if (networkNow != lastProviderState["network"]) {
            reportProviderChange(LocationManager.NETWORK_PROVIDER, networkNow)
            lastProviderState["network"] = networkNow
        }
    }

    private fun reportProviderChange(provider: String, enabled: Boolean) {
        val state = mapOf(
            "provider" to provider,
            "enabled" to enabled,
            "gps" to isProviderEnabled(LocationManager.GPS_PROVIDER),
            "network" to isProviderEnabled(LocationManager.NETWORK_PROVIDER),
            "timestamp" to System.currentTimeMillis(),
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

    private fun locationToMap(location: Location): Map<String, Any?> = mapOf(
        "latitude" to location.latitude,
        "longitude" to location.longitude,
        "altitude" to location.altitude,
        "accuracy" to location.accuracy.toDouble(),
        "speed" to location.speed.toDouble(),
        "heading" to location.bearing.toDouble(),
        "timestamp" to location.time,
        "provider" to (location.provider ?: "unknown"),
    )
}
