package io.rezivure.libre_location

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

/**
 * Manages a headless FlutterEngine for executing Dart callbacks when the
 * app UI is not running (after termination, on boot, or from alarm wakeups).
 *
 * Usage pattern:
 * 1. Dart side registers a static callback via [LibreLocation.registerHeadlessDispatcher]
 * 2. The callback handle (long) is persisted in SharedPreferences
 * 3. When a headless event fires, this class starts a FlutterEngine,
 *    executes the callback, and sends location data via a MethodChannel
 *
 * Thread safety: All FlutterEngine operations happen on the main looper.
 * Memory: The engine is destroyed after [IDLE_TIMEOUT_MS] of inactivity.
 */
object HeadlessCallbackDispatcher {

    private const val TAG = "LibreHeadless"
    private const val PREFS_NAME = "libre_location_headless"
    private const val KEY_CALLBACK_HANDLE = "callback_handle"
    private const val KEY_USER_CALLBACK_HANDLE = "user_callback_handle"
    private const val CHANNEL_NAME = "libre_location/headless"
    private const val IDLE_TIMEOUT_MS = 30_000L

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var idleRunnable: Runnable? = null
    private var isEngineReady = false

    /**
     * Persists the dispatcher and user callback handles from the Dart side.
     */
    fun setCallbackHandles(context: Context, dispatcherHandle: Long, userCallbackHandle: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putLong(KEY_CALLBACK_HANDLE, dispatcherHandle)
            .putLong(KEY_USER_CALLBACK_HANDLE, userCallbackHandle)
            .apply()
        Log.d(TAG, "Callback handles saved: dispatcher=$dispatcherHandle, user=$userCallbackHandle")
    }

    /**
     * Returns whether a headless callback has been registered.
     */
    fun hasCallback(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_CALLBACK_HANDLE, 0L) != 0L
    }

    /**
     * Sends a location update to the Dart headless callback.
     * Starts the FlutterEngine if not already running.
     */
    fun dispatchLocationUpdate(context: Context, locationData: Map<String, Any?>) {
        mainHandler.post {
            ensureEngine(context) { ready ->
                if (ready) {
                    channel?.invokeMethod("onLocationUpdate", locationData)
                    resetIdleTimeout(context)
                } else {
                    Log.w(TAG, "Engine not ready, buffering to database")
                    // Location is already persisted by the caller
                }
            }
        }
    }

    /**
     * Sends a heartbeat event to the Dart headless callback.
     */
    fun dispatchHeartbeat(context: Context, heartbeatData: Map<String, Any?>) {
        mainHandler.post {
            ensureEngine(context) { ready ->
                if (ready) {
                    channel?.invokeMethod("onHeartbeat", heartbeatData)
                    resetIdleTimeout(context)
                }
            }
        }
    }

    private fun ensureEngine(context: Context, onReady: (Boolean) -> Unit) {
        if (engine != null && isEngineReady) {
            onReady(true)
            return
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val dispatcherHandle = prefs.getLong(KEY_CALLBACK_HANDLE, 0L)
        if (dispatcherHandle == 0L) {
            Log.w(TAG, "No dispatcher callback handle registered")
            onReady(false)
            return
        }

        Log.d(TAG, "Starting headless FlutterEngine")

        try {
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
            if (callbackInfo == null) {
                Log.e(TAG, "Could not find callback information for handle: $dispatcherHandle")
                onReady(false)
                return
            }

            val newEngine = FlutterEngine(context)
            engine = newEngine

            channel = MethodChannel(newEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)

            // Set up method channel to receive "ready" from Dart side
            channel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialized" -> {
                        isEngineReady = true
                        Log.d(TAG, "Headless Dart isolate ready")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            val flutterLoader = FlutterInjector.instance().flutterLoader()
            if (!flutterLoader.initialized()) {
                flutterLoader.startInitialization(context)
            }
            flutterLoader.ensureInitializationComplete(context, null)

            val appBundlePath = flutterLoader.findAppBundlePath()
            val dartCallback = DartExecutor.DartCallback(
                context.assets,
                appBundlePath,
                callbackInfo
            )
            newEngine.dartExecutor.executeDartCallback(dartCallback)

            // Give Dart isolate time to initialize, then call onReady
            mainHandler.postDelayed({
                onReady(isEngineReady)
            }, 2000L)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start headless engine: ${e.message}")
            engine = null
            channel = null
            onReady(false)
        }
    }

    private fun resetIdleTimeout(context: Context) {
        idleRunnable?.let { mainHandler.removeCallbacks(it) }
        idleRunnable = Runnable {
            destroyEngine()
        }
        mainHandler.postDelayed(idleRunnable!!, IDLE_TIMEOUT_MS)
    }

    private fun destroyEngine() {
        Log.d(TAG, "Destroying idle headless engine")
        isEngineReady = false
        channel?.setMethodCallHandler(null)
        channel = null
        engine?.destroy()
        engine = null
    }
}
