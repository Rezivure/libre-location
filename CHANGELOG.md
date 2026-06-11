## 0.4.0

iOS battery-profile release: Life360-style stationary/motion power management.

* **Motion-driven GPS re-arming (iOS).** A confident `CMMotionActivity` report (walking/running/cycling/automotive) while stationary now re-arms continuous GPS immediately, instead of waiting for a significant-location-change tick or geofence exit. Raw accelerometer motion still never wakes GPS. Disable with `motionActivityWake: false`.
* **Speed-adaptive accuracy (iOS).** At driving speed (≥10 m/s) `desiredAccuracy` relaxes to `kCLLocationAccuracyNearestTenMeters`; it restores to the preset accuracy below 7 m/s (hysteresis band avoids flapping). Disable with `speedAdaptiveAccuracy: false`.
* **Low-battery SLC-only mode (iOS).** When battery ≤ 20% and not charging, tracking drops to significant-location-changes only regardless of motion state, and restores on charge or recovery past 25%. Configure with `lowBatterySlcOnly` / `lowBatteryThreshold`.
* **`pausesLocationUpdatesAutomatically` is now safe.** `locationManagerDidPauseLocationUpdates` folds the native pause into the plugin's stationary mode (SLC + exit geofence armed), so streaming resumes on movement. Previously a native pause could silently stall updates until the stillness timeout.
* **Upgrade-safe persisted config (iOS).** The persisted tracking config now decodes field-by-field with defaults; previously a plugin upgrade that added config fields caused the whole persisted config to fail decoding, losing tracking restore after termination.
* Android: the new config keys are accepted and ignored (no behavior change); Android already runs its own foreground-service power model.

**Migration notes for consumers:** No breaking API changes. All new behaviors default ON for iOS; pass the new `NativeConfig` flags to opt out.

## 0.3.0

* Removed `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` permissions from the Android manifest. Google Play restricts these to calendar/alarm-clock apps and was rejecting uploads of consuming apps.
* Replaced the `AlarmManager`-based heartbeat with an in-process `Handler.postDelayed` loop inside `LocationService`. Heartbeats now fire while the foreground service is alive (which is the normal case — the ongoing notification + battery-optimization exemption keep it running). Heartbeats may pause during deep Doze, which is a behaviour change from 0.2.x.
* Removed `WatchdogAlarmReceiver` (the 15-minute OEM-kill recovery alarm). OEM-kill resilience now relies solely on the foreground service notification + `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
* Removed `HeartbeatAlarmReceiver`; its headless-callback dispatch logic moved into `LocationService.emitHeartbeat()`.
* Removed `LocationService.ACTION_HEARTBEAT_ALARM` (no longer dispatched).

**Migration notes for consumers:** No API changes. If you were relying on heartbeats firing during deep Doze, you'll see them pause until the next Doze maintenance window or until the user interacts with the device. For most use cases this is acceptable — the foreground service's location updates continue independently of the heartbeat tick.

## 0.2.1

* Bump package version to trigger a fresh tag-based pub.dev publish
* Keep 0.2.0 fixes and release automation improvements intact

## 0.2.0

* Preserve motion state when updating config with `setConfig`
* Enforce a 50m distance filter to reduce noisy updates
* Add a passive listener to improve motion/state handling
* Improve release automation and pub.dev trusted publishing workflow

## 0.1.0

* Initial release
* Background location tracking via AOSP LocationManager (Android) and CoreLocation (iOS)
* Motion detection for adaptive GPS polling
* Geofencing support (ProximityAlert on Android, CLCircularRegion on iOS)
* Three tracking modes: Active, Balanced, Passive
* Zero Google Play Services dependencies
