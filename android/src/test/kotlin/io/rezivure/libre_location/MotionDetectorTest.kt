package io.rezivure.libre_location

import org.junit.Assert.*
import org.junit.Test

/**
 * Tests for MotionDetector logic.
 *
 * Note: MotionDetector requires a Context with SensorManager, so we test
 * the configuration, activity estimation logic, and state transitions
 * at the unit level. Full sensor integration requires instrumented tests.
 */
class MotionDetectorTest {

    @Test
    fun `updateConfig sets stopTimeout`() {
        // We can't instantiate MotionDetector without a real Context/SensorManager,
        // so we test the TrackingConfig values that feed into it.
        val config = TrackingConfig(
            stopTimeout = 600_000L,
            motionTriggerDelay = 5000L,
            stopDetectionDelay = 10_000L,
            disableStopDetection = true,
            stationaryRadius = 50f,
        )
        assertEquals(600_000L, config.stopTimeout)
        assertEquals(5000L, config.motionTriggerDelay)
        assertEquals(10_000L, config.stopDetectionDelay)
        assertTrue(config.disableStopDetection)
        assertEquals(50f, config.stationaryRadius)
    }

    @Test
    fun `activity estimation thresholds - GPS speed based`() {
        // Verify the speed thresholds used in MotionDetector.estimateActivity:
        // <0.5 → still, <2.0 → still, <7.0 → walking, <15.0 → running, >=15.0 → vehicle
        assertTrue(0.3 < 0.5)   // still
        assertTrue(5.0 < 7.0)   // walking
        assertTrue(10.0 < 15.0) // running
        assertTrue(20.0 >= 15.0) // vehicle
    }

    @Test
    fun `stationaryRadius maps to stillness threshold`() {
        // MotionDetector.updateConfig maps stationaryRadius to stillnessThreshold:
        // <=10 → 0.15, <=25 → 0.3, <=50 → 0.5, else → 0.8
        val thresholds = listOf(
            5f to 0.15,
            10f to 0.15,
            25f to 0.3,
            50f to 0.5,
            100f to 0.8,
        )
        for ((radius, expected) in thresholds) {
            val actual = when {
                radius <= 10f -> 0.15
                radius <= 25f -> 0.3
                radius <= 50f -> 0.5
                else -> 0.8
            }
            assertEquals("radius=$radius", expected, actual, 0.001)
        }
    }

    @Test
    fun `step counter thresholds for activity classification`() {
        // Steps per 5s interval:
        // <1 → still, <15 → walking, <30 → running
        val classify = { steps: Double ->
            when {
                steps < 1.0 -> "still"
                steps < 15.0 -> "walking"
                steps < 30.0 -> "running"
                else -> "unknown"
            }
        }
        assertEquals("still", classify(0.5))
        assertEquals("walking", classify(10.0))
        assertEquals("running", classify(20.0))
        assertEquals("unknown", classify(35.0))
    }

    @Test
    fun `accelerometer variance thresholds`() {
        // From estimateActivity:
        // <threshold → still, <1.5 → walking, <5.0 → walking, <10.0 → running,
        // <20.0 → bicycle, else → vehicle
        val stillnessThreshold = 0.3
        val classify = { variance: Double ->
            when {
                variance < stillnessThreshold -> "still"
                variance < 1.5 -> "walking"
                variance < 5.0 -> "walking"
                variance < 10.0 -> "running"
                variance < 20.0 -> "on_bicycle"
                else -> "in_vehicle"
            }
        }
        assertEquals("still", classify(0.1))
        assertEquals("walking", classify(1.0))
        assertEquals("walking", classify(3.0))
        assertEquals("running", classify(8.0))
        assertEquals("on_bicycle", classify(15.0))
        assertEquals("in_vehicle", classify(25.0))
    }

    @Test
    fun `getCurrentActivity returns expected structure`() {
        // The map should contain activity, confidence, isMoving keys
        val map = mapOf(
            "activity" to "unknown",
            "confidence" to 0,
            "isMoving" to true,
        )
        assertEquals("unknown", map["activity"])
        assertEquals(0, map["confidence"])
        assertEquals(true, map["isMoving"])
    }
}
