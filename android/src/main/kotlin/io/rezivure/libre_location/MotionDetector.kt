package io.rezivure.libre_location

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlin.math.sqrt

/**
 * Production-grade motion detector combining accelerometer variance analysis
 * with Android's TYPE_SIGNIFICANT_MOTION sensor.
 *
 * Features:
 * - Configurable stillness threshold and window size
 * - Stop timeout: waits [stopTimeoutMs] of stillness before declaring "stopped"
 * - Motion trigger delay: waits [motionTriggerDelayMs] of motion before declaring "moving"
 * - Stop detection delay: waits [stopDetectionDelayMs] before engaging stop detection
 * - Activity type estimation from sensor data (still, walking, running, in_vehicle)
 * - Significant motion sensor as a low-power wake trigger
 */
class MotionDetector(private val context: Context) {

    companion object {
        private const val TAG = "LibreMotionDetector"
        private const val DEFAULT_WINDOW_SIZE = 50
        private const val GRAVITY = 9.81
    }

    private val sensorManager: SensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val handler = Handler(Looper.getMainLooper())

    private var accelerometer: Sensor? = null
    private var significantMotionSensor: Sensor? = null
    private var stepCounterSensor: Sensor? = null

    // Callbacks
    private var motionCallback: ((Boolean) -> Unit)? = null
    private var activityCallback: ((String, Int) -> Unit)? = null  // (type, confidence)

    // State
    private var isRunning = false
    var isMoving: Boolean = true
        private set

    // Configuration
    var stopTimeoutMs: Long = 300_000L        // time of stillness before "stopped"
    var motionTriggerDelayMs: Long = 0L       // time of motion before "moving"
    var stopDetectionDelayMs: Long = 0L       // delay before engaging stop detection
    var stillnessThreshold: Double = 0.3      // accelerometer variance threshold
    var disableStopDetection: Boolean = false

    // Sliding window for variance calculation
    private val magnitudeHistory = mutableListOf<Double>()
    private val windowSize = DEFAULT_WINDOW_SIZE

    // Timing
    private var stillnessStartTime: Long = 0L
    private var motionStartTime: Long = 0L
    private var trackingStartTime: Long = 0L
    private var stopDetectionEngaged: Boolean = false

    // Activity estimation
    private var lastActivityType: String = "unknown"
    private var lastActivityConfidence: Int = 0
    private val recentVariances = mutableListOf<Double>()
    private val varianceWindowSize = 10

    // Step counter for walking/running detection
    private var lastStepCount: Int = -1
    private var stepCountBaseline: Int = -1
    private var recentStepsPerInterval: MutableList<Int> = mutableListOf()
    private var lastStepTime: Long = 0L
    private val stepCheckIntervalMs = 5_000L

    // GPS speed for activity classification (updated externally)
    @Volatile
    var lastGpsSpeedMs: Double = 0.0

    private val accelerometerListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            processAccelerometerEvent(event)
        }
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private val stepCounterListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val totalSteps = event.values[0].toInt()
            if (stepCountBaseline < 0) {
                stepCountBaseline = totalSteps
                lastStepCount = totalSteps
                lastStepTime = System.currentTimeMillis()
                return
            }
            val now = System.currentTimeMillis()
            val elapsed = now - lastStepTime
            if (elapsed >= stepCheckIntervalMs) {
                val stepsDelta = totalSteps - lastStepCount
                recentStepsPerInterval.add(stepsDelta)
                if (recentStepsPerInterval.size > 6) { // keep ~30s of data
                    recentStepsPerInterval.removeAt(0)
                }
                lastStepCount = totalSteps
                lastStepTime = now
            }
        }
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private val significantMotionListener = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent?) {
            Log.d(TAG, "Significant motion trigger fired")
            if (!isMoving) {
                handleMotionDetected()
            }
            // Re-register (one-shot trigger)
            significantMotionSensor?.let {
                sensorManager.requestTriggerSensor(this, it)
            }
        }
    }

    // Periodic stop detection check
    private val stopDetectionRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return
            checkStopDetection()
            handler.postDelayed(this, 5_000L)
        }
    }

    /**
     * Starts motion detection with the given callbacks.
     *
     * @param onMotionChanged Called when motion state changes (true=moving, false=stationary)
     * @param onActivityChanged Called when estimated activity changes (type, confidence)
     */
    fun start(
        onMotionChanged: (Boolean) -> Unit,
        onActivityChanged: ((String, Int) -> Unit)? = null
    ) {
        if (isRunning) return
        motionCallback = onMotionChanged
        activityCallback = onActivityChanged
        isRunning = true
        isMoving = true
        trackingStartTime = System.currentTimeMillis()
        stopDetectionEngaged = stopDetectionDelayMs == 0L

        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        accelerometer?.let {
            sensorManager.registerListener(
                accelerometerListener, it, SensorManager.SENSOR_DELAY_NORMAL
            )
        } ?: Log.w(TAG, "No accelerometer available")

        significantMotionSensor = sensorManager.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
        significantMotionSensor?.let {
            sensorManager.requestTriggerSensor(significantMotionListener, it)
        }

        // Step counter for walking/running detection (no Google Play Services)
        stepCounterSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        stepCounterSensor?.let {
            sensorManager.registerListener(stepCounterListener, it, SensorManager.SENSOR_DELAY_NORMAL)
            Log.d(TAG, "Step counter sensor registered")
        } ?: Log.d(TAG, "No step counter sensor available")

        handler.postDelayed(stopDetectionRunnable, 5_000L)
        Log.d(TAG, "Motion detector started (stopTimeout=${stopTimeoutMs}ms, threshold=$stillnessThreshold)")
    }

    /**
     * Convenience overload matching the original skeleton API.
     */
    fun start(onMotionChanged: (Boolean) -> Unit) {
        start(onMotionChanged, null)
    }

    fun stop() {
        if (!isRunning) return
        isRunning = false
        sensorManager.unregisterListener(accelerometerListener)
        sensorManager.unregisterListener(stepCounterListener)
        stepCountBaseline = -1
        lastStepCount = -1
        recentStepsPerInterval.clear()
        significantMotionSensor?.let {
            try { sensorManager.cancelTriggerSensor(significantMotionListener, it) }
            catch (_: Exception) {}
        }
        handler.removeCallbacks(stopDetectionRunnable)
        magnitudeHistory.clear()
        recentVariances.clear()
        motionCallback = null
        activityCallback = null
        Log.d(TAG, "Motion detector stopped")
    }

    /**
     * Updates configuration parameters at runtime.
     */
    fun updateConfig(config: TrackingConfig) {
        stopTimeoutMs = config.stopTimeout
        motionTriggerDelayMs = config.motionTriggerDelay
        stopDetectionDelayMs = config.stopDetectionDelay
        disableStopDetection = config.disableStopDetection
        // Map stationaryRadius to stillness threshold heuristically
        stillnessThreshold = when {
            config.stationaryRadius <= 10f -> 0.15
            config.stationaryRadius <= 25f -> 0.3
            config.stationaryRadius <= 50f -> 0.5
            else -> 0.8
        }
    }

    private fun processAccelerometerEvent(event: SensorEvent) {
        val x = event.values[0].toDouble()
        val y = event.values[1].toDouble()
        val z = event.values[2].toDouble()
        val magnitude = sqrt(x * x + y * y + z * z)

        magnitudeHistory.add(magnitude)
        if (magnitudeHistory.size > windowSize) {
            magnitudeHistory.removeAt(0)
        }

        if (magnitudeHistory.size < windowSize) return

        val mean = magnitudeHistory.average()
        val variance = magnitudeHistory.map { (it - mean) * (it - mean) }.average()

        // Track variance for activity estimation
        recentVariances.add(variance)
        if (recentVariances.size > varianceWindowSize) {
            recentVariances.removeAt(0)
        }

        // Engage stop detection after delay
        if (!stopDetectionEngaged && stopDetectionDelayMs > 0) {
            if (System.currentTimeMillis() - trackingStartTime >= stopDetectionDelayMs) {
                stopDetectionEngaged = true
            }
        }

        val currentlyStill = variance < stillnessThreshold

        if (currentlyStill) {
            if (stillnessStartTime == 0L) {
                stillnessStartTime = System.currentTimeMillis()
            }
            motionStartTime = 0L
        } else {
            if (motionStartTime == 0L) {
                motionStartTime = System.currentTimeMillis()
            }
            stillnessStartTime = 0L

            // Check motion trigger delay
            if (!isMoving && motionTriggerDelayMs > 0) {
                if (System.currentTimeMillis() - motionStartTime >= motionTriggerDelayMs) {
                    handleMotionDetected()
                }
            } else if (!isMoving) {
                handleMotionDetected()
            }
        }

        // Estimate activity type periodically
        estimateActivity(variance)
    }

    private fun checkStopDetection() {
        if (disableStopDetection || !stopDetectionEngaged || !isMoving) return

        if (stillnessStartTime > 0) {
            val stillDuration = System.currentTimeMillis() - stillnessStartTime
            if (stillDuration >= stopTimeoutMs) {
                handleStillnessDetected()
            }
        }
    }

    private fun handleMotionDetected() {
        if (isMoving) return
        isMoving = true
        stillnessStartTime = 0L
        Log.d(TAG, "Motion state changed: MOVING")
        motionCallback?.invoke(true)
    }

    private fun handleStillnessDetected() {
        if (!isMoving) return
        isMoving = false
        motionStartTime = 0L
        Log.d(TAG, "Motion state changed: STATIONARY")
        motionCallback?.invoke(false)
    }

    /**
     * Estimates activity by combining three signals:
     * 1. Accelerometer variance (vibration/shake patterns)
     * 2. GPS speed (m/s thresholds: <2 still, 2-7 walk, 7-15 run/cycle, >15 vehicle)
     * 3. Step counter (steps per interval distinguishes walking from running)
     *
     * No Google Play Services — pure sensor APIs only.
     */
    private fun estimateActivity(currentVariance: Double) {
        if (recentVariances.size < varianceWindowSize) return

        val avgVariance = recentVariances.average()
        val speed = lastGpsSpeedMs
        val stepsPerInterval = if (recentStepsPerInterval.isNotEmpty()) recentStepsPerInterval.average() else 0.0

        // Speed-based classification (primary when GPS speed is available and reliable)
        val speedType: String?
        val speedConfidence: Int
        when {
            speed < 0.5 -> { speedType = "still"; speedConfidence = 85 }
            speed < 2.0 -> { speedType = "still"; speedConfidence = 70 }
            speed < 7.0 -> { speedType = "walking"; speedConfidence = 80 }
            speed < 15.0 -> { speedType = "running"; speedConfidence = 75 }  // or cycling
            else -> { speedType = "in_vehicle"; speedConfidence = 85 }
        }

        // Step counter refinement
        // stepsPerInterval is steps per ~5s window
        // Walking: ~8-15 steps/5s (1.6-3 steps/s)
        // Running: ~15-25 steps/5s (3-5 steps/s)
        val stepType: String?
        val stepConfidence: Int
        when {
            stepsPerInterval < 1.0 -> { stepType = "still"; stepConfidence = 80 }
            stepsPerInterval < 15.0 -> { stepType = "walking"; stepConfidence = 85 }
            stepsPerInterval < 30.0 -> { stepType = "running"; stepConfidence = 80 }
            else -> { stepType = null; stepConfidence = 0 } // sensor noise or very fast
        }

        // Accelerometer variance classification
        val accelType: String
        val accelConfidence: Int
        when {
            avgVariance < stillnessThreshold -> { accelType = "still"; accelConfidence = 90 }
            avgVariance < 1.5 -> { accelType = "walking"; accelConfidence = 70 }
            avgVariance < 5.0 -> { accelType = "walking"; accelConfidence = 80 }
            avgVariance < 10.0 -> { accelType = "running"; accelConfidence = 70 }
            avgVariance < 20.0 -> { accelType = "on_bicycle"; accelConfidence = 55 }
            else -> { accelType = "in_vehicle"; accelConfidence = 50 }
        }

        // Combine signals with weighted voting
        val votes = mutableMapOf<String, Int>()

        // Speed has highest weight when available (GPS is most reliable for vehicle detection)
        if (speed > 0.5 && speedType != null) {
            votes[speedType] = (votes[speedType] ?: 0) + speedConfidence * 3
        }

        // Step counter is very reliable for walking vs still vs running
        if (stepType != null && stepConfidence > 0 && stepCounterSensor != null) {
            votes[stepType] = (votes[stepType] ?: 0) + stepConfidence * 2
        }

        // Accelerometer is always available
        votes[accelType] = (votes[accelType] ?: 0) + accelConfidence

        // Distinguish cycling from running using speed (cycling is typically 10-30 km/h)
        if (speed in 7.0..15.0 && avgVariance < 5.0) {
            // Low variance + medium speed = cycling (smooth motion)
            votes["on_bicycle"] = (votes["on_bicycle"] ?: 0) + 100
        }

        // Pick the winner
        val (type, _) = votes.maxByOrNull { it.value } ?: ("unknown" to 0)
        val totalWeight = votes.values.sum().toDouble()
        val winnerWeight = votes[type] ?: 0
        val confidence = if (totalWeight > 0) ((winnerWeight / totalWeight) * 100).toInt().coerceIn(0, 100) else 50

        if (type != lastActivityType) {
            lastActivityType = type
            lastActivityConfidence = confidence
            activityCallback?.invoke(type, confidence)
        }
    }

    /**
     * Returns the current estimated activity as a map suitable for method channel.
     */
    fun getCurrentActivity(): Map<String, Any> = mapOf(
        "activity" to lastActivityType,
        "confidence" to lastActivityConfidence,
        "isMoving" to isMoving,
    )
}
