# libre_location

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Pub Version](https://img.shields.io/pub/v/libre_location)](https://pub.dev/packages/libre_location)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-green.svg)](https://flutter.dev)

**Background location tracking for Flutter — without Google Play Services.**

A production-grade Flutter plugin that uses pure **AOSP LocationManager** on Android and **CoreLocation** on iOS. Zero proprietary dependencies. Built for privacy-focused apps, [GrapheneOS](https://grapheneos.org/), [CalyxOS](https://calyxos.org/), and degoogled devices.

## Why libre_location?

| Feature | libre_location | geolocator | background_geolocation | background_location |
|---|:---:|:---:|:---:|:---:|
| **No Play Services** | ✅ | ❌ | ❌ | ❌ |
| Background tracking | ✅ | ⚠️ | ✅ | ✅ |
| Motion detection | ✅ | ❌ | ✅ | ❌ |
| Geofencing | ✅ | ❌ | ✅ | ❌ |
| Activity recognition | ✅ | ❌ | ✅ | ❌ |
| Auto-adaptation | ✅ | ❌ | ❌ | ❌ |
| Headless mode | ✅ | ❌ | ✅ | ❌ |
| OEM battery protection | ✅ | ❌ | ✅ | ❌ |
| Open source | ✅ Apache 2.0 | ✅ MIT | ⚠️ Paid license | ✅ MIT |
| Works on GrapheneOS | ✅ | ❌ | ❌ | ❌ |

## Quick Start

```dart
import 'package:libre_location/libre_location.dart';

// 1. Request permission
final permission = await LibreLocation.requestPermission();

// 2. Start tracking — that's it
await LibreLocation.start(preset: TrackingPreset.balanced);

// 3. Listen for updates
LibreLocation.onLocation.listen((position) {
  print('${position.latitude}, ${position.longitude}');
});

// 4. Stop when done
await LibreLocation.stop();
```

No magic numbers. No GPS tuning. The plugin auto-adapts to foreground/background, detected activity, and stationary state.

## Tracking Presets

Presets are the recommended API. Pick one and the plugin handles everything else.

| Preset | Battery | Accuracy | Update Interval | Distance Filter | Best For |
|---|---|---|---|---|---|
| `TrackingPreset.low` | ~1%/day | ~500m | 5 min | 500m | Social presence, "roughly where I am" |
| `TrackingPreset.balanced` | ~2-4%/day | ~50m | 1 min | 50m | Most apps (default) |
| `TrackingPreset.high` | ~5-8%/day | ~10m | 15 sec | 10m | Navigation, fitness, delivery |

### What presets auto-configure

Each preset sets 15+ parameters for you, including:

- **GPS accuracy & polling interval** — tuned per tier
- **Motion detection** — stops GPS when stationary, resumes on movement
- **Activity-based adaptation** — tightens tracking when driving, relaxes when still
- **Foreground/background switching** — more aggressive in foreground, battery-friendly in background
- **Heartbeat interval** — periodic pings even when stationary (30 min low, 20 min balanced, 5 min high)
- **Stationarity detection** — radius and timeout per tier

### Switch presets at runtime

```dart
// User enables battery saver — one line
await LibreLocation.setPreset(TrackingPreset.low);

// User starts navigation — one line
await LibreLocation.setPreset(TrackingPreset.high);
```

No stop/start needed. The plugin reconfigures on the fly.

### Auto-Adaptation

When using a preset, the plugin automatically adapts tracking based on:

- **App lifecycle** — tighter tracking in foreground, relaxed in background
- **Detected activity** — driving gets wider distance filter, walking gets tighter GPS
- **Stationary state** — GPS pauses when you stop moving, heartbeat keeps the session alive

You don't manage any of this. The `AutoAdapter` engine handles lifecycle observation and activity stream internally.

## Installation

```yaml
dependencies:
  libre_location: ^1.0.0
```

## Permissions

libre_location provides helpers for the full permission lifecycle:

```dart
// Check current status
final permission = await LibreLocation.checkPermission();
// → LocationPermission.denied | deniedForever | whileInUse | always

// Request foreground permission
final result = await LibreLocation.requestPermission();

// Upgrade to "Always" (background) permission
// iOS: two-step WhenInUse → Always flow
// Android 10+: separate ACCESS_BACKGROUND_LOCATION request
// Android 11+: may need to send user to Settings
final always = await LibreLocation.requestAlwaysPermission();

// Check if GPS is even enabled on the device
final gpsOn = await LibreLocation.isLocationServiceEnabled();

// Android: should you show a rationale before requesting?
final showRationale = await LibreLocation.shouldShowRequestRationale();

// Open system settings when permissions are permanently denied
await LibreLocation.openAppSettings();       // App permission page
await LibreLocation.openLocationSettings();  // Device GPS settings

// React to permission changes
LibreLocation.onPermissionChange.listen((permission) {
  print('Permission changed to: $permission');
});
```

### Full permission flow example

```dart
Future<bool> ensurePermissions() async {
  // Check if location services are on
  if (!await LibreLocation.isLocationServiceEnabled()) {
    await LibreLocation.openLocationSettings();
    return false;
  }

  var permission = await LibreLocation.checkPermission();

  if (permission == LocationPermission.deniedForever) {
    await LibreLocation.openAppSettings();
    return false;
  }

  if (permission == LocationPermission.denied) {
    permission = await LibreLocation.requestPermission();
    if (permission == LocationPermission.denied) return false;
  }

  if (permission == LocationPermission.whileInUse) {
    permission = await LibreLocation.requestAlwaysPermission();
  }

  return permission == LocationPermission.always;
}
```

## Streams

```dart
// Location updates (primary stream)
LibreLocation.onLocation.listen((Position pos) { ... });

// Motion state changes (moving ↔ stationary)
LibreLocation.onMotionChange.listen((Position pos) {
  print(pos.isMoving ? 'Moving' : 'Stopped');
});

// Activity detection (still/walking/running/cycling/vehicle)
LibreLocation.onActivityChange.listen((ActivityEvent event) {
  print('${event.activity} (${event.confidence}%)');
});

// Heartbeat pings (periodic, even when stationary)
LibreLocation.onHeartbeat.listen((HeartbeatEvent event) { ... });

// GPS/provider state changes
LibreLocation.onProviderChange.listen((ProviderEvent event) { ... });

// Power save mode changes
LibreLocation.onPowerSaveChange.listen((bool enabled) { ... });
```

## One-Shot Position

```dart
final pos = await LibreLocation.getCurrentPosition(
  accuracy: Accuracy.high,
  samples: 3,       // Average 3 readings for better accuracy
  timeout: 30,      // Timeout in seconds
  maximumAge: 0,    // Don't accept cached positions
  persist: true,    // Save to local database
);
```

## Geofencing

```dart
await LibreLocation.addGeofence(Geofence(
  id: 'home',
  latitude: 37.4219999,
  longitude: -122.0840575,
  radiusMeters: 100,
  triggers: {GeofenceTransition.enter, GeofenceTransition.exit, GeofenceTransition.dwell},
  dwellDuration: Duration(minutes: 5),
));

LibreLocation.geofenceStream.listen((GeofenceEvent event) {
  print('Geofence ${event.geofence.id}: ${event.transition.name}');
});

await LibreLocation.removeGeofence('home');
final geofences = await LibreLocation.getGeofences();
```

## Configuration

`LocationConfig` is intentionally minimal. All GPS tuning (distance filters, accuracy levels, activity recognition, etc.) is handled internally by presets. You only configure what's genuinely app-specific:

```dart
await LibreLocation.start(
  preset: TrackingPreset.balanced,
  config: LocationConfig(
    notification: NotificationConfig(
      title: 'Tracking Active',
      text: 'Running in background',
    ),
    stopOnTerminate: false,
    startOnBoot: true,
    enableHeadless: true,
    debug: true,
  ),
);
```

### `start()` parameters

| Parameter | Default | Description |
|---|---|---|
| `preset` | `TrackingPreset.balanced` | Tracking tier |
| `config` | `LocationConfig()` | App-specific settings (see below) |

### `LocationConfig` fields

| Field | Default | Description |
|---|---|---|
| `notification` | `null` | Android foreground service notification |
| `backgroundPermissionRationale` | `null` | Permission dialog text |
| `stopOnTerminate` | `false` | Stop tracking when app is killed |
| `startOnBoot` | `true` | Resume tracking after device reboot |
| `enableHeadless` | `true` | Dart callbacks after app termination (Android) |
| `debug` | `false` | Enable debug logging |

That's it. No `distanceFilter`, no `stillnessRadiusMeters`, no `activityCheckIntervalMs`. The preset handles all of that.

## Platform Setup

### Android

#### AndroidManifest.xml

The plugin's manifest includes all required permissions automatically. You may want to be explicit:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
</manifest>
```

#### Minimum SDK

```groovy
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

### iOS

#### Info.plist

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs your location to provide tracking services.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs your location to show your position.</string>
<key>NSMotionUsageDescription</key>
<string>This app uses motion data to detect when you're moving.</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>io.rezivure.libre_location.heartbeat</string>
</array>
```

#### Podfile

```ruby
platform :ios, '13.0'
```

## Android-Specific APIs

### Battery Optimization

Critical for production on Samsung, Xiaomi, Huawei, etc. that aggressively kill background apps.

```dart
final isOptimized = await LibreLocation.checkBatteryOptimization();
if (isOptimized) {
  await LibreLocation.requestBatteryOptimizationExemption();
}

// Check manufacturer-specific auto-start
final autoStart = await LibreLocation.isAutoStartEnabled();

// Open manufacturer power settings
await LibreLocation.openPowerManagerSettings();
```

### Headless Mode

Receive location updates after app termination:

```dart
@pragma('vm:entry-point')
void headlessDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
}

@pragma('vm:entry-point')
void onHeadlessLocation(Map<String, dynamic> data) {
  print('Headless location: $data');
}

await LibreLocation.registerHeadlessDispatcher(
  headlessDispatcher,
  onHeadlessLocation,
);
```

### Notifications

```dart
final hasPermission = await LibreLocation.checkNotificationPermission();
if (!hasPermission) {
  await LibreLocation.requestNotificationPermission();
}
```

## iOS-Specific APIs

```dart
// Request temporary full accuracy (iOS 14+ reduced accuracy mode)
await LibreLocation.requestTemporaryFullAccuracy(purposeKey: 'navigation');
```

## Utilities

```dart
// Force motion state
await LibreLocation.setMoving(true); // Force "moving" state

// Check tracking state
final tracking = await LibreLocation.isTracking;

// Get current preset (null if using custom config)
final preset = LibreLocation.currentPreset;

// Retrieve debug logs
final logs = await LibreLocation.getLog();
```

## Migration from flutter_background_geolocation

### Before: ~370 lines of manual config

```dart
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

// Manual lifecycle management
late final AppLifecycleListener _lifecycleListener;
bool _isInForeground = true;

// 4 different config contexts with 15+ magic numbers each
void _updateTrackingConfig() {
  if (_isInForeground) {
    bg.BackgroundGeolocation.setConfig(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      distanceFilter: 10, stopTimeout: 3, stationaryRadius: 25,
      skipActivityUpdates: false, heartbeatInterval: 300,
      // ... 10 more params
    ));
  } else if (_batterySaver) {
    // another 15+ params...
  } else {
    // another 15+ params...
  }
}

// Manual activity-based switching
bg.BackgroundGeolocation.onActivityChange((event) {
  switch (event.activity) {
    case 'in_vehicle': // tweak config
    case 'still': // tweak config
    // ...
  }
});
```

### After: ~100 lines with presets

```dart
import 'package:libre_location/libre_location.dart';

// Start with one line — auto-adapts to everything
await LibreLocation.start(
  preset: TrackingPreset.balanced,
  config: const LocationConfig(
    notification: NotificationConfig(
      title: 'Location Sharing',
      text: 'Active',
    ),
  ),
);

// Listen
LibreLocation.onLocation.listen((pos) { ... });

// Battery saver? One line.
await LibreLocation.setPreset(TrackingPreset.low);
```

**What you delete:**
- ✗ `AppLifecycleListener` + foreground/background tracking
- ✗ `onActivityChange` handler with `switch` statements
- ✗ Manual throttling logic
- ✗ 60+ lines of `Config()` with hardcoded values
- ✗ 4 different config contexts

**Result:** 73% code reduction, zero config params to manage.

See [`example/migration/location_manager_libre.dart`](example/migration/location_manager_libre.dart) for a complete before/after.

## Troubleshooting

### "Location stops after X minutes"

Almost always **battery optimization**. Android OEMs aggressively kill background apps.

```dart
final optimized = await LibreLocation.checkBatteryOptimization();
if (optimized) {
  await LibreLocation.requestBatteryOptimizationExemption();
}
await LibreLocation.openPowerManagerSettings();
```

### "No updates when app is killed"

Enable headless mode and configure persistence:

```dart
await LibreLocation.registerHeadlessDispatcher(dispatcher, callback);
await LibreLocation.start(
  preset: TrackingPreset.balanced,
  config: const LocationConfig(
    stopOnTerminate: false,
    startOnBoot: true,
    enableHeadless: true,
  ),
);
```

### "Inaccurate on Android"

Without Play Services, Android uses raw AOSP providers (GPS ~3-5m, network ~20-100m). Tips:
- Use `TrackingPreset.high` or `Accuracy.high`
- Use `samples: 3` in `getCurrentPosition()` for averaged readings
- First fix after boot may take 30-60 seconds outdoors

### OEM Battery Kill Guide

| Manufacturer | Setting Location | Key Action |
|---|---|---|
| **Samsung** | Battery → Background usage limits | Add to "Never sleeping apps" |
| **Xiaomi/MIUI** | Security → Autostart / Battery saver | Enable autostart + No restrictions |
| **Huawei/EMUI** | Battery → App launch | Disable "Manage automatically" |
| **OnePlus** | Battery → Battery optimization | Set to "Don't optimize" |
| **Oppo/ColorOS** | Battery → More settings | Disable battery optimization |
| **Vivo/FuntouchOS** | Battery → Background power consumption | Allow background |
| **Stock Android** | Battery → Battery optimization | Set to "Not optimized" |

For comprehensive guidance, see [dontkillmyapp.com](https://dontkillmyapp.com).

## Architecture

### Android
- **LocationManagerWrapper**: Core AOSP LocationManager integration with multi-provider support
- **LocationService**: Foreground service with START_STICKY, wake lock, AlarmManager heartbeat
- **MotionDetector**: Accelerometer variance + step counter + GPS speed + significant motion sensor
- **GeofenceManager**: Custom distance-based geofence checking on every location update
- **HeadlessCallbackDispatcher**: FlutterEngine in headless mode for post-termination callbacks
- **BootReceiver**: Restarts tracking after device boot
- **LocationDatabase**: SQLite buffer for offline location persistence

### iOS
- **LocationService**: CLLocationManager with background location updates, significant location monitoring
- **MotionDetectorService**: CMMotionActivityManager for motion/activity detection
- **GeofenceManagerService**: CLCircularRegion-based geofencing with dwell support
- **BGTaskScheduler**: Background heartbeat via BGAppRefreshTask (iOS 13+)

## Supported Platforms

| Platform | Minimum Version | Notes |
|---|---|---|
| **Android** | API 21 (5.0) | Pure AOSP LocationManager, no Play Services |
| **iOS** | 13.0 | CoreLocation + CoreMotion, BGTaskScheduler for heartbeat |

## Known Limitations

- **Android first fix**: Without Play Services, initial GPS fix can take 30-60 seconds outdoors
- **Android network accuracy**: Cell/Wi-Fi positioning is ~20-100m without Google location fusion
- **iOS background limits**: iOS may throttle background updates; use heartbeat for critical apps
- **iOS geofence limit**: Hard limit of 20 monitored regions (LRU eviction applied automatically)
- **Activity recognition**: Uses accelerometer + step counter + GPS speed heuristics (not Play Services Activity Recognition)
- **No web support**: Native mobile platforms only

## Contributing

1. Fork and create a feature branch
2. Write tests for new functionality
3. Test on real devices — location plugins behave differently on emulators
4. Open a PR with a clear description

```bash
git clone https://github.com/Rezivure/libre-location.git
cd libre-location
flutter test
cd example && flutter run
```

When filing issues, include: device model, OS version, Flutter version, plugin version, steps to reproduce, and relevant logs (`adb logcat | grep LibreLocation`).

## License

Apache License 2.0 — free for commercial use, no restrictions.
