package io.rezivure.libre_location

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import kotlin.math.sqrt

/**
 * Accelerometer-based motion detection.
 *
 * Monitors accelerometer variance over a 30-second window to detect
 * stillness vs movement. Uses TYPE_SIGNIFICANT_MOTION as a wake trigger.
 */
class MotionDetector(private val context: Context) {

    private val sensorManager: SensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    private var accelerometer: Sensor? = null
    private var significantMotionSensor: Sensor? = null
    private var callback: ((Boolean) -> Unit)? = null
    private var isRunning = false
    private var isCurrentlyMoving = true

    // Sliding window for variance calculation
    private val magnitudeHistory = mutableListOf<Double>()
    private val windowSize = 30 // samples (~30s at 1Hz)
    private val stillnessThreshold = 0.15 // variance threshold

    private val accelerometerListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val x = event.values[0].toDouble()
            val y = event.values[1].toDouble()
            val z = event.values[2].toDouble()
            val magnitude = sqrt(x * x + y * y + z * z)

            magnitudeHistory.add(magnitude)
            if (magnitudeHistory.size > windowSize) {
                magnitudeHistory.removeAt(0)
            }

            if (magnitudeHistory.size >= windowSize) {
                val mean = magnitudeHistory.average()
                val variance = magnitudeHistory.map { (it - mean) * (it - mean) }.average()
                val moving = variance > stillnessThreshold

                if (moving != isCurrentlyMoving) {
                    isCurrentlyMoving = moving
                    callback?.invoke(moving)
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private val significantMotionListener = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent?) {
            // Significant motion detected — wake up GPS
            if (!isCurrentlyMoving) {
                isCurrentlyMoving = true
                callback?.invoke(true)
            }
            // Re-register (significant motion is a one-shot trigger)
            significantMotionSensor?.let {
                sensorManager.requestTriggerSensor(this, it)
            }
        }
    }

    fun start(onMotionChanged: (Boolean) -> Unit) {
        if (isRunning) return
        callback = onMotionChanged
        isRunning = true

        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        accelerometer?.let {
            sensorManager.registerListener(
                accelerometerListener, it, SensorManager.SENSOR_DELAY_NORMAL
            )
        }

        significantMotionSensor = sensorManager.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
        significantMotionSensor?.let {
            sensorManager.requestTriggerSensor(significantMotionListener, it)
        }
    }

    fun stop() {
        if (!isRunning) return
        isRunning = false
        sensorManager.unregisterListener(accelerometerListener)
        significantMotionSensor?.let {
            sensorManager.cancelTriggerSensor(significantMotionListener, it)
        }
        magnitudeHistory.clear()
        callback = null
    }
}
