package io.rezivure.libre_location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.util.Log

/**
 * Detects power save mode changes and emits them via a callback.
 * Registers/unregisters dynamically with the plugin lifecycle.
 */
class PowerSaveReceiver(
    private val context: Context,
    private val onPowerSaveChanged: (Boolean) -> Unit,
) {
    companion object {
        private const val TAG = "LibrePowerSave"
    }

    private var registered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action == PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) {
                val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                val isPowerSave = pm.isPowerSaveMode
                Log.d(TAG, "Power save mode changed: $isPowerSave")
                onPowerSaveChanged(isPowerSave)
            }
        }
    }

    fun register() {
        if (registered) return
        val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        context.registerReceiver(receiver, filter)
        registered = true
    }

    fun unregister() {
        if (!registered) return
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {}
        registered = false
    }
}
