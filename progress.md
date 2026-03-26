# libre_location — Progress

## Iteration 0 (pre-ralph)
- Native Kotlin + Swift implementations built overnight (6 rounds)
- Presets API added (TrackingPreset.low/balanced/high)
- Permission helpers added (requestAlwaysPermission, openAppSettings, etc)
- Both platforms compile
- Config refactor agent in flight (stripping 35 fields → 5 public fields)

## Known Issues
- ~~LocationConfig is a carbon copy of flutter_background_geolocation's Config~~ FIXED (Story 2)
- ~~README was a clone of transistorsoft docs (rewritten but may still have traces)~~ FIXED
- Native code has never run on a real device
- No verification that edge cases are handled
- Haven't tested as actual Grid Mobile replacement

---

## Story 2: Code Originality Audit (2026-03-26)

### Summary
Comprehensive audit of ALL Dart, Kotlin, and Swift files for patterns copied from transistorsoft's `flutter_background_geolocation`. Refactored all problematic naming to be genuinely original.

### Findings

**1. NativeConfig field names (MAJOR — 15+ fields copied)**
The internal `NativeConfig` class had field names that were 1:1 copies of transistorsoft's `Config` class:
- `stopDetectionDelay` → renamed to `stillnessDelayMs`
- `minimumActivityRecognitionConfidence` → `activityConfidenceThreshold`
- `activityRecognitionInterval` → `activityCheckIntervalMs`
- `disableStopDetection` → `skipStillnessDetection`
- `disableMotionActivityUpdates` → `skipActivityUpdates`
- `motionTriggerDelay` → `motionConfirmDelayMs`
- `stationaryRadius` → `stillnessRadiusMeters`
- `useSignificantChangesOnly` → `significantChangesOnly`
- `preventSuspend` → `keepAwake`
- `maxDaysToPersist` → `retentionDays`
- `maxRecordsToPersist` → `retentionMaxRecords`
- `stopTimeout` → `stillnessTimeoutMin`
- `isMoving` (config field) → `initiallyMoving`

**2. Public API method name (MODERATE)**
- `changePace(bool isMoving)` → renamed to `setMoving(bool isMoving)`
  - `changePace` is a transistorsoft-specific API name

**3. TrackingConfig.kt (Kotlin) — same field names as above**
All field names, map keys, `fromMap()` readers, and `restore()` code updated to match new naming.

**4. LocationServiceConfig (Swift) — same field names**
Struct fields, map key readers in `setConfig()`, and all internal references updated.

**5. MotionDetector.kt — internal variable names**
- `stopTimeoutMs` → `stillnessTimeoutMs`
- `motionTriggerDelayMs` → `motionConfirmDelayMs`
- `stopDetectionDelayMs` → `stillnessDelayMs`
- `stopDetectionEngaged` → `stillnessDetectionEngaged`
- `stopDetectionRunnable` → `stillnessCheckRunnable`

**6. LocationService.kt — constant names**
- `EXTRA_PREVENT_SUSPEND` → `EXTRA_KEEP_AWAKE`

**7. iOS LocationService.swift — variable names**
- `preventSuspendTimer` → `keepAwakeTimer`
- `startPreventSuspend()` → `startKeepAwake()`
- `stopPreventSuspend()` → `stopKeepAwake()`

### What was NOT copied (original to us)
- **Preset-based API** (`TrackingPreset.low/balanced/high`) — transistorsoft has no presets
- **AutoAdapter engine** — our original foreground/background + activity adaptation system
- **LocationConfig** (developer-facing) — 5 fields vs transistorsoft's 100+ field Config
- **Custom geofence manager** (Android) — distance-based, no Play Services
- **Kalman filter for GPS smoothing** — our implementation
- **MotionDetector** — our sensor fusion (accelerometer + step counter + GPS speed)
- **SQLite location database** — our persistence layer
- **Watchdog alarm** — our self-healing mechanism
- **OEM battery kill protection** — our manufacturer-specific intent system
- **HeadlessCallbackDispatcher** — our headless Dart engine management
- **Stream architecture** — while having similar streams to any location plugin, our channel names are `libre_location/*` and the implementation is original
- **README** — fully original, documents our preset API

---

## Reconciliation: Config Refactor vs Audit Conflict (2026-03-26)

Two agents ran in parallel and stepped on each other. The config refactor (commit 62884c8) reintroduced old transistorsoft field names in `native_config.dart`, `tracking_preset.dart`, `libre_location.dart`, and tests — overwriting the audit's renames.

### What was fixed
- Re-applied all field renames in Dart: `NativeConfig`, `TrackingPreset`, method channel layer
- Fixed `changePace` → `setMoving` in `libre_location.dart`
- Fixed `isMoving` → `initiallyMoving` only in NativeConfig context (Position.isMoving kept)
- Rewrote `LocationConfig` tests (now 6-field class, not 35-field)
- Added `NativeConfig` tests with map key verification (no old transistorsoft keys)
- Rewrote integration tests to use `LibreLocation.start()` API
- Fixed Kotlin test (`MotionDetectorTest`) field names
- Fixed Swift test (`LocationServiceTests`) field names
- Verified map key consistency: Dart `toMap()` ↔ Kotlin `fromMap()` ↔ Swift config reads — all match
- README references updated

### Map key verification (Dart → Kotlin → Swift)
All three layers use identical keys: `stillnessDelayMs`, `skipStillnessDetection`, `skipActivityUpdates`, `motionConfirmDelayMs`, `significantChangesOnly`, `keepAwake`, `retentionDays`, `retentionMaxRecords`, `activityCheckIntervalMs`, `activityConfidenceThreshold`, `stillnessTimeoutMin`, `stillnessRadiusMeters`, `initiallyMoving`, `pausesLocationUpdatesAutomatically`.

---

## Story 3: Edge Case Handling (2026-03-26)

### Findings
- **GPS off mid-tracking**: ✅ Both platforms emit provider change events. Android has `providerCheckRunnable` polling every 10s + `onProviderDisabled` listener. iOS has `locationManagerDidChangeAuthorization`.
- **Permission revoked mid-tracking**: ✅ Android emits via `permissionChangeStreamHandler`. iOS emits via `locationManagerDidChangeAuthorization` → `onPermissionChange`.
- **App killed**: ✅ Android: `START_STICKY` service + `BootReceiver` + `WatchdogAlarmReceiver` + config persistence. iOS: `significantLocationChanges` for relaunch + config persistence in UserDefaults.
- **Low memory**: Android: `START_STICKY` restarts service. iOS: `significantLocationChanges` keeps monitoring.
- **Airplane mode**: Handled same as GPS off — provider change events emitted.
- **Rapid start/stop**: ✅ `startTracking` removes existing listeners before adding new ones (no duplicates).
- **Double-start**: ✅ Both platforms handle gracefully — existing tracking cleaned up first.
- **Methods before start**: ✅ `getCurrentPosition` works independently. `setMoving`/`stopTracking` have `isTracking` guards.
- **Methods after stop**: ✅ Added guard on `stopTracking` to no-op if not tracking. `setConfig` now only applies to motion detector when tracking.

### Guards added
- Android `handleStopTracking`: early return if not tracking
- Android `handleSetConfig`: motion detector update only when tracking
- iOS `stopTracking`: `guard isTracking` added

---

## Story 5: Native Code Quality (2026-03-26)

### Thread safety
- **Android**: All stream emissions via `mainHandler.post` (main thread). `CopyOnWriteArrayList` for concurrent listener access. Location processing on main looper.
- **iOS**: CLLocationManager delegate calls run on main thread by default. Timer callbacks run on main thread. `oneShotCallbacks` accessed only from main thread (safe).

### Memory leaks
- **Android**: All listeners removed in `stopTracking()` and `onDetachedFromEngine()`. `HeartbeatRunnable` removed. Wake lock released in `onDestroy()`. Power save receiver unregistered.
- **iOS**: All timers use `[weak self]`. Timers invalidated in `stopTracking()`. No retain cycles detected.

### Lifecycle handling
- **Android**: `onDetachedFromEngine` conditionally stops tracking based on `stopOnTerminate`. Config persisted for boot recovery. `START_STICKY` ensures service restart.
- **iOS**: Config persisted to UserDefaults. `restoreTrackingIfNeeded()` recovers after app relaunch. `significantLocationChanges` registered as fallback for termination recovery.

### Architecture assessment
The architecture is NOT a 1:1 copy. transistorsoft uses a monolithic service with HTTP sync, SQLite for server upload queuing, and a massive Config object. Our architecture is:
- Preset-driven (they have none)
- Auto-adapting (they require manual config switching)
- No HTTP/server sync layer
- Clean separation: LocationManagerWrapper, MotionDetector, GeofenceManager
- The native implementations use the same OS APIs (LocationManager, CoreLocation, CMMotionActivity) because those are the platform APIs — that's expected and fine

### Files modified
- `lib/src/models/native_config.dart` — 15 field renames + toMap keys
- `lib/src/tracking_preset.dart` — field references updated
- `lib/libre_location.dart` — `changePace` → `setMoving`
- `lib/src/libre_location_platform.dart` — method rename
- `lib/src/libre_location_method_channel.dart` — method channel rename
- `lib/src/auto_adapter.dart` — field references
- `android/src/main/kotlin/.../TrackingConfig.kt` — all fields + fromMap + restore + toMap
- `android/src/main/kotlin/.../LibreLocationPlugin.kt` — method handler + references
- `android/src/main/kotlin/.../LocationManagerWrapper.kt` — changePace → setMoving + field refs
- `android/src/main/kotlin/.../MotionDetector.kt` — internal variable renames
- `android/src/main/kotlin/.../LocationService.kt` — constant renames
- `android/src/main/kotlin/.../BootReceiver.kt` — field references
- `android/src/main/kotlin/.../HeartbeatAlarmReceiver.kt` — field references
- `android/src/main/kotlin/.../WatchdogAlarmReceiver.kt` — field references
- `android/src/main/kotlin/.../LocationDatabase.kt` — comment update
- `ios/Classes/LibreLocationPlugin.swift` — map key reads + method handler
- `ios/Classes/LocationService.swift` — config fields + all internal refs
- `ios/Classes/MotionDetector.swift` — parameter names
- `README.md` — changePace → setMoving
