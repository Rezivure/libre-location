package io.rezivure.libre_location

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.os.Build

/**
 * Geofence manager using pure AOSP LocationManager.addProximityAlert().
 * NO Google Play Services.
 */
class GeofenceManager(
    private val context: Context,
    private val onGeofenceEvent: (Map<String, Any?>) -> Unit,
) {

    private val locationManager: LocationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    private val geofences = mutableMapOf<String, GeofenceData>()
    private val pendingIntents = mutableMapOf<String, PendingIntent>()

    data class GeofenceData(
        val id: String,
        val latitude: Double,
        val longitude: Double,
        val radiusMeters: Float,
        val triggers: List<Int>,
        val dwellDurationMs: Long?,
    )

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val id = intent?.getStringExtra("geofence_id") ?: return
            val entering = intent.getBooleanExtra(LocationManager.KEY_PROXIMITY_ENTERING, false)
            val geofence = geofences[id] ?: return

            val transition = if (entering) 0 else 1 // 0=enter, 1=exit

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
            putExtra("geofence_id", id)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        val pi = PendingIntent.getBroadcast(context, id.hashCode(), intent, flags)
        pendingIntents[id] = pi

        locationManager.addProximityAlert(
            latitude,
            longitude,
            radiusMeters,
            -1, // no expiration
            pi
        )
    }

    @SuppressLint("MissingPermission")
    fun removeGeofence(id: String) {
        pendingIntents[id]?.let { pi ->
            locationManager.removeProximityAlert(pi)
            pendingIntents.remove(id)
        }
        geofences.remove(id)
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

    companion object {
        private const val ACTION_GEOFENCE = "io.rezivure.libre_location.GEOFENCE"
    }
}

/** BroadcastReceiver declared in AndroidManifest for geofence events. */
class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        // Events are handled by the dynamic receiver in GeofenceManager
    }
}
