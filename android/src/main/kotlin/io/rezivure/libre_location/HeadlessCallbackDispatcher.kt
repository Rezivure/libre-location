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
    private var isStarting = false
    private var inFlight = 0
    private val pendingReady = mutableListOf<(Boolean) -> Unit>()
    private var readyTimeout: Runnable? = null

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
            inFlight++
            ensureEngine(context) { ready ->
                if (ready) {
                    // Hold the in-flight count until Dart finishes the async
                    // Matrix send and replies. Otherwise the idle timer can tear
                    // the engine down mid-send (esp. the cold first-run client
                    // init, which can exceed the idle window).
                    channel?.invokeMethod("onLocationUpdate", locationData, object : MethodChannel.Result {
                        override fun success(result: Any?) { inFlight--; resetIdleTimeout(context) }
                        override fun error(code: String, msg: String?, details: Any?) { inFlight--; resetIdleTimeout(context) }
                        override fun notImplemented() { inFlight--; resetIdleTimeout(context) }
                    }) ?: run { inFlight--; resetIdleTimeout(context) }
                } else {
                    inFlight--
                    resetIdleTimeout(context)
                }
            }
        }
    }

    /**
     * Sends a heartbeat event to the Dart headless callback.
     */
    fun dispatchHeartbeat(context: Context, heartbeatData: Map<String, Any?>) {
        mainHandler.post {
            inFlight++
            ensureEngine(context) { ready ->
                if (ready) {
                    // Hold in-flight until Dart replies (see dispatchLocationUpdate).
                    channel?.invokeMethod("onHeartbeat", heartbeatData, object : MethodChannel.Result {
                        override fun success(result: Any?) { inFlight--; resetIdleTimeout(context) }
                        override fun error(code: String, msg: String?, details: Any?) { inFlight--; resetIdleTimeout(context) }
                        override fun notImplemented() { inFlight--; resetIdleTimeout(context) }
                    }) ?: run { inFlight--; resetIdleTimeout(context) }
                } else {
                    inFlight--
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

        // Startup already in progress: queue this waiter instead of spawning
        // a second engine that would orphan the first.
        if (isStarting) {
            pendingReady.add(onReady)
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
        isStarting = true
        pendingReady.add(onReady)

        try {
            // Load the Flutter library before the first call into it. When
            // the service starts in a fresh process (restart after the process
            // was killed, boot, app update) no UI has loaded it yet, and the
            // lookup below threw UnsatisfiedLinkError: the process crashed on
            // every restart and sharing stayed off until the app was opened.
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            if (!flutterLoader.initialized()) {
                flutterLoader.startInitialization(context)
            }
            flutterLoader.ensureInitializationComplete(context, null)

            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
            if (callbackInfo == null) {
                Log.e(TAG, "Could not find callback information for handle: $dispatcherHandle")
                flushPending(false)
                return
            }

            val newEngine = FlutterEngine(context)
            engine = newEngine

            channel = MethodChannel(newEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            channel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialized" -> {
                        isEngineReady = true
                        Log.d(TAG, "Headless Dart isolate ready")
                        result.success(null)
                        flushPending(true)
                    }
                    else -> result.notImplemented()
                }
            }

            val appBundlePath = flutterLoader.findAppBundlePath()
            val dartCallback = DartExecutor.DartCallback(
                context.assets,
                appBundlePath,
                callbackInfo
            )
            newEngine.dartExecutor.executeDartCallback(dartCallback)

            // Fallback: if Dart never signals "initialized" within the window,
            // resolve waiters as not-ready (they no-op) rather than hang.
            readyTimeout = Runnable {
                if (!isEngineReady) {
                    Log.w(TAG, "Headless isolate init timed out")
                    flushPending(false)
                }
            }
            mainHandler.postDelayed(readyTimeout!!, 5000L)

        } catch (e: Throwable) {
            // Throwable, not Exception: a failing native call raises an Error,
            // which used to take the whole process down instead of this path.
            Log.e(TAG, "Failed to start headless engine: $e")
            engine = null
            channel = null
            flushPending(false)
        }
    }

    private fun flushPending(ready: Boolean) {
        isStarting = false
        readyTimeout?.let { mainHandler.removeCallbacks(it) }
        readyTimeout = null
        val waiters = pendingReady.toList()
        pendingReady.clear()
        waiters.forEach { it(ready) }
    }

    private fun resetIdleTimeout(context: Context) {
        idleRunnable?.let { mainHandler.removeCallbacks(it) }
        idleRunnable = Runnable {
            // Don't tear down while dispatches are still in flight.
            if (inFlight > 0) {
                resetIdleTimeout(context)
                return@Runnable
            }
            destroyEngine()
        }
        mainHandler.postDelayed(idleRunnable!!, IDLE_TIMEOUT_MS)
    }

    private fun destroyEngine() {
        if (inFlight > 0 || isStarting) return
        Log.d(TAG, "Destroying idle headless engine")
        isEngineReady = false
        channel?.setMethodCallHandler(null)
        channel = null
        engine?.destroy()
        engine = null
    }
}
