package io.rezivure.libre_location

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.location.Location

/**
 * SQLite-backed local persistence for location records.
 *
 * Buffers locations when the Flutter engine is unavailable (headless mode,
 * app terminated) and enforces configurable retention limits via
 * [maxDaysToPersist] and [maxRecordsToPersist].
 */
class LocationDatabase(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val DATABASE_NAME = "libre_location.db"
        private const val DATABASE_VERSION = 2

        private const val TABLE_LOCATIONS = "locations"
        private const val COL_ID = "id"
        private const val COL_LATITUDE = "latitude"
        private const val COL_LONGITUDE = "longitude"
        private const val COL_ALTITUDE = "altitude"
        private const val COL_ACCURACY = "accuracy"
        private const val COL_SPEED = "speed"
        private const val COL_HEADING = "heading"
        private const val COL_TIMESTAMP = "timestamp"
        private const val COL_PROVIDER = "provider"
        private const val COL_IS_MOVING = "is_moving"
        private const val COL_ACTIVITY_TYPE = "activity_type"
        private const val COL_ACTIVITY_CONFIDENCE = "activity_confidence"
        private const val COL_DELIVERED = "delivered"

        private const val TABLE_CONFIG = "config"
        private const val COL_KEY = "key"
        private const val COL_VALUE = "value"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE $TABLE_LOCATIONS (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_LATITUDE REAL NOT NULL,
                $COL_LONGITUDE REAL NOT NULL,
                $COL_ALTITUDE REAL DEFAULT 0,
                $COL_ACCURACY REAL DEFAULT 0,
                $COL_SPEED REAL DEFAULT 0,
                $COL_HEADING REAL DEFAULT 0,
                $COL_TIMESTAMP INTEGER NOT NULL,
                $COL_PROVIDER TEXT DEFAULT 'unknown',
                $COL_IS_MOVING INTEGER DEFAULT 1,
                $COL_ACTIVITY_TYPE TEXT,
                $COL_ACTIVITY_CONFIDENCE INTEGER DEFAULT 0,
                $COL_DELIVERED INTEGER DEFAULT 0
            )
        """)
        db.execSQL("""
            CREATE INDEX idx_locations_timestamp ON $TABLE_LOCATIONS($COL_TIMESTAMP)
        """)
        db.execSQL("""
            CREATE INDEX idx_locations_delivered ON $TABLE_LOCATIONS($COL_DELIVERED)
        """)
        db.execSQL("""
            CREATE TABLE $TABLE_CONFIG (
                $COL_KEY TEXT PRIMARY KEY,
                $COL_VALUE TEXT
            )
        """)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE $TABLE_LOCATIONS ADD COLUMN $COL_IS_MOVING INTEGER DEFAULT 1")
            db.execSQL("ALTER TABLE $TABLE_LOCATIONS ADD COLUMN $COL_ACTIVITY_TYPE TEXT")
            db.execSQL("ALTER TABLE $TABLE_LOCATIONS ADD COLUMN $COL_ACTIVITY_CONFIDENCE INTEGER DEFAULT 0")
        }
    }

    /**
     * Inserts a location record into the buffer.
     */
    fun insertLocation(
        location: Location,
        isMoving: Boolean = true,
        activityType: String? = null,
        activityConfidence: Int = 0
    ): Long {
        val values = ContentValues().apply {
            put(COL_LATITUDE, location.latitude)
            put(COL_LONGITUDE, location.longitude)
            put(COL_ALTITUDE, location.altitude)
            put(COL_ACCURACY, location.accuracy.toDouble())
            put(COL_SPEED, location.speed.toDouble())
            put(COL_HEADING, location.bearing.toDouble())
            put(COL_TIMESTAMP, location.time)
            put(COL_PROVIDER, location.provider ?: "unknown")
            put(COL_IS_MOVING, if (isMoving) 1 else 0)
            put(COL_ACTIVITY_TYPE, activityType)
            put(COL_ACTIVITY_CONFIDENCE, activityConfidence)
            put(COL_DELIVERED, 0)
        }
        return writableDatabase.insert(TABLE_LOCATIONS, null, values)
    }

    /**
     * Inserts a location from a map representation.
     */
    fun insertLocationMap(map: Map<String, Any?>): Long {
        val values = ContentValues().apply {
            put(COL_LATITUDE, map["latitude"] as Double)
            put(COL_LONGITUDE, map["longitude"] as Double)
            put(COL_ALTITUDE, (map["altitude"] as? Number)?.toDouble() ?: 0.0)
            put(COL_ACCURACY, (map["accuracy"] as? Number)?.toDouble() ?: 0.0)
            put(COL_SPEED, (map["speed"] as? Number)?.toDouble() ?: 0.0)
            put(COL_HEADING, (map["heading"] as? Number)?.toDouble() ?: 0.0)
            put(COL_TIMESTAMP, (map["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis())
            put(COL_PROVIDER, map["provider"] as? String ?: "unknown")
            put(COL_IS_MOVING, if (map["isMoving"] as? Boolean != false) 1 else 0)
            put(COL_ACTIVITY_TYPE, map["activityType"] as? String)
            put(COL_ACTIVITY_CONFIDENCE, (map["activityConfidence"] as? Number)?.toInt() ?: 0)
            put(COL_DELIVERED, 0)
        }
        return writableDatabase.insert(TABLE_LOCATIONS, null, values)
    }

    /**
     * Retrieves all undelivered location records.
     */
    fun getUndeliveredLocations(limit: Int = 1000): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val cursor = readableDatabase.query(
            TABLE_LOCATIONS,
            null,
            "$COL_DELIVERED = 0",
            null, null, null,
            "$COL_TIMESTAMP ASC",
            limit.toString()
        )
        cursor.use {
            while (it.moveToNext()) {
                results.add(mapOf(
                    "id" to it.getLong(it.getColumnIndexOrThrow(COL_ID)),
                    "latitude" to it.getDouble(it.getColumnIndexOrThrow(COL_LATITUDE)),
                    "longitude" to it.getDouble(it.getColumnIndexOrThrow(COL_LONGITUDE)),
                    "altitude" to it.getDouble(it.getColumnIndexOrThrow(COL_ALTITUDE)),
                    "accuracy" to it.getDouble(it.getColumnIndexOrThrow(COL_ACCURACY)),
                    "speed" to it.getDouble(it.getColumnIndexOrThrow(COL_SPEED)),
                    "heading" to it.getDouble(it.getColumnIndexOrThrow(COL_HEADING)),
                    "timestamp" to it.getLong(it.getColumnIndexOrThrow(COL_TIMESTAMP)),
                    "provider" to it.getString(it.getColumnIndexOrThrow(COL_PROVIDER)),
                    "isMoving" to (it.getInt(it.getColumnIndexOrThrow(COL_IS_MOVING)) == 1),
                    "activityType" to it.getString(it.getColumnIndexOrThrow(COL_ACTIVITY_TYPE)),
                    "activityConfidence" to it.getInt(it.getColumnIndexOrThrow(COL_ACTIVITY_CONFIDENCE)),
                ))
            }
        }
        return results
    }

    /**
     * Marks records as delivered.
     */
    fun markDelivered(ids: List<Long>) {
        if (ids.isEmpty()) return
        val placeholders = ids.joinToString(",") { "?" }
        val args = ids.map { it.toString() }.toTypedArray()
        writableDatabase.execSQL(
            "UPDATE $TABLE_LOCATIONS SET $COL_DELIVERED = 1 WHERE $COL_ID IN ($placeholders)",
            args
        )
    }

    /**
     * Enforces retention limits. Call periodically.
     */
    fun enforceRetention(maxDays: Int, maxRecords: Int) {
        // Delete records older than maxDays
        if (maxDays > 0) {
            val cutoff = System.currentTimeMillis() - (maxDays * 86_400_000L)
            writableDatabase.delete(TABLE_LOCATIONS, "$COL_TIMESTAMP < ?", arrayOf(cutoff.toString()))
        }

        // Delete excess records (keep most recent maxRecords)
        if (maxRecords > 0) {
            writableDatabase.execSQL("""
                DELETE FROM $TABLE_LOCATIONS WHERE $COL_ID NOT IN (
                    SELECT $COL_ID FROM $TABLE_LOCATIONS ORDER BY $COL_TIMESTAMP DESC LIMIT ?
                )
            """, arrayOf(maxRecords))
        }
    }

    /**
     * Returns the total number of stored records.
     */
    fun getRecordCount(): Int {
        val cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM $TABLE_LOCATIONS", null)
        cursor.use {
            return if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    /**
     * Deletes all delivered records.
     */
    fun purgeDelivered() {
        writableDatabase.delete(TABLE_LOCATIONS, "$COL_DELIVERED = 1", null)
    }

    /**
     * Persists a configuration key-value pair.
     */
    fun setConfigValue(key: String, value: String?) {
        val cv = ContentValues().apply {
            put(COL_KEY, key)
            put(COL_VALUE, value)
        }
        writableDatabase.insertWithOnConflict(TABLE_CONFIG, null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    /**
     * Retrieves a persisted configuration value.
     */
    fun getConfigValue(key: String): String? {
        val cursor = readableDatabase.query(
            TABLE_CONFIG, arrayOf(COL_VALUE),
            "$COL_KEY = ?", arrayOf(key),
            null, null, null
        )
        cursor.use {
            return if (it.moveToFirst()) it.getString(0) else null
        }
    }

    /**
     * Retrieves all persisted configuration as a map.
     */
    fun getAllConfig(): Map<String, String> {
        val result = mutableMapOf<String, String>()
        val cursor = readableDatabase.query(TABLE_CONFIG, null, null, null, null, null, null)
        cursor.use {
            while (it.moveToNext()) {
                val key = it.getString(it.getColumnIndexOrThrow(COL_KEY))
                val value = it.getString(it.getColumnIndexOrThrow(COL_VALUE))
                if (value != null) result[key] = value
            }
        }
        return result
    }

    /**
     * Clears all location data.
     */
    fun clearAll() {
        writableDatabase.delete(TABLE_LOCATIONS, null, null)
    }
}
