package io.rezivure.libre_location

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service for persistent background location tracking.
 *
 * Features:
 * - START_STICKY for automatic restart after system kill
 * - Configurable notification (title, text, priority, sticky)
 * - Partial wake lock for CPU-intensive operations (heartbeat, motion detection)
 * - In-process heartbeat via Handler.postDelayed (no AlarmManager — avoids
 *   Google Play exact-alarm policy restrictions). Heartbeats fire while the
 *   foreground service is alive; may pause during Doze, but the service's
 *   ongoing notification + battery-optimization exemption keep it running.
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

        const val EXTRA_NOTIFICATION_TITLE = "notificationTitle"
        const val EXTRA_NOTIFICATION_BODY = "notificationBody"
        const val EXTRA_NOTIFICATION_PRIORITY = "notificationPriority"
        const val EXTRA_NOTIFICATION_STICKY = "notificationSticky"
        const val EXTRA_HEARTBEAT_INTERVAL = "heartbeatInterval"
        const val EXTRA_KEEP_AWAKE = "keepAwake"
        const val EXTRA_FROM_BOOT = "fromBoot"

        private var instance: LocationService? = null
        fun isRunning(): Boolean = instance != null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var serviceLocationManager: LocationManager? = null
    private var serviceListener: LocationListener? = null
    private var notificationTitle = "Location Tracking"
    private var notificationBody = "Tracking your location in the background"
    private var notificationPriority = NotificationCompat.PRIORITY_LOW
    private var notificationSticky = true
    private var heartbeatIntervalSec = 0L
    private var keepAwake = false
    private var heartbeatThread: HandlerThread? = null
    private var heartbeatHandler: Handler? = null
    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            emitHeartbeat()
            heartbeatHandler?.postDelayed(this, heartbeatIntervalSec * 1000L)
        }
    }

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
        }

        // Normal start. On a START_STICKY restart the intent is null and all
        // extras are lost — fall back to the persisted TrackingConfig so the
        // service comes back fully configured instead of inert.
        val restored = if (intent == null) TrackingConfig.restore(this) else null

        notificationTitle = intent?.getStringExtra(EXTRA_NOTIFICATION_TITLE)
            ?: restored?.notificationTitle ?: notificationTitle
        notificationBody = intent?.getStringExtra(EXTRA_NOTIFICATION_BODY)
            ?: restored?.notificationBody ?: notificationBody
        notificationPriority = intent?.getIntExtra(EXTRA_NOTIFICATION_PRIORITY, notificationPriority)
            ?: restored?.notificationPriority ?: notificationPriority
        notificationSticky = intent?.getBooleanExtra(EXTRA_NOTIFICATION_STICKY, true)
            ?: restored?.notificationSticky ?: true
        heartbeatIntervalSec = intent?.getLongExtra(EXTRA_HEARTBEAT_INTERVAL, 0L)
            ?: restored?.heartbeatInterval ?: 0L
        keepAwake = intent?.getBooleanExtra(EXTRA_KEEP_AWAKE, false)
            ?: restored?.keepAwake ?: false

        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Acquire wake lock if keepAwake is enabled
        if (keepAwake) {
            acquireWakeLock()
        }

        // Start the in-process heartbeat loop
        if (heartbeatIntervalSec > 0) {
            startHeartbeatLoop()
        }

        // Own an active location subscription in the service itself so fresh
        // fixes keep flowing even after a START_STICKY restart with no Flutter
        // engine attached. This is independent of the plugin/engine lifecycle.
        startServiceLocationUpdates()

        Log.d(TAG, "LocationService started (sticky=$notificationSticky, " +
                "heartbeat=${heartbeatIntervalSec}s, keepAwake=$keepAwake)")

        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        releaseWakeLock()
        stopHeartbeatLoop()
        stopServiceLocationUpdates()
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

    // ----- Service-owned location subscription -----

    @SuppressLint("MissingPermission")
    private fun startServiceLocationUpdates() {
        if (serviceListener != null) return
        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        serviceLocationManager = lm

        val listener = LocationListener { location -> onServiceLocation(location) }
        serviceListener = listener

        // Interval-based GPS/network updates. A foreground-service of type
        // location continues to receive these while backgrounded; the interval
        // is delivered even in Doze for an FGS holder (unlike Handler timers).
        val intervalMs = if (heartbeatIntervalSec > 0) heartbeatIntervalSec * 1000L else 60_000L
        try {
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, intervalMs, 0f, listener, Looper.getMainLooper())
            }
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, intervalMs, 0f, listener, Looper.getMainLooper())
            }
            Log.d(TAG, "Service-owned location updates started (interval=${intervalMs}ms)")
        } catch (e: SecurityException) {
            Log.w(TAG, "No location permission for service subscription: ${e.message}")
        }
    }

    private fun stopServiceLocationUpdates() {
        serviceListener?.let { serviceLocationManager?.removeUpdates(it) }
        serviceListener = null
        serviceLocationManager = null
    }

    @SuppressLint("WakelockTimeout")
    private fun onServiceLocation(location: Location) {
        if (!HeadlessCallbackDispatcher.hasCallback(this)) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val pulse = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "libre_location:fix")
        pulse.acquire(30_000L)
        try {
            val posMap = mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "altitude" to location.altitude,
                "accuracy" to location.accuracy.toDouble(),
                "speed" to location.speed.toDouble(),
                "heading" to location.bearing.toDouble(),
                "timestamp" to location.time,
                "isMoving" to (location.speed > 0.5f),
                "provider" to (location.provider ?: "unknown"),
            )
            HeadlessCallbackDispatcher.dispatchLocationUpdate(this, posMap)
        } finally {
            if (pulse.isHeld) pulse.release()
        }
    }

    // ----- Heartbeat (in-process, Handler-based) -----

    private fun startHeartbeatLoop() {
        val thread = HandlerThread("libre-heartbeat").also { it.start() }
        heartbeatThread = thread
        val handler = Handler(thread.looper)
        heartbeatHandler = handler
        handler.postDelayed(heartbeatRunnable, heartbeatIntervalSec * 1000L)
        Log.d(TAG, "Heartbeat loop started: ${heartbeatIntervalSec}s")
    }

    private fun stopHeartbeatLoop() {
        heartbeatHandler?.removeCallbacks(heartbeatRunnable)
        heartbeatHandler = null
        heartbeatThread?.quitSafely()
        heartbeatThread = null
    }

    @SuppressLint("WakelockTimeout")
    private fun emitHeartbeat() {
        Log.d(TAG, "Heartbeat tick")
        if (!HeadlessCallbackDispatcher.hasCallback(this)) return

        // Hold a short wakelock across the fix→emit critical section so the CPU
        // can't sleep mid-dispatch when we aren't holding the session-long lock.
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val pulse = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "libre_location:pulse")
        pulse.acquire(30_000L)
        try {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
            try {
                val lastKnown = locationManager?.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)
                    ?: locationManager?.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)
                if (lastKnown != null) {
                    val posMap = mapOf(
                        "latitude" to lastKnown.latitude,
                        "longitude" to lastKnown.longitude,
                        "altitude" to lastKnown.altitude,
                        "accuracy" to lastKnown.accuracy.toDouble(),
                        "speed" to lastKnown.speed.toDouble(),
                        "heading" to lastKnown.bearing.toDouble(),
                        "timestamp" to lastKnown.time,
                        "provider" to (lastKnown.provider ?: "unknown"),
                    )
                    HeadlessCallbackDispatcher.dispatchHeartbeat(this, mapOf("position" to posMap))
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "No permission for headless location: ${e.message}")
            }
        } finally {
            if (pulse.isHeld) pulse.release()
        }
    }
}
