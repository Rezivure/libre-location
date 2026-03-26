package io.rezivure.libre_location

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Geofence manager using pure AOSP LocationManager.addProximityAlert().
 * NO Google Play Services.
 *
 * Supports enter, exit, and dwell events (dwell via timer after enter).
 */
class GeofenceManager(
    private val context: Context,
    private val onGeofenceEvent: (Map<String, Any?>) -> Unit,
) {

    companion object {
        private const val TAG = "LibreGeofenceMgr"
        private const val ACTION_GEOFENCE = "io.rezivure.libre_location.GEOFENCE"
    }

    private val locationManager: LocationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())

    private val geofences = mutableMapOf<String, GeofenceData>()
    private val pendingIntents = mutableMapOf<String, PendingIntent>()
    private val dwellRunnables = mutableMapOf<String, Runnable>()

    data class GeofenceData(
        val id: String,
        val latitude: Double,
        val longitude: Double,
        val radiusMeters: Float,
        val triggers: List<Int>,  // 0=enter, 1=exit, 2=dwell
        val dwellDurationMs: Long?,
    )

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val id = intent?.getStringExtra("geofence_id") ?: return
            val entering = intent.getBooleanExtra(LocationManager.KEY_PROXIMITY_ENTERING, false)
            val geofence = geofences[id] ?: return

            if (entering) {
                // Enter event
                if (geofence.triggers.contains(0)) {
                    emitEvent(geofence, 0)
                }
                // Start dwell timer if dwell is a trigger
                if (geofence.triggers.contains(2) && geofence.dwellDurationMs != null && geofence.dwellDurationMs > 0) {
                    startDwellTimer(geofence)
                }
            } else {
                // Exit event
                cancelDwellTimer(id)
                if (geofence.triggers.contains(1)) {
                    emitEvent(geofence, 1)
                }
            }
        }
    }

    init {
        val filter = IntentFilter(ACTION_GEOFENCE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    @SuppressLint("MissingPermission")
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

        val intent = Intent(ACTION_GEOFENCE).apply {
            setPackage(context.packageName)
            putExtra("geofence_id", id)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        val pi = PendingIntent.getBroadcast(context, id.hashCode(), intent, flags)
        pendingIntents[id] = pi

        try {
            locationManager.addProximityAlert(
                latitude,
                longitude,
                radiusMeters,
                -1, // no expiration
                pi
            )
            Log.d(TAG, "Added geofence: $id at ($latitude, $longitude) r=${radiusMeters}m")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add geofence $id: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    fun removeGeofence(id: String) {
        cancelDwellTimer(id)
        pendingIntents[id]?.let { pi ->
            try {
                locationManager.removeProximityAlert(pi)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to remove proximity alert for $id: ${e.message}")
            }
            pendingIntents.remove(id)
        }
        geofences.remove(id)
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
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {}
        dwellRunnables.keys.toList().forEach { cancelDwellTimer(it) }
    }

    // ----- Dwell Timer -----

    private fun startDwellTimer(geofence: GeofenceData) {
        cancelDwellTimer(geofence.id)
        val runnable = Runnable {
            emitEvent(geofence, 2) // dwell
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

/** BroadcastReceiver declared in AndroidManifest for geofence events. */
class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        // Events are handled by the dynamic receiver in GeofenceManager
    }
}
