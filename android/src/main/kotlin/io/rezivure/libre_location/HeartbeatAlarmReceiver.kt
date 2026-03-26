package io.rezivure.libre_location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BroadcastReceiver for AlarmManager-based heartbeat wakeups.
 *
 * Fired by the alarm scheduled in [LocationService] to ensure periodic
 * location emissions survive Android Doze and App Standby modes.
 *
 * On each trigger, it pokes the [LocationService] to emit a heartbeat location
 * and reschedules the next alarm.
 */
class HeartbeatAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "LibreHeartbeatAlarm"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        Log.d(TAG, "Heartbeat alarm fired")

        if (!LocationService.isRunning()) {
            Log.d(TAG, "LocationService not running — checking if we should restart")

            if (TrackingConfig.isTrackingEnabled(context)) {
                val config = TrackingConfig.restore(context)
                if (config != null && config.enableHeadless) {
                    // Restart service in headless mode
                    val serviceIntent = Intent(context, LocationService::class.java).apply {
                        action = LocationService.ACTION_HEARTBEAT_ALARM
                        putExtra(LocationService.EXTRA_NOTIFICATION_TITLE, config.notificationTitle)
                        putExtra(LocationService.EXTRA_NOTIFICATION_BODY, config.notificationBody)
                        putExtra(LocationService.EXTRA_HEARTBEAT_INTERVAL, config.heartbeatInterval)
                        putExtra(LocationService.EXTRA_PREVENT_SUSPEND, config.preventSuspend)
                    }
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to restart service from heartbeat: ${e.message}")
                    }
                }
            }
            return
        }

        // Poke the service
        val serviceIntent = Intent(context, LocationService::class.java).apply {
            action = LocationService.ACTION_HEARTBEAT_ALARM
        }
        try {
            context.startService(serviceIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to poke service: ${e.message}")
        }
    }
}
