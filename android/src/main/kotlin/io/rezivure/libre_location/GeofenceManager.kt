package io.rezivure.libre_location

import android.content.Context
import android.location.Location
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Custom geofence manager using distance-based checking on every location update.
 * NO Google Play Services, NO deprecated ProximityAlert.
 *
 * On each location update, calculates distance from every registered geofence center
 * and triggers enter/exit/dwell events based on distance vs radius.
 *
 * Thread-safe: all state is accessed on the main looper via [handler].
 */
class GeofenceManager(
    private val context: Context,
    private val onGeofenceEvent: (Map<String, Any?>) -> Unit,
) {

    companion object {
        private const val TAG = "LibreGeofenceMgr"
    }

    private val handler = Handler(Looper.getMainLooper())

    private val geofences = mutableMapOf<String, GeofenceData>()
    private val insideStates = mutableMapOf<String, Boolean>()  // true = currently inside
    private val dwellRunnables = mutableMapOf<String, Runnable>()

    data class GeofenceData(
        val id: String,
        val latitude: Double,
        val longitude: Double,
        val radiusMeters: Float,
        val triggers: List<Int>,  // 0=enter, 1=exit, 2=dwell
        val dwellDurationMs: Long?,
    )

    /**
     * Called on every location update. Checks all geofences for enter/exit transitions.
     * Should be called from [LocationManagerWrapper.processLocation].
     */
    fun onLocationUpdate(location: Location) {
        for ((id, geofence) in geofences) {
            val center = Location("geofence").apply {
                latitude = geofence.latitude
                longitude = geofence.longitude
            }
            val distance = location.distanceTo(center)
            val wasInside = insideStates[id] ?: false
            val isInside = distance <= geofence.radiusMeters

            if (isInside && !wasInside) {
                // Entered
                insideStates[id] = true
                if (geofence.triggers.contains(0)) {
                    emitEvent(geofence, 0)
                }
                // Start dwell timer
                if (geofence.triggers.contains(2) && geofence.dwellDurationMs != null && geofence.dwellDurationMs > 0) {
                    startDwellTimer(geofence)
                }
            } else if (!isInside && wasInside) {
                // Exited
                insideStates[id] = false
                cancelDwellTimer(id)
                if (geofence.triggers.contains(1)) {
                    emitEvent(geofence, 1)
                }
            }
        }
    }

    fun addGeofence(
        id: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Float,
        triggers: List<Int>,
        dwellDurationMs: Long?,
    ) {
        val data = GeofenceData(id, latitude, longitude, radiusMeters, triggers, dwellDurationMs)
        geofences[id] = data
        // Initialize inside state as unknown (false) — will be determined on next location update
        insideStates[id] = false
        Log.d(TAG, "Added geofence: $id at ($latitude, $longitude) r=${radiusMeters}m")
    }

    fun removeGeofence(id: String) {
        cancelDwellTimer(id)
        geofences.remove(id)
        insideStates.remove(id)
        Log.d(TAG, "Removed geofence: $id")
    }

    fun removeAllGeofences() {
        val ids = geofences.keys.toList()
        for (id in ids) {
            removeGeofence(id)
        }
    }

    fun getGeofences(): List<Map<String, Any?>> {
        return geofences.values.map { g ->
            mapOf(
                "id" to g.id,
                "latitude" to g.latitude,
                "longitude" to g.longitude,
                "radiusMeters" to g.radiusMeters.toDouble(),
                "triggers" to g.triggers,
                "dwellDurationMs" to g.dwellDurationMs,
            )
        }
    }

    fun destroy() {
        dwellRunnables.keys.toList().forEach { cancelDwellTimer(it) }
        geofences.clear()
        insideStates.clear()
    }

    // ----- Dwell Timer -----

    private fun startDwellTimer(geofence: GeofenceData) {
        cancelDwellTimer(geofence.id)
        val runnable = Runnable {
            // Verify still inside before emitting dwell
            if (insideStates[geofence.id] == true) {
                emitEvent(geofence, 2)
            }
            dwellRunnables.remove(geofence.id)
        }
        dwellRunnables[geofence.id] = runnable
        handler.postDelayed(runnable, geofence.dwellDurationMs ?: 0L)
    }

    private fun cancelDwellTimer(id: String) {
        dwellRunnables[id]?.let { handler.removeCallbacks(it) }
        dwellRunnables.remove(id)
    }

    // ----- Event Emission -----

    private fun emitEvent(geofence: GeofenceData, transition: Int) {
        onGeofenceEvent(mapOf(
            "geofence" to mapOf(
                "id" to geofence.id,
                "latitude" to geofence.latitude,
                "longitude" to geofence.longitude,
                "radiusMeters" to geofence.radiusMeters.toDouble(),
                "triggers" to geofence.triggers,
            ),
            "transition" to transition,
            "timestamp" to System.currentTimeMillis(),
        ))
    }
}
