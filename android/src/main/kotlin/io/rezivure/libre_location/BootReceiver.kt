package io.rezivure.libre_location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Restarts location tracking after device boot when [TrackingConfig.startOnBoot] is true.
 *
 * Reads the persisted configuration from SharedPreferences and starts the
 * [LocationService] foreground service. The service then runs in headless mode
 * (without a Flutter engine) until the app is opened.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "LibreBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED &&
            intent?.action != "android.intent.action.QUICKBOOT_POWERON" &&
            intent?.action != "com.htc.intent.action.QUICKBOOT_POWERON") {
            return
        }

        Log.d(TAG, "Boot completed — checking if tracking should restart")

        if (!TrackingConfig.isTrackingEnabled(context)) {
            Log.d(TAG, "Tracking was not enabled before shutdown — skipping")
            return
        }

        val config = TrackingConfig.restore(context)
        if (config == null) {
            Log.w(TAG, "No persisted config found — skipping")
            return
        }

        if (!config.startOnBoot) {
            Log.d(TAG, "startOnBoot is false — skipping")
            return
        }

        Log.d(TAG, "Restarting location tracking after boot")

        val serviceIntent = Intent(context, LocationService::class.java).apply {
            action = LocationService.ACTION_START
            putExtra(LocationService.EXTRA_NOTIFICATION_TITLE, config.notificationTitle)
            putExtra(LocationService.EXTRA_NOTIFICATION_BODY, config.notificationBody)
            putExtra(LocationService.EXTRA_NOTIFICATION_PRIORITY, config.notificationPriority)
            putExtra(LocationService.EXTRA_NOTIFICATION_STICKY, config.notificationSticky)
            putExtra(LocationService.EXTRA_HEARTBEAT_INTERVAL, config.heartbeatInterval)
            putExtra(LocationService.EXTRA_KEEP_AWAKE, config.keepAwake)
            putExtra(LocationService.EXTRA_FROM_BOOT, true)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            Log.d(TAG, "LocationService started after boot")

            // Start headless Dart engine if a callback is registered
            if (config.enableHeadless && HeadlessCallbackDispatcher.hasCallback(context)) {
                Log.d(TAG, "Initializing headless Dart engine for boot callbacks")
                HeadlessCallbackDispatcher.dispatchHeartbeat(context, mapOf(
                    "event" to "boot",
                    "timestamp" to System.currentTimeMillis(),
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start LocationService after boot: ${e.message}")
        }
    }
}
