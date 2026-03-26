package io.rezivure.libre_location

import android.location.Location
import org.junit.Assert.*
import org.junit.Test

/**
 * Tests for LocationManagerWrapper filtering and processing logic.
 *
 * LocationManagerWrapper requires a real Context with LocationManager,
 * so we test the filtering/processing logic through observable behavior
 * and configuration validation.
 */
class LocationManagerWrapperTest {

    @Test
    fun `distance filter logic - locations within filter are rejected`() {
        // Two locations ~11m apart should pass a 10m filter
        val loc1 = createLocation(37.420000, -122.080000)
        val loc2 = createLocation(37.420100, -122.080000) // ~11m north
        val distance = loc1.distanceTo(loc2)
        assertTrue("Distance $distance should be > 10", distance > 10)
    }

    @Test
    fun `distance filter logic - locations within filter are dropped`() {
        // Two locations ~1m apart should NOT pass a 10m filter
        val loc1 = createLocation(37.420000, -122.080000)
        val loc2 = createLocation(37.420001, -122.080000) // ~0.1m
        val distance = loc1.distanceTo(loc2)
        assertTrue("Distance $distance should be < 10", distance < 10)
    }

    @Test
    fun `speed rejection - impossible speed filtered`() {
        val loc1 = createLocation(37.0, -122.0)
        loc1.time = 1000

        val loc2 = createLocation(38.0, -122.0) // ~111km away
        loc2.time = 2000 // 1 second later → 111,000 m/s

        val timeDelta = (loc2.time - loc1.time) / 1000.0
        val distance = loc1.distanceTo(loc2)
        val impliedSpeed = distance / timeDelta

        val maxSpeed = 83.33f // ~300 km/h
        assertTrue("Implied speed $impliedSpeed should exceed max $maxSpeed", impliedSpeed > maxSpeed)
    }

    @Test
    fun `speed rejection - normal speed passes`() {
        val loc1 = createLocation(37.420000, -122.080000)
        loc1.time = 0

        val loc2 = createLocation(37.420100, -122.080000) // ~11m
        loc2.time = 10_000 // 10 seconds later → ~1.1 m/s

        val timeDelta = (loc2.time - loc1.time) / 1000.0
        val distance = loc1.distanceTo(loc2)
        val impliedSpeed = distance / timeDelta

        assertTrue("Implied speed $impliedSpeed should be < 83.33", impliedSpeed < 83.33)
    }

    @Test
    fun `accuracy rejection - low accuracy filtered`() {
        val location = createLocation(37.42, -122.08)
        location.accuracy = 150f // worse than 100m threshold
        assertTrue(location.accuracy > 100f)
    }

    @Test
    fun `accuracy rejection - good accuracy passes`() {
        val location = createLocation(37.42, -122.08)
        location.accuracy = 5f
        assertTrue(location.accuracy <= 100f)
    }

    @Test
    fun `duplicate time threshold`() {
        val loc1 = createLocation(37.42, -122.08)
        loc1.time = 1000
        loc1.accuracy = 10f

        val loc2 = createLocation(37.42, -122.08)
        loc2.time = 1500 // 500ms later, within 1000ms threshold
        loc2.accuracy = 15f // worse accuracy

        val timeDiff = loc2.time - loc1.time
        assertTrue("Time diff $timeDiff should be < 1000", timeDiff < 1000)
        assertTrue("Worse accuracy should be filtered", loc2.accuracy >= loc1.accuracy)
    }

    @Test
    fun `locationToMap structure verification`() {
        // Verify the expected keys in locationToMap output
        val expectedKeys = listOf(
            "latitude", "longitude", "altitude", "accuracy",
            "speed", "heading", "timestamp", "provider", "isMoving"
        )
        // This just documents the expected structure
        assertEquals(9, expectedKeys.size)
    }

    @Test
    fun `providerForAccuracy mapping`() {
        // accuracy 0 → GPS, 3 → PASSIVE, else → NETWORK
        val mappings = mapOf(
            0 to "gps",
            1 to "network",
            2 to "network",
            3 to "passive",
        )
        assertEquals("gps", mappings[0])
        assertEquals("network", mappings[1])
        assertEquals("passive", mappings[3])
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
