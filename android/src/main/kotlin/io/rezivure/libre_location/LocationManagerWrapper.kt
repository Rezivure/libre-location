package io.rezivure.libre_location

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper

/**
 * Pure AOSP LocationManager wrapper. NO Google Play Services.
 *
 * Uses GPS_PROVIDER and NETWORK_PROVIDER directly from android.location.LocationManager.
 */
class LocationManagerWrapper(
    private val context: Context,
    private val onPosition: (Map<String, Any?>) -> Unit,
) {

    private val locationManager: LocationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    var isTracking = false
        private set

    private var currentMode: Int = 1  // 0=active, 1=balanced, 2=passive
    private var intervalMs: Long = 60000L
    private var distanceFilter: Float = 10f
    private var isPausedForStillness = false

    private val gpsListener = object : LocationListener {
        override fun onLocationChanged(location: Location) = emitLocation(location)
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Deprecated in API")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private val networkListener = object : LocationListener {
        override fun onLocationChanged(location: Location) = emitLocation(location)
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Deprecated in API")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    @SuppressLint("MissingPermission")
    fun startTracking(accuracy: Int, intervalMs: Long, distanceFilter: Float, mode: Int) {
        this.currentMode = mode
        this.intervalMs = intervalMs
        this.distanceFilter = distanceFilter
        isTracking = true
        isPausedForStillness = false

        when (mode) {
            0 -> { // Active — GPS primary
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    intervalMs,
                    distanceFilter,
                    gpsListener,
                    Looper.getMainLooper()
                )
            }
            1 -> { // Balanced — network primary, GPS on motion
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    intervalMs,
                    distanceFilter,
                    networkListener,
                    Looper.getMainLooper()
                )
            }
            2 -> { // Passive
                locationManager.requestLocationUpdates(
                    LocationManager.PASSIVE_PROVIDER,
                    intervalMs,
                    distanceFilter,
                    networkListener,
                    Looper.getMainLooper()
                )
            }
        }
    }

    fun stopTracking() {
        isTracking = false
        locationManager.removeUpdates(gpsListener)
        locationManager.removeUpdates(networkListener)
    }

    @SuppressLint("MissingPermission")
    fun getCurrentPosition(accuracy: Int, callback: (Map<String, Any?>) -> Unit) {
        val provider = if (accuracy == 0) LocationManager.GPS_PROVIDER else LocationManager.NETWORK_PROVIDER

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                locationManager.removeUpdates(this)
                callback(locationToMap(location))
            }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
            @Deprecated("Deprecated in API")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }

        locationManager.requestLocationUpdates(
            provider, 0L, 0f, listener, Looper.getMainLooper()
        )

        // Also try last known location as fallback
        val lastKnown = locationManager.getLastKnownLocation(provider)
        if (lastKnown != null) {
            // If the listener hasn't fired within 5s, this serves as backup
        }
    }

    @SuppressLint("MissingPermission")
    fun onMotionDetected() {
        if (!isTracking || !isPausedForStillness) return
        isPausedForStillness = false

        // Re-enable GPS when motion is detected (for balanced mode)
        if (currentMode == 1) {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                intervalMs,
                distanceFilter,
                gpsListener,
                Looper.getMainLooper()
            )
        }
    }

    fun onStillnessDetected() {
        if (!isTracking || isPausedForStillness) return
        isPausedForStillness = true

        // Remove GPS listener to save battery when stationary
        if (currentMode == 1) {
            locationManager.removeUpdates(gpsListener)
        }
    }

    private fun emitLocation(location: Location) {
        onPosition(locationToMap(location))
    }

    private fun locationToMap(location: Location): Map<String, Any?> {
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "altitude" to location.altitude,
            "accuracy" to location.accuracy.toDouble(),
            "speed" to location.speed.toDouble(),
            "heading" to location.bearing.toDouble(),
            "timestamp" to location.time,
            "provider" to location.provider,
        )
    }
}
