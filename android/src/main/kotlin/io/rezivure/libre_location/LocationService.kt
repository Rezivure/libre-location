package io.rezivure.libre_location

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service for persistent background location tracking.
 *
 * Features:
 * - START_STICKY for automatic restart after system kill
 * - Configurable notification (title, text, priority, sticky)
 * - Partial wake lock for CPU-intensive operations (heartbeat, motion detection)
 * - Heartbeat alarm via AlarmManager for Doze-resistant periodic wakeups
 * - Android 12+ foreground service type declarations
 * - Headless mode support: restores tracking config on restart without Flutter engine
 */
class LocationService : Service() {

    companion object {
        private const val TAG = "LibreLocationService"
        const val NOTIFICATION_ID = 74291
        const val CHANNEL_ID = "libre_location_channel"

        const val ACTION_START = "io.rezivure.libre_location.START"
        const val ACTION_STOP = "io.rezivure.libre_location.STOP"
        const val ACTION_UPDATE_NOTIFICATION = "io.rezivure.libre_location.UPDATE_NOTIFICATION"
        const val ACTION_HEARTBEAT_ALARM = "io.rezivure.libre_location.HEARTBEAT_ALARM"

        const val EXTRA_NOTIFICATION_TITLE = "notificationTitle"
        const val EXTRA_NOTIFICATION_BODY = "notificationBody"
        const val EXTRA_NOTIFICATION_PRIORITY = "notificationPriority"
        const val EXTRA_NOTIFICATION_STICKY = "notificationSticky"
        const val EXTRA_HEARTBEAT_INTERVAL = "heartbeatInterval"
        const val EXTRA_PREVENT_SUSPEND = "preventSuspend"
        const val EXTRA_FROM_BOOT = "fromBoot"

        private var instance: LocationService? = null
        fun isRunning(): Boolean = instance != null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var notificationTitle = "Location Tracking"
    private var notificationBody = "Tracking your location in the background"
    private var notificationPriority = NotificationCompat.PRIORITY_LOW
    private var notificationSticky = true
    private var heartbeatIntervalSec = 0L
    private var preventSuspend = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        Log.d(TAG, "LocationService created")
    }

    @SuppressLint("WakelockTimeout")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE_NOTIFICATION -> {
                notificationTitle = intent.getStringExtra(EXTRA_NOTIFICATION_TITLE) ?: notificationTitle
                notificationBody = intent.getStringExtra(EXTRA_NOTIFICATION_BODY) ?: notificationBody
                notificationPriority = intent.getIntExtra(EXTRA_NOTIFICATION_PRIORITY, notificationPriority)
                updateNotification()
                return START_STICKY
            }
            ACTION_HEARTBEAT_ALARM -> {
                // Woken by AlarmManager — the LocationManagerWrapper heartbeat handler
                // will emit a location via its own callback. We just need to stay alive.
                Log.d(TAG, "Heartbeat alarm received")
                return START_STICKY
            }
        }

        // Normal start
        notificationTitle = intent?.getStringExtra(EXTRA_NOTIFICATION_TITLE) ?: notificationTitle
        notificationBody = intent?.getStringExtra(EXTRA_NOTIFICATION_BODY) ?: notificationBody
        notificationPriority = intent?.getIntExtra(EXTRA_NOTIFICATION_PRIORITY, notificationPriority) ?: notificationPriority
        notificationSticky = intent?.getBooleanExtra(EXTRA_NOTIFICATION_STICKY, true) ?: true
        heartbeatIntervalSec = intent?.getLongExtra(EXTRA_HEARTBEAT_INTERVAL, 0L) ?: 0L
        preventSuspend = intent?.getBooleanExtra(EXTRA_PREVENT_SUSPEND, false) ?: false

        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Acquire wake lock if preventSuspend is enabled
        if (preventSuspend) {
            acquireWakeLock()
        }

        // Schedule heartbeat alarm for Doze resistance
        if (heartbeatIntervalSec > 0) {
            scheduleHeartbeatAlarm()
        }

        Log.d(TAG, "LocationService started (sticky=$notificationSticky, " +
                "heartbeat=${heartbeatIntervalSec}s, preventSuspend=$preventSuspend)")

        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        releaseWakeLock()
        cancelHeartbeatAlarm()
        stopForeground(STOP_FOREGROUND_REMOVE)
        Log.d(TAG, "LocationService destroyed")
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // If stopOnTerminate is false (default), we keep running
        // The service is START_STICKY so Android will restart it
        Log.d(TAG, "Task removed — service remains via START_STICKY")
    }

    // ----- Notification -----

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when location tracking is active"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        // Stop action PendingIntent
        val stopIntent = Intent(this, LocationService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Launch app PendingIntent
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val launchPendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(notificationTitle)
            .setContentText(notificationBody)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(notificationSticky)
            .setPriority(notificationPriority)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .apply {
                launchPendingIntent?.let { setContentIntent(it) }
                addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            }
            .build()
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    /**
     * Updates the notification text from external code (e.g., plugin).
     */
    fun updateNotification(title: String, body: String) {
        notificationTitle = title
        notificationBody = body
        updateNotification()
    }

    // ----- Wake Lock -----

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "libre_location:tracking"
        ).apply {
            acquire()
        }
        Log.d(TAG, "Wake lock acquired")
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
            wakeLock = null
            Log.d(TAG, "Wake lock released")
        }
    }

    // ----- Heartbeat Alarm (Doze-resistant) -----

    private fun scheduleHeartbeatAlarm() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, HeartbeatAlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val intervalMs = heartbeatIntervalSec * 1000L
        val triggerAt = SystemClock.elapsedRealtime() + intervalMs

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // setExactAndAllowWhileIdle for Doze mode
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pendingIntent
            )
        }
        Log.d(TAG, "Heartbeat alarm scheduled: ${heartbeatIntervalSec}s")
    }

    private fun cancelHeartbeatAlarm() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, HeartbeatAlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }
}
