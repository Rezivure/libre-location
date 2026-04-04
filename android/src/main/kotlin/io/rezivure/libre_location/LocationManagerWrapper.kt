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
        private const val GATE_CHECK_COOLDOWN_MS = 60_000L
    }

    // GPS filter config
    private var locationFilterEnabled: Boolean = true
    private var maxAccuracy: Float = 100f
    private var maxSpeed: Float = 83.33f // ~300 km/h

    // Kalman filter for GPS smoothing
    private val kalmanFilter = KalmanFilter()

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

    // Motion change tracking — allows first emission after motion state change to bypass time filter
    private var motionChangeOccurred = false

    // Cooldown for distance gate checks to prevent indoor motion spam
    private var lastGateCheckTime: Long = 0

    private var providerChangeCallback: ((Map<String, Any?>) -> Unit)? = null
    private var locationUpdateListeners = mutableListOf<(Location) -> Unit>()
    private var lastProviderState = mutableMapOf<String, Boolean>()

    private var heartbeatRunnable: Runnable? = null

    private val activeListeners = CopyOnWriteArrayList<LocationListener>()

    // ----- Stop Detection State Machine -----
    // GPS-speed-only: when speed < 0.5 m/s for stillnessTimeoutMs, transition to stationary.
    private var stopDetectionTimer: Runnable? = null
    private var lastMovementTime: Long = 0L  // last time speed > 0.5 m/s

    // ----- Home Geofence (stationary mode) -----
    private var homeGeofenceCenter: Location? = null
    private var homeGeofenceRadius: Float = 150f

    private val PREFS_NAME = "libre_location_home"
    private val PREF_HOME_LAT = "home_lat"
    private val PREF_HOME_LNG = "home_lng"
    private val PREF_HOME_RADIUS = "home_radius"
    private val PREF_HOME_TIME = "home_time"

    /** Callback invoked when the wrapper's own isMoving state changes. */
    private var motionStateCallback: ((Boolean) -> Unit)? = null

    fun setMotionStateCallback(callback: (Boolean) -> Unit) {
        motionStateCallback = callback
    }

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

    /** Passive provider listener for stationary mode — checks distance from home on each update. */
    private val passiveListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            if (!isMoving) checkDistanceFromHome(location)
        }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
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
        lastGateCheckTime = 0
        kalmanFilter.reset()
        locationFilterEnabled = config.locationFilterEnabled
        maxAccuracy = config.maxAccuracy
        maxSpeed = config.maxSpeed

        // Check for persisted home point (process death recovery)
        restoreHomeIfNeeded()

        if (isMoving) {
            registerProviders()
            lastMovementTime = System.currentTimeMillis()
            restartStopDetectionTimer()
        }
        startHeartbeat()
        startProviderMonitoring()

        Log.d(TAG, "Tracking started: mode=${config.mode}, accuracy=${config.accuracy}, filter=$locationFilterEnabled, isMoving=$isMoving")
    }

    fun stopTracking() {
        isTracking = false
        cancelStopDetectionTimer()
        homeGeofenceCenter = null
        locationManager.removeUpdates(primaryListener)
        locationManager.removeUpdates(secondaryListener)
        locationManager.removeUpdates(passiveListener)
        activeListeners.forEach { locationManager.removeUpdates(it) }
        activeListeners.clear()
        stopHeartbeat()
        handler.removeCallbacks(providerCheckRunnable)
        clearPersistedHome()
        Log.d(TAG, "Tracking stopped")
    }

    @SuppressLint("MissingPermission")
    fun setConfig(newConfig: TrackingConfig) {
        val wasTracking = isTracking
        this.config = newConfig
        locationFilterEnabled = newConfig.locationFilterEnabled
        maxAccuracy = newConfig.maxAccuracy
        maxSpeed = newConfig.maxSpeed

        if (wasTracking) {
            // Only re-register providers if currently moving (GPS active).
            // When stationary, GPS is off and we must NOT re-engage it.
            if (isMoving) {
                locationManager.removeUpdates(primaryListener)
                locationManager.removeUpdates(secondaryListener)
                registerProviders()
            }
            // Heartbeat can always be updated
            stopHeartbeat()
            startHeartbeat()
        }

        Log.d(TAG, "Config updated dynamically (isMoving=$isMoving)")
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

    /**
     * Called when accelerometer detects motion while stationary.
     * Instead of directly waking GPS, requests a single network location
     * and checks distance from home point (distance gate).
     */
    @SuppressLint("MissingPermission")
    fun onMotionDetectedGated() {
        if (!isTracking) return
        if (isMoving) return  // already moving, no-op

        val now = System.currentTimeMillis()
        if (now - lastGateCheckTime < GATE_CHECK_COOLDOWN_MS) {
            Log.d(TAG, "Motion gate cooldown active — ignoring (${now - lastGateCheckTime}ms since last check)")
            return
        }
        lastGateCheckTime = now

        Log.d(TAG, "Motion detected (gated) — requesting network location for distance check")

        requestSingleNetworkLocation { location ->
            if (!isTracking || isMoving) return@requestSingleNetworkLocation
            if (location != null) {
                checkDistanceFromHome(location)
            } else {
                // Network unavailable — check age of last known location
                val lastTime = lastEmittedLocation?.time ?: 0L
                val age = System.currentTimeMillis() - lastTime
                if (age > 30 * 60 * 1000) { // 30 min stale
                    Log.d(TAG, "Network unavailable, last location stale (${age}ms) — transitioning to MOVING")
                    transitionToMoving()
                } else {
                    Log.d(TAG, "Network unavailable but last location fresh — staying STATIONARY")
                }
            }
        }
    }

    /**
     * Manually override motion state. Used by setMoving API.
     */
    fun setMoving(moving: Boolean) {
        if (!isTracking) return
        cancelStopDetectionTimer()
        if (moving) {
            if (!isMoving) transitionToMoving()
        } else {
            if (isMoving) transitionToStationary()
        }
    }

    // ----- State Transitions -----

    @SuppressLint("MissingPermission")
    fun transitionToStationary() {
        isMoving = false
        Log.d(TAG, "Transitioning to STATIONARY — stopping GPS, recording home point")

        // Record home point
        homeGeofenceCenter = lastEmittedLocation?.let { Location(it) }
        homeGeofenceRadius = config.stillnessRadiusMeters

        // Stop GPS, keep passive
        locationManager.removeUpdates(primaryListener)
        locationManager.removeUpdates(secondaryListener)
        requestUpdatesIfAvailable(LocationManager.PASSIVE_PROVIDER, passiveListener)

        // Persist home point for process death recovery
        persistHome()

        cancelStopDetectionTimer()
        motionStateCallback?.invoke(false)
    }

    @SuppressLint("MissingPermission")
    fun transitionToMoving() {
        isMoving = true
        homeGeofenceCenter = null
        motionChangeOccurred = true
        lastGateCheckTime = 0
        Log.d(TAG, "Transitioning to MOVING — re-engaging GPS")

        // Remove passive listener
        locationManager.removeUpdates(passiveListener)

        // Clear persisted home
        clearPersistedHome()

        // Re-engage GPS
        registerProviders()

        // Reset stop detection
        lastMovementTime = System.currentTimeMillis()
        restartStopDetectionTimer()

        motionStateCallback?.invoke(true)
    }

    // ----- Distance Check -----

    private fun checkDistanceFromHome(location: Location) {
        val home = homeGeofenceCenter ?: return
        val distance = location.distanceTo(home)
        if (distance > homeGeofenceRadius) {
            Log.d(TAG, "Distance from home: ${distance}m > ${homeGeofenceRadius}m — transitioning to MOVING")
            transitionToMoving()
        } else {
            Log.v(TAG, "Distance from home: ${distance}m ≤ ${homeGeofenceRadius}m — staying STATIONARY")
        }
    }

    // ----- Network Location Request -----

    @SuppressLint("MissingPermission")
    private fun requestSingleNetworkLocation(callback: (Location?) -> Unit) {
        var completed = false
        try {
            val listener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    if (completed) return
                    completed = true
                    locationManager.removeUpdates(this)
                    callback(location)
                }
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {
                    if (completed) return
                    completed = true
                    locationManager.removeUpdates(this)
                    callback(null)
                }
                @Deprecated("Deprecated in API")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            }
            locationManager.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER, 0L, 0f, listener, Looper.getMainLooper()
            )
            // Timeout after 10s
            handler.postDelayed({
                if (completed) return@postDelayed
                completed = true
                locationManager.removeUpdates(listener)
                val lastKnown = try {
                    locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                } catch (_: SecurityException) { null }
                callback(lastKnown)
            }, 10_000L)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to request network location: ${e.message}")
            if (!completed) {
                completed = true
                callback(null)
            }
        }
    }

    // ----- Stop Detection Timer (GPS-speed-only) -----

    /**
     * Called from processLocation when speed data is available.
     * Resets lastMovementTime when speed > 0.5 m/s.
     */
    private fun updateStopDetection(location: Location) {
        if (!isMoving || !isTracking) return
        if (location.hasSpeed() && location.speed > 0.5f) {
            lastMovementTime = System.currentTimeMillis()
        }
    }

    private fun restartStopDetectionTimer() {
        cancelStopDetectionTimer()
        val timeoutMs = config.stillnessTimeoutMs
        val runnable = Runnable { checkStopDetection() }
        stopDetectionTimer = runnable
        handler.postDelayed(runnable, timeoutMs)
    }

    private fun checkStopDetection() {
        if (!isTracking || !isMoving) return
        val elapsed = System.currentTimeMillis() - lastMovementTime
        val timeoutMs = config.stillnessTimeoutMs
        if (elapsed >= timeoutMs) {
            Log.d(TAG, "Stop detection: no movement for ${elapsed}ms — transitioning to STATIONARY")
            transitionToStationary()
        } else {
            // Reschedule for remaining time
            val remaining = timeoutMs - elapsed
            val runnable = Runnable { checkStopDetection() }
            stopDetectionTimer = runnable
            handler.postDelayed(runnable, remaining)
        }
    }

    private fun cancelStopDetectionTimer() {
        stopDetectionTimer?.let {
            handler.removeCallbacks(it)
            stopDetectionTimer = null
        }
    }

    // ----- Home Point Persistence -----

    private fun persistHome() {
        val home = homeGeofenceCenter ?: return
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(PREF_HOME_LAT, java.lang.Double.doubleToRawLongBits(home.latitude))
            .putLong(PREF_HOME_LNG, java.lang.Double.doubleToRawLongBits(home.longitude))
            .putFloat(PREF_HOME_RADIUS, homeGeofenceRadius)
            .putLong(PREF_HOME_TIME, home.time)
            .apply()
    }

    private fun clearPersistedHome() {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().clear().apply()
    }

    /**
     * Restores home point from SharedPreferences after process death.
     * Called during startTracking if a persisted home exists.
     */
    @SuppressLint("MissingPermission")
    private fun restoreHomeIfNeeded() {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.contains(PREF_HOME_TIME)) return

        val lat = java.lang.Double.longBitsToDouble(prefs.getLong(PREF_HOME_LAT, 0L))
        val lng = java.lang.Double.longBitsToDouble(prefs.getLong(PREF_HOME_LNG, 0L))
        val radius = prefs.getFloat(PREF_HOME_RADIUS, 150f)
        val time = prefs.getLong(PREF_HOME_TIME, 0L)

        if (lat == 0.0 && lng == 0.0) return

        val home = Location("restored").apply {
            latitude = lat
            longitude = lng
            this.time = time
        }
        homeGeofenceCenter = home
        homeGeofenceRadius = radius
        isMoving = false

        // Register passive provider
        requestUpdatesIfAvailable(LocationManager.PASSIVE_PROVIDER, passiveListener)

        Log.d(TAG, "Restored home point from SharedPreferences: ($lat, $lng) radius=${radius}m")

        // Check if we've moved since process death
        requestSingleNetworkLocation { location ->
            if (location != null) checkDistanceFromHome(location)
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
                // Enforce 50m minimum distance filter for active providers (GPS/network) while moving
                val effectiveDistanceFilter = if (provider != LocationManager.PASSIVE_PROVIDER && isMoving) {
                    maxOf(config.distanceFilter, 50f)
                } else {
                    config.distanceFilter
                }
                locationManager.requestLocationUpdates(
                    provider, config.intervalMs, effectiveDistanceFilter, listener, Looper.getMainLooper()
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
                if (config.significantChangesOnly) {
                    val distance = location.distanceTo(last)
                    if (distance < config.distanceFilter) return
                }
            }
        }

        // Apply Kalman filter for GPS smoothing (if filtering enabled)
        val smoothed = if (locationFilterEnabled) {
            // Reset if accuracy changed dramatically (>5x)
            kalmanFilter.lastAccuracy?.let { lastAcc ->
                if (lastAcc > 0 && location.accuracy > 0) {
                    val ratio = location.accuracy / lastAcc
                    if (ratio > 5.0f || ratio < 0.2f) {
                        kalmanFilter.reset()
                    }
                }
            }

            kalmanFilter.process(
                location.latitude,
                location.longitude,
                location.accuracy.toDouble(),
                location.time / 1000.0
            )

            if (kalmanFilter.lat != null) {
                Location(location).apply {
                    latitude = kalmanFilter.lat!!
                    longitude = kalmanFilter.lng!!
                }
            } else {
                location
            }
        } else {
            location
        }

        // Software distance filter (post-Kalman): enforce distanceFilter as hard limit
        // Android's setSmallestDisplacement is respected better than iOS but add software backup
        if (locationFilterEnabled) {
            val last = lastEmittedLocation
            if (last != null) {
                val distance = smoothed.distanceTo(last)
                if (distance < config.distanceFilter) {
                    Log.v(TAG, "Software distance filter: ${distance}m < ${config.distanceFilter}m")
                    return
                }
            }

            // Software time filter: enforce intervalMs as minimum emission interval
            val isMotionChangeBypass = motionChangeOccurred && location.speed > 0
            if (lastEmittedTime > 0 && !isMotionChangeBypass) {
                val elapsedMs = location.time - lastEmittedTime
                if (elapsedMs < config.intervalMs) {
                    Log.v(TAG, "Software time filter: ${elapsedMs}ms < ${config.intervalMs}ms")
                    return
                }
            }
        }

        lastEmittedLocation = smoothed
        lastEmittedTime = smoothed.time
        cachedLocation = smoothed
        motionChangeOccurred = false

        // Feed stop detection (GPS-speed-only)
        updateStopDetection(smoothed)

        // Notify location update listeners (e.g., GeofenceManager for distance-based checking)
        for (listener in locationUpdateListeners) {
            listener(smoothed)
        }

        val map = locationToMap(smoothed).toMutableMap()
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

    // ----- Kalman Filter -----

    /**
     * Simple 1D Kalman filter applied independently to latitude and longitude.
     * Smooths GPS jitter while preserving real movement.
     */
    private class KalmanFilter {
        var lat: Double? = null
            private set
        var lng: Double? = null
            private set
        var lastAccuracy: Float? = null
            private set

        private var variance: Double = 0.0
        private var lastTimestamp: Double = 0.0

        /** Process noise in m²/s — higher = trusts new readings more. */
        private val processNoise: Double = 3.0

        fun process(lat: Double, lng: Double, accuracy: Double, timestampSec: Double) {
            if (accuracy <= 0) return

            if (this.lat == null) {
                this.lat = lat
                this.lng = lng
                this.variance = accuracy * accuracy
                this.lastTimestamp = timestampSec
                this.lastAccuracy = accuracy.toFloat()
                return
            }

            // Add process noise based on time elapsed
            val timeDelta = maxOf(0.0, timestampSec - lastTimestamp)
            variance += timeDelta * processNoise

            // Kalman gain
            val measurementVariance = accuracy * accuracy
            val K = variance / (variance + measurementVariance)

            // Update estimates
            this.lat = this.lat!! + K * (lat - this.lat!!)
            this.lng = this.lng!! + K * (lng - this.lng!!)

            // Update variance
            this.variance = (1.0 - K) * variance

            this.lastTimestamp = timestampSec
            this.lastAccuracy = accuracy.toFloat()
        }

        fun reset() {
            lat = null
            lng = null
            variance = 0.0
            lastTimestamp = 0.0
            lastAccuracy = null
        }
    }
}
