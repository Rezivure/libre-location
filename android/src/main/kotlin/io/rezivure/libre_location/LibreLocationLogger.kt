package io.rezivure.libre_location

import android.util.Log
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.ConcurrentLinkedDeque

/**
 * Structured logging system for the Android native layer.
 * Uses android.util.Log with tag "LibreLocation" and respects the configured log level.
 * Stores the last N entries in memory for retrieval via getLog().
 */
object LibreLocationLogger {
    private const val TAG = "LibreLocation"
    private const val MAX_ENTRIES = 500

    // LogLevel: 0=off, 1=error, 2=warning, 3=info, 4=debug, 5=verbose
    @Volatile
    var logLevel: Int = 0

    private val entries = ConcurrentLinkedDeque<Map<String, Any>>()
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)

    fun verbose(message: String) = log(5, "verbose", message)
    fun debug(message: String) = log(4, "debug", message)
    fun info(message: String) = log(3, "info", message)
    fun warning(message: String) = log(2, "warning", message)
    fun error(message: String) = log(1, "error", message)

    private fun log(level: Int, levelName: String, message: String) {
        if (logLevel == 0 || level > logLevel) return

        // Write to android.util.Log
        when (level) {
            1 -> Log.e(TAG, message)
            2 -> Log.w(TAG, message)
            3 -> Log.i(TAG, message)
            4 -> Log.d(TAG, message)
            5 -> Log.v(TAG, message)
        }

        // Store in ring buffer
        val entry = mapOf<String, Any>(
            "timestamp" to dateFormat.format(Date()),
            "level" to levelName,
            "message" to message,
            "platform" to "android",
        )
        entries.addLast(entry)
        while (entries.size > MAX_ENTRIES) {
            entries.pollFirst()
        }
    }

    fun getLog(): List<Map<String, Any>> = entries.toList()

    fun clear() = entries.clear()
}
