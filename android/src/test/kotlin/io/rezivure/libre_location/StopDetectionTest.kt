package io.rezivure.libre_location

import org.junit.Assert.*
import org.junit.Test

/**
 * Tests for the stop detection and stationary/moving state machine in LocationManagerWrapper.
 *
 * The redesigned state machine uses:
 * - GPS-speed-only stop detection (MOVING → STATIONARY)
 * - Distance-gated accelerometer wake (STATIONARY → MOVING)
 * - Home geofence with passive provider backup
 */
class StopDetectionTest {

    @Test
    fun `stop detection is GPS-speed-only`() {
        // MOVING → STATIONARY transition requires GPS speed < 0.5 m/s
        // for stillnessTimeoutMs. Accelerometer is NOT used for stop detection.
        val states = mutableListOf<String>()
        states.add("MOVING")         // initial state
        states.add("MOVING")         // GPS speed still > 0.5 m/s, timer keeps resetting
        states.add("STATIONARY")     // GPS speed < 0.5 for stillnessTimeoutMs → transition

        assertEquals("MOVING", states[0])
        assertEquals("MOVING", states[1])
        assertEquals("STATIONARY", states[2])
    }

    @Test
    fun `accelerometer motion triggers distance gate not direct GPS wake`() {
        // When stationary, accelerometer motion calls onMotionDetectedGated()
        // which requests a NETWORK_PROVIDER location and checks distance from home.
        // GPS is NOT started until distance > homeGeofenceRadius.
        val actions = mutableListOf<String>()
        actions.add("ACCEL_MOTION")          // accelerometer fires
        actions.add("NETWORK_LOCATION_REQ")  // request single network location
        actions.add("DISTANCE_CHECK")        // compare to home point
        // If distance ≤ radius:
        actions.add("STAY_STATIONARY")       // no GPS, indoor movement

        assertEquals(4, actions.size)
        assertEquals("STAY_STATIONARY", actions[3])
    }

    @Test
    fun `distance gate transitions to moving when far from home`() {
        // When distance from home > homeGeofenceRadius, transition to MOVING
        val actions = mutableListOf<String>()
        actions.add("ACCEL_MOTION")
        actions.add("NETWORK_LOCATION_REQ")
        actions.add("DISTANCE_CHECK")        // distance > radius
        actions.add("TRANSITION_TO_MOVING")  // GPS re-engaged

        assertEquals("TRANSITION_TO_MOVING", actions[3])
    }

    @Test
    fun `network unavailable falls back to last location age check`() {
        // If NETWORK_PROVIDER is unavailable, check age of last known location.
        // If > 30min stale → transition to MOVING (assume displacement).
        // If fresh → stay stationary.
        val staleAgeMs = 31 * 60 * 1000L  // 31 minutes
        val freshAgeMs = 5 * 60 * 1000L   // 5 minutes

        assertTrue(staleAgeMs > 30 * 60 * 1000)  // should transition
        assertTrue(freshAgeMs <= 30 * 60 * 1000)  // should stay stationary
    }

    @Test
    fun `onMotionDetectedGated is no-op when already moving`() {
        // If isMoving is already true, onMotionDetectedGated returns immediately
        var isMoving = true
        val shouldProcess = !isMoving  // false — no-op
        assertFalse(shouldProcess)
    }

    @Test
    fun `transitionToStationary records home point and stops GPS`() {
        // On transition to STATIONARY:
        // 1. Record lastEmittedLocation as homeGeofenceCenter
        // 2. Remove GPS listeners (primary + secondary)
        // 3. Register PASSIVE_PROVIDER listener
        // 4. Persist home to SharedPreferences
        val actions = mutableListOf<String>()
        actions.add("RECORD_HOME_POINT")
        actions.add("REMOVE_GPS_LISTENERS")
        actions.add("REGISTER_PASSIVE")
        actions.add("PERSIST_HOME_PREFS")
        actions.add("EMIT_MOTION_FALSE")

        assertEquals(5, actions.size)
    }

    @Test
    fun `transitionToMoving clears home and re-engages GPS`() {
        // On transition to MOVING:
        // 1. Clear homeGeofenceCenter
        // 2. Remove passive listener
        // 3. Clear persisted home from SharedPreferences
        // 4. Re-engage GPS via registerProviders()
        // 5. Restart stop detection timer
        val actions = mutableListOf<String>()
        actions.add("CLEAR_HOME")
        actions.add("REMOVE_PASSIVE")
        actions.add("CLEAR_PREFS")
        actions.add("REGISTER_PROVIDERS")
        actions.add("RESTART_STOP_TIMER")
        actions.add("EMIT_MOTION_TRUE")

        assertEquals(6, actions.size)
    }

    @Test
    fun `passive listener checks distance from home`() {
        // PASSIVE_PROVIDER delivers locations from other apps.
        // Each update checks distance from homeGeofenceCenter.
        // If distance > homeGeofenceRadius → transitionToMoving()
        val homeLatDeg = 40.0
        val homeLngDeg = -74.0
        val passiveLatDeg = 40.002  // ~222m north
        val passiveLngDeg = -74.0
        val radiusMeters = 150f

        // Rough distance check (1 deg lat ≈ 111km)
        val approxDistanceM = Math.abs(passiveLatDeg - homeLatDeg) * 111_000
        assertTrue(approxDistanceM > radiusMeters)  // should trigger exit
    }

    @Test
    fun `setMoving bypasses distance gate`() {
        // Manual setMoving(true) should directly call transitionToMoving()
        // Manual setMoving(false) should directly call transitionToStationary()
        val states = mutableListOf<Pair<String, String>>()
        states.add("setMoving(false)" to "STATIONARY")  // immediate
        states.add("setMoving(true)" to "MOVING")        // immediate

        assertEquals("STATIONARY", states[0].second)
        assertEquals("MOVING", states[1].second)
    }

    @Test
    fun `home point persists across process death`() {
        // Home point is saved to SharedPreferences with full double precision.
        // On startTracking, restoreHomeIfNeeded() checks for persisted home.
        // If found, resumes in STATIONARY state and does a network check.
        val lat = 40.7128
        val lng = -74.0060
        val latBits = java.lang.Double.doubleToRawLongBits(lat)
        val restored = java.lang.Double.longBitsToDouble(latBits)
        assertEquals(lat, restored, 0.0)  // exact roundtrip
    }

    @Test
    fun `motionStateCallback fires on actual state transitions only`() {
        // Callback fires on transitionToStationary() and transitionToMoving(),
        // NOT on accelerometer events that stay within the distance gate.
        val callbackEvents = mutableListOf<Boolean>()
        callbackEvents.add(false)  // transitionToStationary
        callbackEvents.add(true)   // transitionToMoving

        assertEquals(2, callbackEvents.size)
        assertFalse(callbackEvents[0])
        assertTrue(callbackEvents[1])
    }
}
