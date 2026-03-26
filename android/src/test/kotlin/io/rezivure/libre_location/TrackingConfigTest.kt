package io.rezivure.libre_location

import org.junit.Assert.*
import org.junit.Test

class TrackingConfigTest {

    @Test
    fun `default values are sensible`() {
        val config = TrackingConfig()
        assertEquals(0, config.accuracy)
        assertEquals(60_000L, config.intervalMs)
        assertEquals(10f, config.distanceFilter)
        assertEquals(1, config.mode)
        assertTrue(config.enableMotionDetection)
        assertEquals(300_000L, config.stopTimeout)
        assertEquals(25f, config.stationaryRadius)
        assertFalse(config.stopOnTerminate)
        assertTrue(config.startOnBoot)
        assertTrue(config.locationFilterEnabled)
        assertEquals(100f, config.maxAccuracy)
        assertEquals(83.33f, config.maxSpeed)
    }

    @Test
    fun `fromMap parses Dart arguments correctly`() {
        val args = mapOf<String, Any>(
            "accuracy" to 2,
            "intervalMs" to 30000L,
            "distanceFilter" to 50.0,
            "mode" to 0,
            "enableMotionDetection" to false,
            "stopTimeout" to 10L, // Dart sends minutes
            "stationaryRadius" to 100.0,
            "stopOnTerminate" to true,
            "startOnBoot" to false,
            "heartbeatInterval" to 300L,
            "locationFilterEnabled" to false,
            "maxAccuracy" to 200.0,
            "maxSpeed" to 50.0,
            "logLevel" to 3,
        )
        val config = TrackingConfig.fromMap(args)

        assertEquals(2, config.accuracy)
        assertEquals(30000L, config.intervalMs)
        assertEquals(50f, config.distanceFilter)
        assertEquals(0, config.mode)
        assertFalse(config.enableMotionDetection)
        assertEquals(600_000L, config.stopTimeout) // 10 min * 60_000
        assertEquals(100f, config.stationaryRadius)
        assertTrue(config.stopOnTerminate)
        assertFalse(config.startOnBoot)
        assertEquals(300L, config.heartbeatInterval)
        assertFalse(config.locationFilterEnabled)
        assertEquals(200f, config.maxAccuracy)
        assertEquals(50f, config.maxSpeed)
        assertEquals(3, config.logLevel)
    }

    @Test
    fun `fromMap uses defaults for missing keys`() {
        val config = TrackingConfig.fromMap(emptyMap<String, Any>())
        assertEquals(0, config.accuracy)
        assertEquals(60_000L, config.intervalMs)
        assertEquals(10f, config.distanceFilter)
        assertEquals(1, config.mode)
        assertTrue(config.enableMotionDetection)
    }

    @Test
    fun `toMap roundtrip preserves values`() {
        val original = TrackingConfig(
            accuracy = 3,
            intervalMs = 120_000L,
            distanceFilter = 25f,
            mode = 2,
            heartbeatInterval = 60L,
        )
        val map = original.toMap()
        assertEquals(3, map["accuracy"])
        assertEquals(120_000L, map["intervalMs"])
        assertEquals(25.0, map["distanceFilter"])
        assertEquals(2, map["mode"])
        assertEquals(60L, map["heartbeatInterval"])
    }

    @Test
    fun `fromMap handles notification nested map`() {
        val args = mapOf<String, Any>(
            "notification" to mapOf(
                "title" to "Custom Title",
                "text" to "Custom Body",
                "priority" to -2,
                "sticky" to false,
            )
        )
        val config = TrackingConfig.fromMap(args)
        assertEquals("Custom Title", config.notificationTitle)
        assertEquals("Custom Body", config.notificationBody)
        assertEquals(-2, config.notificationPriority)
        assertFalse(config.notificationSticky)
    }

    @Test
    fun `fromMap top-level notification overrides nested`() {
        val args = mapOf<String, Any>(
            "notificationTitle" to "Top Level",
            "notification" to mapOf("title" to "Nested"),
        )
        val config = TrackingConfig.fromMap(args)
        assertEquals("Top Level", config.notificationTitle)
    }

    @Test
    fun `stopTimeout conversion from minutes to ms`() {
        val args = mapOf<String, Any>("stopTimeout" to 1)
        val config = TrackingConfig.fromMap(args)
        assertEquals(60_000L, config.stopTimeout)
    }
}
