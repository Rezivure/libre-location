package io.rezivure.libre_location

import android.location.Location
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class LocationDatabaseTest {

    private lateinit var db: LocationDatabase

    @Before
    fun setup() {
        db = LocationDatabase(RuntimeEnvironment.getApplication())
    }

    @After
    fun teardown() {
        db.clearAll()
        db.close()
    }

    @Test
    fun `insert and query location`() {
        val location = createLocation(37.42, -122.08)
        val id = db.insertLocation(location, isMoving = true)
        assertTrue(id > 0)

        val records = db.getUndeliveredLocations()
        assertEquals(1, records.size)
        assertEquals(37.42, records[0]["latitude"] as Double, 0.001)
        assertEquals(-122.08, records[0]["longitude"] as Double, 0.001)
        assertEquals(true, records[0]["isMoving"])
    }

    @Test
    fun `insertLocationMap works`() {
        val map = mapOf<String, Any?>(
            "latitude" to 38.0,
            "longitude" to -121.0,
            "altitude" to 100.0,
            "accuracy" to 5.0,
            "speed" to 2.0,
            "heading" to 90.0,
            "timestamp" to System.currentTimeMillis(),
            "provider" to "gps",
            "isMoving" to false,
        )
        val id = db.insertLocationMap(map)
        assertTrue(id > 0)

        val records = db.getUndeliveredLocations()
        assertEquals(1, records.size)
        assertEquals(38.0, records[0]["latitude"] as Double, 0.001)
        assertEquals(false, records[0]["isMoving"])
    }

    @Test
    fun `markDelivered excludes from undelivered query`() {
        val id = db.insertLocation(createLocation(37.0, -122.0))
        db.markDelivered(listOf(id))
        val records = db.getUndeliveredLocations()
        assertTrue(records.isEmpty())
    }

    @Test
    fun `getRecordCount returns correct count`() {
        assertEquals(0, db.getRecordCount())
        db.insertLocation(createLocation(37.0, -122.0))
        db.insertLocation(createLocation(38.0, -121.0))
        assertEquals(2, db.getRecordCount())
    }

    @Test
    fun `purgeDelivered removes only delivered records`() {
        val id1 = db.insertLocation(createLocation(37.0, -122.0))
        db.insertLocation(createLocation(38.0, -121.0))
        db.markDelivered(listOf(id1))
        db.purgeDelivered()
        assertEquals(1, db.getRecordCount())
    }

    @Test
    fun `enforceRetention by maxRecords`() {
        for (i in 0 until 20) {
            val loc = createLocation(37.0 + i * 0.01, -122.0)
            loc.time = System.currentTimeMillis() + i * 1000
            db.insertLocation(loc)
        }
        assertEquals(20, db.getRecordCount())
        db.enforceRetention(maxDays = 0, maxRecords = 10)
        assertEquals(10, db.getRecordCount())
    }

    @Test
    fun `enforceRetention by maxDays`() {
        val oldLocation = createLocation(37.0, -122.0)
        oldLocation.time = System.currentTimeMillis() - (8 * 86_400_000L) // 8 days ago
        db.insertLocation(oldLocation)

        val recentLocation = createLocation(38.0, -121.0)
        recentLocation.time = System.currentTimeMillis()
        db.insertLocation(recentLocation)

        db.enforceRetention(maxDays = 7, maxRecords = 0)
        assertEquals(1, db.getRecordCount())
    }

    @Test
    fun `clearAll removes everything`() {
        db.insertLocation(createLocation(37.0, -122.0))
        db.insertLocation(createLocation(38.0, -121.0))
        db.clearAll()
        assertEquals(0, db.getRecordCount())
    }

    @Test
    fun `config key-value storage`() {
        db.setConfigValue("test_key", "test_value")
        assertEquals("test_value", db.getConfigValue("test_key"))
    }

    @Test
    fun `config key-value returns null for missing key`() {
        assertNull(db.getConfigValue("nonexistent"))
    }

    @Test
    fun `config key-value overwrites`() {
        db.setConfigValue("key", "value1")
        db.setConfigValue("key", "value2")
        assertEquals("value2", db.getConfigValue("key"))
    }

    @Test
    fun `getAllConfig returns all pairs`() {
        db.setConfigValue("a", "1")
        db.setConfigValue("b", "2")
        val all = db.getAllConfig()
        assertEquals("1", all["a"])
        assertEquals("2", all["b"])
    }

    @Test
    fun `undelivered locations ordered by timestamp`() {
        val loc1 = createLocation(37.0, -122.0)
        loc1.time = 2000
        db.insertLocation(loc1)

        val loc2 = createLocation(38.0, -121.0)
        loc2.time = 1000
        db.insertLocation(loc2)

        val records = db.getUndeliveredLocations()
        assertEquals(2, records.size)
        assertTrue((records[0]["timestamp"] as Long) < (records[1]["timestamp"] as Long))
    }

    private fun createLocation(lat: Double, lng: Double): Location {
        return Location("test").apply {
            latitude = lat
            longitude = lng
            altitude = 0.0
            accuracy = 10f
            speed = 0f
            bearing = 0f
            time = System.currentTimeMillis()
        }
    }
}
