package io.rezivure.libre_location

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Centralized tracking configuration that can be persisted across restarts.
 *
 * Supports all configuration parameters from the Dart [LocationConfig] plus
 * extended parameters for heartbeat, activity recognition, motion detection,
 * persistence, and foreground service notification.
 */
data class TrackingConfig(
    // Core location parameters
    val accuracy: Int = 0,                          // 0=high, 1=balanced, 2=low, 3=passive
    val intervalMs: Long = 60_000L,
    val distanceFilter: Float = 10f,
    val mode: Int = 1,                              // 0=active, 1=balanced, 2=passive
    val enableMotionDetection: Boolean = true,

    // Foreground service notification
    val notificationTitle: String = "Location Tracking",
    val notificationBody: String = "Tracking your location in the background",
    val notificationPriority: Int = -1,             // NotificationCompat.PRIORITY_LOW
    val notificationSticky: Boolean = true,

    // Lifecycle
    val stopOnTerminate: Boolean = false,
    val startOnBoot: Boolean = true,
    val enableHeadless: Boolean = true,

    // Motion detection
    val stopTimeout: Long = 300_000L,               // 5 min — time stationary before declaring "stopped"
    val stopDetectionDelay: Long = 0L,              // delay before engaging stop detection
    val stationaryRadius: Float = 25f,              // meters
    val motionTriggerDelay: Long = 0L,              // delay before re-engaging motion tracking
    val disableStopDetection: Boolean = false,
    val disableMotionActivityUpdates: Boolean = false,
    val useSignificantChangesOnly: Boolean = false,

    // Heartbeat
    val heartbeatInterval: Long = 0L,               // 0 = disabled; seconds between heartbeat emissions

    // Activity recognition
    val activityRecognitionInterval: Long = 10_000L,
    val minimumActivityRecognitionConfidence: Int = 75,

    // Persistence
    val maxDaysToPersist: Int = 7,
    val maxRecordsToPersist: Int = 10_000,
    val persistLocations: Boolean = true,

    // Battery
    val preventSuspend: Boolean = false,
) {

    fun toMap(): Map<String, Any?> = mapOf(
        "accuracy" to accuracy,
        "intervalMs" to intervalMs,
        "distanceFilter" to distanceFilter.toDouble(),
        "mode" to mode,
        "enableMotionDetection" to enableMotionDetection,
        "notificationTitle" to notificationTitle,
        "notificationBody" to notificationBody,
        "notificationPriority" to notificationPriority,
        "notificationSticky" to notificationSticky,
        "stopOnTerminate" to stopOnTerminate,
        "startOnBoot" to startOnBoot,
        "enableHeadless" to enableHeadless,
        "stopTimeout" to stopTimeout,
        "stopDetectionDelay" to stopDetectionDelay,
        "stationaryRadius" to stationaryRadius.toDouble(),
        "motionTriggerDelay" to motionTriggerDelay,
        "disableStopDetection" to disableStopDetection,
        "disableMotionActivityUpdates" to disableMotionActivityUpdates,
        "useSignificantChangesOnly" to useSignificantChangesOnly,
        "heartbeatInterval" to heartbeatInterval,
        "activityRecognitionInterval" to activityRecognitionInterval,
        "minimumActivityRecognitionConfidence" to minimumActivityRecognitionConfidence,
        "maxDaysToPersist" to maxDaysToPersist,
        "maxRecordsToPersist" to maxRecordsToPersist,
        "persistLocations" to persistLocations,
        "preventSuspend" to preventSuspend,
    )

    /**
     * Persists configuration to SharedPreferences for boot restoration.
     */
    fun persist(context: Context) {
        val prefs = getPrefs(context)
        prefs.edit().putString(KEY_CONFIG_JSON, JSONObject(toMap()).toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "libre_location_config"
        private const val KEY_CONFIG_JSON = "config_json"
        private const val KEY_TRACKING_ENABLED = "tracking_enabled"

        private fun getPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        /**
         * Creates a [TrackingConfig] from a Dart method channel arguments map.
         * Merges any provided values with defaults.
         */
        fun fromMap(args: Map<*, *>): TrackingConfig {
            return TrackingConfig(
                accuracy = args["accuracy"] as? Int ?: 0,
                intervalMs = (args["intervalMs"] as? Number)?.toLong() ?: 60_000L,
                distanceFilter = (args["distanceFilter"] as? Number)?.toFloat() ?: 10f,
                mode = args["mode"] as? Int ?: 1,
                enableMotionDetection = args["enableMotionDetection"] as? Boolean ?: true,
                notificationTitle = args["notificationTitle"] as? String ?: "Location Tracking",
                notificationBody = args["notificationBody"] as? String ?: "Tracking your location in the background",
                notificationPriority = args["notificationPriority"] as? Int ?: -1,
                notificationSticky = args["notificationSticky"] as? Boolean ?: true,
                stopOnTerminate = args["stopOnTerminate"] as? Boolean ?: false,
                startOnBoot = args["startOnBoot"] as? Boolean ?: true,
                enableHeadless = args["enableHeadless"] as? Boolean ?: true,
                stopTimeout = (args["stopTimeout"] as? Number)?.toLong() ?: 300_000L,
                stopDetectionDelay = (args["stopDetectionDelay"] as? Number)?.toLong() ?: 0L,
                stationaryRadius = (args["stationaryRadius"] as? Number)?.toFloat() ?: 25f,
                motionTriggerDelay = (args["motionTriggerDelay"] as? Number)?.toLong() ?: 0L,
                disableStopDetection = args["disableStopDetection"] as? Boolean ?: false,
                disableMotionActivityUpdates = args["disableMotionActivityUpdates"] as? Boolean ?: false,
                useSignificantChangesOnly = args["useSignificantChangesOnly"] as? Boolean ?: false,
                heartbeatInterval = (args["heartbeatInterval"] as? Number)?.toLong() ?: 0L,
                activityRecognitionInterval = (args["activityRecognitionInterval"] as? Number)?.toLong() ?: 10_000L,
                minimumActivityRecognitionConfidence = args["minimumActivityRecognitionConfidence"] as? Int ?: 75,
                maxDaysToPersist = args["maxDaysToPersist"] as? Int ?: 7,
                maxRecordsToPersist = args["maxRecordsToPersist"] as? Int ?: 10_000,
                persistLocations = args["persistLocations"] as? Boolean ?: true,
                preventSuspend = args["preventSuspend"] as? Boolean ?: false,
            )
        }

        /**
         * Restores a previously persisted configuration, or null if none exists.
         */
        fun restore(context: Context): TrackingConfig? {
            val prefs = getPrefs(context)
            val json = prefs.getString(KEY_CONFIG_JSON, null) ?: return null
            return try {
                val obj = JSONObject(json)
                val map = mutableMapOf<String, Any?>()
                for (key in obj.keys()) {
                    map[key] = obj.get(key)
                }
                fromMap(map)
            } catch (e: Exception) {
                null
            }
        }

        fun setTrackingEnabled(context: Context, enabled: Boolean) {
            getPrefs(context).edit().putBoolean(KEY_TRACKING_ENABLED, enabled).apply()
        }

        fun isTrackingEnabled(context: Context): Boolean =
            getPrefs(context).getBoolean(KEY_TRACKING_ENABLED, false)

        /**
         * Clears all persisted configuration.
         */
        fun clear(context: Context) {
            getPrefs(context).edit().clear().apply()
        }
    }
}
