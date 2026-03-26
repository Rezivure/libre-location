package io.rezivure.libre_location

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Centralized tracking configuration that can be persisted across restarts.
 *
 * All time values are stored in milliseconds internally.
 * Dart sends:
 *   - stillnessTimeoutMs in minutes
 *   - stillnessDelayMs in seconds (treated as ms-ready from Dart, but we handle both)
 *   - motionConfirmDelayMs in ms
 *   - heartbeatInterval in seconds
 *   - intervalMs in ms
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

    // Motion detection — all times in ms
    val stillnessTimeoutMs: Long = 300_000L,               // 5 min in ms
    val stillnessDelayMs: Long = 0L,
    val stillnessRadiusMeters: Float = 25f,              // meters
    val motionConfirmDelayMs: Long = 0L,
    val skipStillnessDetection: Boolean = false,
    val skipActivityUpdates: Boolean = false,
    val significantChangesOnly: Boolean = false,

    // Heartbeat — in seconds
    val heartbeatInterval: Long = 0L,

    // Activity recognition
    val activityCheckIntervalMs: Long = 10_000L,
    val activityConfidenceThreshold: Int = 75,

    // Persistence
    val retentionDays: Int = 7,
    val retentionMaxRecords: Int = 10_000,
    val persistLocations: Boolean = true,

    // Battery
    val keepAwake: Boolean = false,

    // GPS filtering
    val locationFilterEnabled: Boolean = true,
    val maxAccuracy: Float = 100f,
    val maxSpeed: Float = 83.33f,

    // Logging
    val logLevel: Int = 0, // 0=off, 1=error, 2=warning, 3=info, 4=debug, 5=verbose
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
        "stillnessTimeoutMin" to stillnessTimeoutMs,
        "stillnessDelayMs" to stillnessDelayMs,
        "stillnessRadiusMeters" to stillnessRadiusMeters.toDouble(),
        "motionConfirmDelayMs" to motionConfirmDelayMs,
        "skipStillnessDetection" to skipStillnessDetection,
        "skipActivityUpdates" to skipActivityUpdates,
        "significantChangesOnly" to significantChangesOnly,
        "heartbeatInterval" to heartbeatInterval,
        "activityCheckIntervalMs" to activityCheckIntervalMs,
        "activityConfidenceThreshold" to activityConfidenceThreshold,
        "retentionDays" to retentionDays,
        "retentionMaxRecords" to retentionMaxRecords,
        "persistLocations" to persistLocations,
        "keepAwake" to keepAwake,
        "locationFilterEnabled" to locationFilterEnabled,
        "maxAccuracy" to maxAccuracy.toDouble(),
        "maxSpeed" to maxSpeed.toDouble(),
        "logLevel" to logLevel,
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
         * Creates a [TrackingConfig] from Dart method channel arguments.
         * Handles unit conversions:
         *   - stillnessTimeoutMin: Dart sends minutes → convert to ms
         *   - heartbeatInterval: Dart sends seconds → keep as seconds (used as-is)
         *   - intervalMs: already in ms
         */
        fun fromMap(args: Map<*, *>): TrackingConfig {
            // Extract notification config from nested map if present
            val notificationMap = args["notification"] as? Map<*, *>
            val notifTitle = args["notificationTitle"] as? String
                ?: notificationMap?.get("title") as? String
                ?: "Location Tracking"
            val notifBody = args["notificationBody"] as? String
                ?: notificationMap?.get("text") as? String
                ?: "Tracking your location in the background"
            val notifPriority = args["notificationPriority"] as? Int
                ?: (notificationMap?.get("priority") as? Number)?.toInt()
                ?: -1
            val notifSticky = args["notificationSticky"] as? Boolean
                ?: notificationMap?.get("sticky") as? Boolean
                ?: true

            // stillnessTimeoutMin: Dart sends in minutes, convert to ms
            val stillnessMinutes = (args["stillnessTimeoutMin"] as? Number)?.toLong() ?: 5L
            val stillnessMs = stillnessMinutes * 60_000L

            return TrackingConfig(
                accuracy = args["accuracy"] as? Int ?: 0,
                intervalMs = (args["intervalMs"] as? Number)?.toLong() ?: 60_000L,
                distanceFilter = (args["distanceFilter"] as? Number)?.toFloat() ?: 10f,
                mode = args["mode"] as? Int ?: 1,
                enableMotionDetection = args["enableMotionDetection"] as? Boolean ?: true,
                notificationTitle = notifTitle,
                notificationBody = notifBody,
                notificationPriority = notifPriority,
                notificationSticky = notifSticky,
                stopOnTerminate = args["stopOnTerminate"] as? Boolean ?: false,
                startOnBoot = args["startOnBoot"] as? Boolean ?: true,
                enableHeadless = args["enableHeadless"] as? Boolean ?: true,
                stillnessTimeoutMs = stillnessMs,
                stillnessDelayMs = (args["stillnessDelayMs"] as? Number)?.toLong() ?: 0L,
                stillnessRadiusMeters = (args["stillnessRadiusMeters"] as? Number)?.toFloat() ?: 25f,
                motionConfirmDelayMs = (args["motionConfirmDelayMs"] as? Number)?.toLong() ?: 0L,
                skipStillnessDetection = args["skipStillnessDetection"] as? Boolean ?: false,
                skipActivityUpdates = args["skipActivityUpdates"] as? Boolean ?: false,
                significantChangesOnly = args["significantChangesOnly"] as? Boolean ?: false,
                heartbeatInterval = (args["heartbeatInterval"] as? Number)?.toLong() ?: 0L,
                activityCheckIntervalMs = (args["activityCheckIntervalMs"] as? Number)?.toLong() ?: 10_000L,
                activityConfidenceThreshold = args["activityConfidenceThreshold"] as? Int ?: 75,
                retentionDays = args["retentionDays"] as? Int ?: 7,
                retentionMaxRecords = args["retentionMaxRecords"] as? Int ?: 10_000,
                persistLocations = args["persistLocations"] as? Boolean ?: true,
                keepAwake = args["keepAwake"] as? Boolean ?: false,
                locationFilterEnabled = args["locationFilterEnabled"] as? Boolean ?: true,
                maxAccuracy = (args["maxAccuracy"] as? Number)?.toFloat() ?: 100f,
                maxSpeed = (args["maxSpeed"] as? Number)?.toFloat() ?: 83.33f,
                logLevel = (args["logLevel"] as? Number)?.toInt() ?: 0,
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
                // When restoring from persisted JSON, stillnessTimeoutMs is already in ms
                // so we need to handle that — use the raw value since toMap() stores ms
                TrackingConfig(
                    accuracy = (map["accuracy"] as? Number)?.toInt() ?: 0,
                    intervalMs = (map["intervalMs"] as? Number)?.toLong() ?: 60_000L,
                    distanceFilter = (map["distanceFilter"] as? Number)?.toFloat() ?: 10f,
                    mode = (map["mode"] as? Number)?.toInt() ?: 1,
                    enableMotionDetection = map["enableMotionDetection"] as? Boolean ?: true,
                    notificationTitle = map["notificationTitle"] as? String ?: "Location Tracking",
                    notificationBody = map["notificationBody"] as? String ?: "Tracking your location in the background",
                    notificationPriority = (map["notificationPriority"] as? Number)?.toInt() ?: -1,
                    notificationSticky = map["notificationSticky"] as? Boolean ?: true,
                    stopOnTerminate = map["stopOnTerminate"] as? Boolean ?: false,
                    startOnBoot = map["startOnBoot"] as? Boolean ?: true,
                    enableHeadless = map["enableHeadless"] as? Boolean ?: true,
                    stillnessTimeoutMs = (map["stillnessTimeoutMin"] as? Number)?.toLong() ?: 300_000L,
                    stillnessDelayMs = (map["stillnessDelayMs"] as? Number)?.toLong() ?: 0L,
                    stillnessRadiusMeters = (map["stillnessRadiusMeters"] as? Number)?.toFloat() ?: 25f,
                    motionConfirmDelayMs = (map["motionConfirmDelayMs"] as? Number)?.toLong() ?: 0L,
                    skipStillnessDetection = map["skipStillnessDetection"] as? Boolean ?: false,
                    skipActivityUpdates = map["skipActivityUpdates"] as? Boolean ?: false,
                    significantChangesOnly = map["significantChangesOnly"] as? Boolean ?: false,
                    heartbeatInterval = (map["heartbeatInterval"] as? Number)?.toLong() ?: 0L,
                    activityCheckIntervalMs = (map["activityCheckIntervalMs"] as? Number)?.toLong() ?: 10_000L,
                    activityConfidenceThreshold = (map["activityConfidenceThreshold"] as? Number)?.toInt() ?: 75,
                    retentionDays = (map["retentionDays"] as? Number)?.toInt() ?: 7,
                    retentionMaxRecords = (map["retentionMaxRecords"] as? Number)?.toInt() ?: 10_000,
                    persistLocations = map["persistLocations"] as? Boolean ?: true,
                    keepAwake = map["keepAwake"] as? Boolean ?: false,
                    locationFilterEnabled = map["locationFilterEnabled"] as? Boolean ?: true,
                    maxAccuracy = (map["maxAccuracy"] as? Number)?.toFloat() ?: 100f,
                    maxSpeed = (map["maxSpeed"] as? Number)?.toFloat() ?: 83.33f,
                    logLevel = (map["logLevel"] as? Number)?.toInt() ?: 0,
                )
            } catch (e: Exception) {
                null
            }
        }

        fun setTrackingEnabled(context: Context, enabled: Boolean) {
            getPrefs(context).edit().putBoolean(KEY_TRACKING_ENABLED, enabled).apply()
        }

        fun isTrackingEnabled(context: Context): Boolean =
            getPrefs(context).getBoolean(KEY_TRACKING_ENABLED, false)

        fun clear(context: Context) {
            getPrefs(context).edit().clear().apply()
        }
    }
}
