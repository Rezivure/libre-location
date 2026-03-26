package io.rezivure.libre_location

import android.content.Context
import android.location.Location
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.mock

class GeofenceManagerTest {

    private lateinit var context: Context
    private val events = mutableListOf<Map<String, Any?>>()
    private lateinit var manager: GeofenceManager

    @Before
    fun setup() {
        context = mock(Context::class.java)
        events.clear()
        manager = GeofenceManager(context) { events.add(it) }
    }

    @Test
    fun `addGeofence stores geofence`() {
        manager.addGeofence("test", 37.42, -122.08, 100f, listOf(0, 1), null)
        val geofences = manager.getGeofences()
        assertEquals(1, geofences.size)
        assertEquals("test", geofences[0]["id"])
        assertEquals(37.42, geofences[0]["latitude"])
        assertEquals(-122.08, geofences[0]["longitude"])
        assertEquals(100.0, geofences[0]["radiusMeters"])
    }

    @Test
    fun `removeGeofence removes it`() {
        manager.addGeofence("test", 37.42, -122.08, 100f, listOf(0), null)
        manager.removeGeofence("test")
        assertTrue(manager.getGeofences().isEmpty())
    }

    @Test
    fun `removeAllGeofences clears all`() {
        manager.addGeofence("a", 37.0, -122.0, 50f, listOf(0), null)
        manager.addGeofence("b", 38.0, -121.0, 50f, listOf(0), null)
        manager.removeAllGeofences()
        assertTrue(manager.getGeofences().isEmpty())
    }

    @Test
    fun `enter event fires when crossing into geofence`() {
        manager.addGeofence("home", 37.42, -122.08, 100f, listOf(0), null)

        // Location far away — no event
        val farLocation = createLocation(38.0, -121.0)
        manager.onLocationUpdate(farLocation)
        assertTrue(events.isEmpty())

        // Location inside geofence — enter event
        val insideLocation = createLocation(37.42, -122.08)
        manager.onLocationUpdate(insideLocation)
        assertEquals(1, events.size)
        assertEquals(0, events[0]["transition"])
    }

    @Test
    fun `exit event fires when leaving geofence`() {
        manager.addGeofence("home", 37.42, -122.08, 100f, listOf(0, 1), null)

        // Enter
        manager.onLocationUpdate(createLocation(37.42, -122.08))
        assertEquals(1, events.size)

        // Exit
        manager.onLocationUpdate(createLocation(38.0, -121.0))
        assertEquals(2, events.size)
        assertEquals(1, events[1]["transition"])
    }

    @Test
    fun `no duplicate enter events while inside`() {
        manager.addGeofence("home", 37.42, -122.08, 100f, listOf(0), null)

        manager.onLocationUpdate(createLocation(37.42, -122.08))
        manager.onLocationUpdate(createLocation(37.4201, -122.0801)) // still inside
        assertEquals(1, events.size)
    }

    @Test
    fun `no exit event if exit trigger not configured`() {
        manager.addGeofence("home", 37.42, -122.08, 100f, listOf(0), null) // enter only

        manager.onLocationUpdate(createLocation(37.42, -122.08))
        manager.onLocationUpdate(createLocation(38.0, -121.0)) // exit
        // Only the enter event
        assertEquals(1, events.size)
        assertEquals(0, events[0]["transition"])
    }

    @Test
    fun `distance calculation is correct for enter-exit`() {
        // 200m radius geofence
        manager.addGeofence("zone", 0.0, 0.0, 200f, listOf(0, 1), null)

        // ~111m away (0.001 degrees latitude ≈ 111m)
        manager.onLocationUpdate(createLocation(0.001, 0.0))
        assertEquals(1, events.size) // inside 200m

        // ~333m away
        manager.onLocationUpdate(createLocation(0.003, 0.0))
        assertEquals(2, events.size) // exit
    }

    @Test
    fun `geofence event contains correct structure`() {
        manager.addGeofence("cafe", 37.42, -122.08, 50f, listOf(0), null)
        manager.onLocationUpdate(createLocation(37.42, -122.08))

        val event = events[0]
        assertNotNull(event["timestamp"])
        assertEquals(0, event["transition"])
        val geofence = event["geofence"] as Map<*, *>
        assertEquals("cafe", geofence["id"])
        assertEquals(37.42, geofence["latitude"])
    }

    @Test
    fun `destroy clears everything`() {
        manager.addGeofence("test", 0.0, 0.0, 100f, listOf(0), null)
        manager.destroy()
        assertTrue(manager.getGeofences().isEmpty())
    }

    private fun createLocation(lat: Double, lng: Double): Location {
        return Location("test").apply {
            latitude = lat
            longitude = lng
            time = System.currentTimeMillis()
            accuracy = 10f
        }
    }
}
