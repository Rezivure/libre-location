package io.rezivure.libre_location

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

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
 * - Service-owned GPS/network subscription delivers fresh fixes in Doze
 *   for an FGS of type location (unlike Handler timers).
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
        const val ACTION_UPDATE_CONFIG = "io.rezivure.libre_location.UPDATE_CONFIG"

        const val EXTRA_NOTIFICATION_TITLE = "notificationTitle"
        const val EXTRA_NOTIFICATION_BODY = "notificationBody"
        const val EXTRA_NOTIFICATION_PRIORITY = "notificationPriority"
        const val EXTRA_NOTIFICATION_STICKY = "notificationSticky"
        const val EXTRA_HEARTBEAT_INTERVAL = "heartbeatInterval"
        const val EXTRA_KEEP_AWAKE = "keepAwake"
        const val EXTRA_FROM_BOOT = "fromBoot"

        private const val ONE_SHOT_TIMEOUT_MS = 25_000L

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
    private var lastDeliveredFixTimeMs = 0L
    private var oneShotInFlight = AtomicBoolean(false)
    private var oneShotListener: LocationListener? = null
    private var oneShotTimeout: Runnable? = null
    private var oneShotCancellation: CancellationSignal? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            emitHeartbeat()
            val delay = if (heartbeatIntervalSec > 0) heartbeatIntervalSec * 1000L else 60_000L
            heartbeatHandler?.postDelayed(this, delay)
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
            ACTION_UPDATE_CONFIG -> {
                applyConfigUpdate(intent)
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
        val newInterval = intent?.getLongExtra(EXTRA_HEARTBEAT_INTERVAL, 0L)
            ?: restored?.heartbeatInterval ?: 0L
        keepAwake = intent?.getBooleanExtra(EXTRA_KEEP_AWAKE, false)
            ?: restored?.keepAwake ?: false

        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Never hold a session-long wakelock from this path; keepAwake must stay false
        // for Play/battery. Short pulse locks are acquired per fix/dispatch only.
        if (keepAwake) {
            Log.w(TAG, "keepAwake=true requested; ignoring to avoid pinning CPU")
        }

        applyHeartbeatInterval(newInterval, forceRestart = serviceListener == null)

        Log.d(TAG, "LocationService started (sticky=$notificationSticky, " +
                "heartbeat=${heartbeatIntervalSec}s, keepAwake=false)")

        return START_STICKY
    }

    private fun applyConfigUpdate(intent: Intent) {
        notificationTitle = intent.getStringExtra(EXTRA_NOTIFICATION_TITLE) ?: notificationTitle
        notificationBody = intent.getStringExtra(EXTRA_NOTIFICATION_BODY) ?: notificationBody
        notificationPriority = intent.getIntExtra(EXTRA_NOTIFICATION_PRIORITY, notificationPriority)
        if (intent.hasExtra(EXTRA_NOTIFICATION_STICKY)) {
            notificationSticky = intent.getBooleanExtra(EXTRA_NOTIFICATION_STICKY, notificationSticky)
        }
        updateNotification()

        if (intent.hasExtra(EXTRA_HEARTBEAT_INTERVAL)) {
            val newInterval = intent.getLongExtra(EXTRA_HEARTBEAT_INTERVAL, heartbeatIntervalSec)
            applyHeartbeatInterval(newInterval, forceRestart = false)
        }
        Log.d(TAG, "Config updated (heartbeat=${heartbeatIntervalSec}s)")
    }

    /**
     * Applies a new heartbeat interval. Restarts the network listener and
     * Handler loop when the interval actually changes (or on first start).
     */
    private fun applyHeartbeatInterval(newInterval: Long, forceRestart: Boolean) {
        val changed = newInterval != heartbeatIntervalSec
        heartbeatIntervalSec = newInterval
        if (!forceRestart && !changed && serviceListener != null) {
            return
        }

        stopHeartbeatLoop()
        stopServiceLocationUpdates()

        if (heartbeatIntervalSec > 0) {
            startHeartbeatLoop()
        }
        startServiceLocationUpdates()
    }

    override fun onDestroy() {
        instance = null
        cancelOneShot()
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

        // Interval-based GPS/network updates (same as upstream). A foreground
        // service of type location continues to receive these while backgrounded;
        // the interval is delivered even in Doze for an FGS holder (unlike Handler).
        val intervalMs = if (heartbeatIntervalSec > 0) heartbeatIntervalSec * 1000L else 60_000L
        var started = false
        try {
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    intervalMs,
                    0f,
                    listener,
                    Looper.getMainLooper()
                )
                started = true
            }
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    intervalMs,
                    0f,
                    listener,
                    Looper.getMainLooper()
                )
                started = true
            }
            if (started) {
                Log.d(TAG, "Service-owned location updates started (interval=${intervalMs}ms)")
            } else {
                Log.w(TAG, "No enabled location providers for service subscription")
                serviceListener = null
                serviceLocationManager = null
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "No location permission for service subscription: ${e.message}")
            serviceListener = null
            serviceLocationManager = null
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
            dispatchLocation(location)
        } finally {
            if (pulse.isHeld) pulse.release()
        }
    }

    private fun dispatchLocation(location: Location) {
        val posMap = locationToMap(location)
        lastDeliveredFixTimeMs = SystemClock.elapsedRealtime()
        HeadlessCallbackDispatcher.dispatchLocationUpdate(this, posMap)
        Log.d(TAG, "Dispatched fix provider=${location.provider} time=${location.time}")
    }

    private fun dispatchHeartbeat(location: Location) {
        val posMap = locationToMap(location)
        lastDeliveredFixTimeMs = SystemClock.elapsedRealtime()
        HeadlessCallbackDispatcher.dispatchHeartbeat(this, mapOf("position" to posMap))
        Log.d(TAG, "Dispatched heartbeat provider=${location.provider} time=${location.time}")
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
            "isMoving" to (location.speed > 0.5f),
            "provider" to (location.provider ?: "unknown"),
        )

        try {
            val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
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

    // ----- Heartbeat (in-process, Handler-based) -----

    private fun startHeartbeatLoop() {
        if (heartbeatHandler != null) return
        val thread = HandlerThread("libre-heartbeat").also { it.start() }
        heartbeatThread = thread
        val handler = Handler(thread.looper)
        heartbeatHandler = handler
        val delay = if (heartbeatIntervalSec > 0) heartbeatIntervalSec * 1000L else 60_000L
        handler.postDelayed(heartbeatRunnable, delay)
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

        val intervalMs = if (heartbeatIntervalSec > 0) heartbeatIntervalSec * 1000L else 60_000L
        val age = SystemClock.elapsedRealtime() - lastDeliveredFixTimeMs
        if (lastDeliveredFixTimeMs > 0L && age <= intervalMs) {
            Log.d(TAG, "Heartbeat skipped; fresh fix age=${age}ms <= interval=${intervalMs}ms")
            return
        }

        // Hold a short wakelock across the fix→emit critical section so the CPU
        // can't sleep mid-dispatch when we aren't holding the session-long lock.
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val pulse = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "libre_location:pulse")
        pulse.acquire(30_000L)
        try {
            requestFreshFix { location ->
                try {
                    if (location != null) {
                        dispatchHeartbeat(location)
                    } else {
                        Log.w(TAG, "Heartbeat: no fresh fix; not publishing stale cache")
                    }
                } finally {
                    if (pulse.isHeld) pulse.release()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Heartbeat fresh fix failed: ${e.message}")
            if (pulse.isHeld) pulse.release()
        }
    }

    /**
     * One-shot GPS/network fix. Used only when the FGS listener has not
     * delivered within the current interval. Never falls back to publishing
     * a stale getLastKnownLocation sample. Prefer GPS when enabled (same
     * provider order as upstream last-known), else network.
     */
    @SuppressLint("MissingPermission")
    private fun requestFreshFix(onResult: (Location?) -> Unit) {
        if (!oneShotInFlight.compareAndSet(false, true)) {
            Log.d(TAG, "One-shot already in flight; skipping")
            onResult(null)
            return
        }

        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm == null) {
            oneShotInFlight.set(false)
            onResult(null)
            return
        }

        val provider = when {
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> null
        }
        if (provider == null) {
            oneShotInFlight.set(false)
            onResult(null)
            return
        }

        val delivered = AtomicBoolean(false)
        fun complete(location: Location?) {
            if (!delivered.compareAndSet(false, true)) return
            finishOneShot()
            onResult(location)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val cancellation = CancellationSignal()
                oneShotCancellation = cancellation
                val executor: Executor = mainExecutor
                lm.getCurrentLocation(
                    provider,
                    cancellation,
                    executor
                ) { location ->
                    complete(location)
                }
                oneShotTimeout = Runnable {
                    Log.w(TAG, "One-shot getCurrentLocation timed out ($provider)")
                    cancellation.cancel()
                    complete(null)
                }
                mainHandler.postDelayed(oneShotTimeout!!, ONE_SHOT_TIMEOUT_MS)
            } else {
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        cancelOneShotListener(lm)
                        complete(location)
                    }
                    @Deprecated("Deprecated in API")
                    override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                }
                oneShotListener = listener
                // Match upstream dual subscription: listen on every enabled provider;
                // first fix wins.
                var registered = false
                if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    lm.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        0L,
                        0f,
                        listener,
                        Looper.getMainLooper()
                    )
                    registered = true
                }
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    lm.requestLocationUpdates(
                        LocationManager.NETWORK_PROVIDER,
                        0L,
                        0f,
                        listener,
                        Looper.getMainLooper()
                    )
                    registered = true
                }
                if (!registered) {
                    complete(null)
                    return
                }
                oneShotTimeout = Runnable {
                    Log.w(TAG, "One-shot requestLocationUpdates timed out")
                    cancelOneShotListener(lm)
                    complete(null)
                }
                mainHandler.postDelayed(oneShotTimeout!!, ONE_SHOT_TIMEOUT_MS)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "No permission for one-shot fix: ${e.message}")
            complete(null)
        } catch (e: Exception) {
            Log.w(TAG, "One-shot fix error: ${e.message}")
            complete(null)
        }
    }

    private fun cancelOneShotListener(lm: LocationManager) {
        oneShotListener?.let {
            try {
                lm.removeUpdates(it)
            } catch (_: Exception) {
            }
        }
        oneShotListener = null
    }

    private fun finishOneShot() {
        oneShotTimeout?.let { mainHandler.removeCallbacks(it) }
        oneShotTimeout = null
        oneShotCancellation = null
        oneShotInFlight.set(false)
    }

    private fun cancelOneShot() {
        oneShotCancellation?.cancel()
        oneShotTimeout?.let { mainHandler.removeCallbacks(it) }
        oneShotTimeout = null
        val lm = serviceLocationManager
            ?: getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm != null) {
            cancelOneShotListener(lm)
        }
        oneShotInFlight.set(false)
        oneShotCancellation = null
    }
}
