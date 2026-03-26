package io.rezivure.libre_location

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * Watchdog alarm that fires every 15 minutes to check if the LocationService
 * is still running. If tracking should be active but the service is dead,
 * it restarts the service. This survives some OEM kills that bypass START_STICKY.
 */
class WatchdogAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "LibreWatchdog"
        private const val INTERVAL_MS = 15 * 60 * 1000L // 15 minutes
        private const val REQUEST_CODE = 74292

        fun schedule(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, WatchdogAlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context, REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val triggerAt = SystemClock.elapsedRealtime() + INTERVAL_MS

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pendingIntent
                )
            }
            Log.d(TAG, "Watchdog alarm scheduled (15 min)")
        }

        fun cancel(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, WatchdogAlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context, REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            Log.d(TAG, "Watchdog alarm cancelled")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Watchdog alarm fired")

        val shouldBeTracking = TrackingConfig.isTrackingEnabled(context)
        val isRunning = LocationService.isRunning()

        if (shouldBeTracking && !isRunning) {
            Log.w(TAG, "Service dead but should be tracking — restarting")

            val config = TrackingConfig.restore(context) ?: return
            val serviceIntent = Intent(context, LocationService::class.java).apply {
                action = LocationService.ACTION_START
                putExtra(LocationService.EXTRA_NOTIFICATION_TITLE, config.notificationTitle)
                putExtra(LocationService.EXTRA_NOTIFICATION_BODY, config.notificationBody)
                putExtra(LocationService.EXTRA_NOTIFICATION_PRIORITY, config.notificationPriority)
                putExtra(LocationService.EXTRA_NOTIFICATION_STICKY, config.notificationSticky)
                putExtra(LocationService.EXTRA_HEARTBEAT_INTERVAL, config.heartbeatInterval)
                putExtra(LocationService.EXTRA_KEEP_AWAKE, config.keepAwake)
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to restart service: ${e.message}")
            }
        }

        // Re-schedule
        if (shouldBeTracking) {
            schedule(context)
        }
    }
}
