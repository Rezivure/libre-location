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
| Headless mode | ✅ | ❌ | ✅ | ❌ |
| OEM battery protection | ✅ | ❌ | ✅ | ❌ |
| Open source | ✅ Apache 2.0 | ✅ MIT | ⚠️ Paid license | ✅ MIT |
| Works on GrapheneOS | ✅ | ❌ | ❌ | ❌ |
| Pure platform APIs | ✅ | ❌ | ❌ | ❌ |

## Features

- 📍 **Background location tracking** with configurable accuracy, intervals, and distance filters
- 🏃 **Motion detection** — accelerometer + step counter based, pauses GPS when stationary
- 🎯 **Geofencing** — enter/exit/dwell events with configurable radius and duration
- 🔋 **Battery info** — level and charging state included in every position update
- 💓 **Heartbeat** — periodic location emission even when stationary
- 📱 **Activity recognition** — still/walking/running/cycling/vehicle (no Play Services)
- 🔄 **Boot persistence** — auto-restart tracking after device reboot
- 💀 **Headless mode** — Dart callbacks even after app termination (Android)
- 🛡️ **OEM battery kill protection** — Samsung, Xiaomi, Huawei, OnePlus, Oppo, Vivo guidance
- 📊 **Local persistence** — SQLite buffer for offline location storage
- ⚙️ **Dynamic config** — change settings at runtime without restart

## Quick Start

```dart
import 'package:libre_location/libre_location.dart';

// Check permission
final permission = await LibreLocation.checkPermission();
if (permission == LocationPermission.denied) {
  await LibreLocation.requestPermission();
}

// Start tracking
await LibreLocation.startTracking(LocationConfig(
  accuracy: Accuracy.high,
  mode: TrackingMode.balanced,
  distanceFilter: 10.0,
  intervalMs: 60000,
  notificationTitle: 'Tracking Active',
  notificationBody: 'Your location is being tracked',
));

// Listen to positions
LibreLocation.positionStream.listen((position) {
  print('${position.latitude}, ${position.longitude}');
  print('Battery: ${position.battery?.level}%');
  print('Moving: ${position.isMoving}');
});

// Stop tracking
await LibreLocation.stopTracking();
```

## Installation

```yaml
dependencies:
  libre_location: ^1.0.0
```

## Platform Setup

### Android

#### AndroidManifest.xml

The plugin's manifest includes all required permissions automatically. However, your app's `AndroidManifest.xml` should include:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- These are included by the plugin automatically, but you may want to be explicit -->
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

Ensure your `android/app/build.gradle` has:

```groovy
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

### iOS

#### Info.plist

Add the following keys to `ios/Runner/Info.plist`:

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
<!-- Required for BGTaskScheduler heartbeat -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>io.rezivure.libre_location.heartbeat</string>
</array>
```

#### Podfile

Ensure your `ios/Podfile` has:

```ruby
platform :ios, '13.0'
```

## API Reference

### Core Tracking

#### `LibreLocation.startTracking(LocationConfig config)`

Starts background location tracking. On Android, this launches a foreground service with a persistent notification.

```dart
await LibreLocation.startTracking(LocationConfig(
  accuracy: Accuracy.high,           // high, balanced, low, passive
  mode: TrackingMode.balanced,       // active, balanced, passive
  intervalMs: 60000,                 // Minimum update interval
  distanceFilter: 10.0,             // Minimum distance change (meters)
  enableMotionDetection: true,       // Pause GPS when stationary
  notificationTitle: 'Tracking',
  notificationBody: 'Running in background',
  stopOnTerminate: false,            // Keep tracking after app close
  startOnBoot: true,                 // Restart after device reboot
  enableHeadless: true,              // Enable headless Dart callbacks
  heartbeatInterval: 900,            // Heartbeat every 15 min (seconds)
  stopTimeout: 5,                    // Minutes of stillness before "stopped"
  stationaryRadius: 25.0,           // Meters for stationary detection
  persistLocations: true,           // Save to local SQLite
  preventSuspend: false,            // Keep CPU awake (battery intensive!)
));
```

#### `LibreLocation.stopTracking()`

Stops all location tracking and shuts down the foreground service.

```dart
await LibreLocation.stopTracking();
```

#### `LibreLocation.getCurrentPosition(...)`

Gets a one-shot position reading with configurable accuracy and multi-sample averaging.

```dart
final position = await LibreLocation.getCurrentPosition(
  accuracy: Accuracy.high,
  samples: 3,         // Average 3 readings for better accuracy
  timeout: 30,        // Timeout in seconds
  maximumAge: 5000,   // Accept cached position up to 5s old (ms)
  persist: true,      // Save to local database
);
```

#### `LibreLocation.setConfig(LocationConfig config)`

Dynamically update configuration without stopping/restarting tracking.

```dart
await LibreLocation.setConfig(LocationConfig(
  accuracy: Accuracy.low,
  intervalMs: 300000,
));
```

#### `LibreLocation.isTracking`

```dart
final tracking = await LibreLocation.isTracking;
```

### Streams

#### Position Stream

```dart
LibreLocation.positionStream.listen((Position position) {
  print('Lat: ${position.latitude}');
  print('Lng: ${position.longitude}');
  print('Accuracy: ${position.accuracy}m');
  print('Speed: ${position.speed} m/s');
  print('Provider: ${position.provider}');
  print('Battery: ${position.battery?.level}');
  print('Charging: ${position.battery?.isCharging}');
});
```

#### Motion Change Stream

Emits when the device transitions between moving and stationary states.

```dart
LibreLocation.motionChangeStream.listen((Position position) {
  if (position.isMoving) {
    print('Started moving at ${position.latitude}, ${position.longitude}');
  } else {
    print('Stopped at ${position.latitude}, ${position.longitude}');
  }
});
```

#### Activity Change Stream

```dart
LibreLocation.activityChangeStream.listen((ActivityEvent event) {
  print('Activity: ${event.type}');        // still, walking, running, on_bicycle, in_vehicle
  print('Confidence: ${event.confidence}'); // 0-100
});
```

#### Provider Change Stream

```dart
LibreLocation.providerChangeStream.listen((ProviderEvent event) {
  print('GPS enabled: ${event.gps}');
  print('Network enabled: ${event.network}');
});
```

#### Heartbeat Stream

Periodic location emission even when stationary. Configure `heartbeatInterval` in `LocationConfig`.

```dart
LibreLocation.heartbeatStream.listen((HeartbeatEvent event) {
  print('Heartbeat position: ${event.position}');
});
```

### Geofencing

```dart
// Add a geofence
await LibreLocation.addGeofence(Geofence(
  id: 'home',
  latitude: 37.4219999,
  longitude: -122.0840575,
  radiusMeters: 100,
  triggers: {GeofenceTransition.enter, GeofenceTransition.exit, GeofenceTransition.dwell},
  dwellDuration: Duration(minutes: 5),
));

// Listen to geofence events
LibreLocation.geofenceStream.listen((GeofenceEvent event) {
  print('Geofence ${event.geofence.id}: ${event.transition.name}');
});

// Remove a geofence
await LibreLocation.removeGeofence('home');

// Get all active geofences
final geofences = await LibreLocation.getGeofences();
```

### Permissions

```dart
final permission = await LibreLocation.checkPermission();
// LocationPermission.denied | deniedForever | whileInUse | always

if (permission != LocationPermission.always) {
  final result = await LibreLocation.requestPermission();
  // On iOS: requests WhenInUse first, then escalates to Always
  // On Android 11+: requests foreground first, then background separately
}
```

### Battery Optimization (Android)

Critical for production apps on Samsung, Xiaomi, Huawei, and other OEM devices that aggressively kill background apps.

```dart
// Check if the app is battery-optimized (bad for background tracking)
final isOptimized = await LibreLocation.checkBatteryOptimization();
if (isOptimized) {
  // Request exemption — opens system dialog
  await LibreLocation.requestBatteryOptimizationExemption();
}

// Check manufacturer-specific auto-start settings
final autoStart = await LibreLocation.isAutoStartEnabled();
print('Manufacturer: ${autoStart['manufacturer']}');
print('Has auto-start setting: ${autoStart['hasAutoStartSetting']}');

// Open manufacturer power settings (Samsung battery, Xiaomi autostart, etc.)
await LibreLocation.openPowerManagerSettings();
```

### Headless Mode (Android)

Receive location updates even after the app UI is terminated.

```dart
// Both must be top-level or static functions
@pragma('vm:entry-point')
void headlessDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  // Set up the headless isolate
}

@pragma('vm:entry-point')
void onHeadlessLocation(Map<String, dynamic> data) {
  // Process location in background
  print('Headless location: $data');
}

// Register during app initialization
await LibreLocation.registerHeadlessDispatcher(
  headlessDispatcher,
  onHeadlessLocation,
);
```

## Migration from flutter_background_geolocation

### Before (flutter_background_geolocation)

```dart
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

// Configure
bg.BackgroundGeolocation.ready(bg.Config(
  desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
  distanceFilter: 10.0,
  stopOnTerminate: false,
  startOnBoot: true,
  notification: bg.Notification(
    title: 'Tracking',
    text: 'Running in background',
  ),
)).then((bg.State state) {
  if (!state.enabled) {
    bg.BackgroundGeolocation.start();
  }
});

// Listen
bg.BackgroundGeolocation.onLocation((bg.Location location) {
  print('[location] ${location.coords.latitude}, ${location.coords.longitude}');
});

bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
  print('[motionChange] isMoving: ${location.isMoving}');
});

// Geofence
bg.BackgroundGeolocation.addGeofence(bg.Geofence(
  identifier: 'home',
  radius: 100,
  latitude: 37.42,
  longitude: -122.08,
  notifyOnEntry: true,
  notifyOnExit: true,
));
```

### After (libre_location)

```dart
import 'package:libre_location/libre_location.dart';

// Configure and start (combined)
await LibreLocation.startTracking(LocationConfig(
  accuracy: Accuracy.high,
  distanceFilter: 10.0,
  stopOnTerminate: false,
  startOnBoot: true,
  notificationTitle: 'Tracking',
  notificationBody: 'Running in background',
));

// Listen
LibreLocation.positionStream.listen((Position position) {
  print('[location] ${position.latitude}, ${position.longitude}');
});

LibreLocation.motionChangeStream.listen((Position position) {
  print('[motionChange] isMoving: ${position.isMoving}');
});

// Geofence
await LibreLocation.addGeofence(Geofence(
  id: 'home',
  radiusMeters: 100,
  latitude: 37.42,
  longitude: -122.08,
  triggers: {GeofenceTransition.enter, GeofenceTransition.exit},
));
```

### Key Differences

| flutter_background_geolocation | libre_location |
|---|---|
| `bg.Config(desiredAccuracy: ...)` | `LocationConfig(accuracy: Accuracy.high)` |
| `bg.BackgroundGeolocation.ready()` then `.start()` | `LibreLocation.startTracking(config)` |
| `location.coords.latitude` | `position.latitude` |
| `location.isMoving` | `position.isMoving` |
| `bg.Geofence(identifier: ...)` | `Geofence(id: ...)` |
| Requires license for production | Apache 2.0, free forever |
| Requires Google Play Services | Pure platform APIs |

## Troubleshooting

### "Location stops after X minutes"

This is almost always caused by **battery optimization**. Android OEMs aggressively kill background apps.

**Fix:**

```dart
// 1. Check and request battery optimization exemption
final optimized = await LibreLocation.checkBatteryOptimization();
if (optimized) {
  await LibreLocation.requestBatteryOptimizationExemption();
}

// 2. Open manufacturer-specific settings
await LibreLocation.openPowerManagerSettings();

// 3. Use preventSuspend for critical apps (increases battery usage)
await LibreLocation.startTracking(LocationConfig(
  preventSuspend: true,
  heartbeatInterval: 900, // 15 min heartbeat as fallback
));
```

### "No updates when app is killed"

Set up headless mode:

```dart
// 1. Register headless dispatcher
await LibreLocation.registerHeadlessDispatcher(dispatcher, callback);

// 2. Configure for persistence
await LibreLocation.startTracking(LocationConfig(
  stopOnTerminate: false,
  startOnBoot: true,
  enableHeadless: true,
));
```

### "Inaccurate on Android"

Without Google Play Services, Android uses raw AOSP providers:

- **GPS**: High accuracy (~3-5m) but requires sky view. Slower first fix.
- **Network**: Uses Wi-Fi/cell towers. ~20-100m accuracy. Fast but rough.
- **Passive**: Only receives updates requested by other apps.

**Tips:**
- Use `Accuracy.high` for best results
- Set `mode: TrackingMode.active` for continuous GPS
- Reduce `distanceFilter` for more updates
- Use `samples: 3` in `getCurrentPosition` for averaged readings
- First fix after boot may take 30-60 seconds outdoors

### Samsung Issues

Samsung's "Sleeping Apps" and "Adaptive Battery" aggressively kill background processes.

**User instructions:**
1. Open **Settings → Battery and device care → Battery**
2. Tap **Background usage limits**
3. Remove your app from **Sleeping apps** and **Deep sleeping apps**
4. Add your app to **Never sleeping apps**
5. Disable **Adaptive battery**

**Programmatic:**
```dart
await LibreLocation.openPowerManagerSettings(); // Opens Samsung battery settings
```

### Xiaomi / MIUI Issues

MIUI has the most aggressive battery management. Background apps are killed within minutes without proper configuration.

**User instructions:**
1. Open **Settings → Apps → Manage apps → [Your App]**
2. Tap **Autostart** → Enable
3. Tap **Battery saver** → No restrictions
4. Open **Settings → Battery & performance → App battery saver**
5. Set your app to **No restrictions**
6. In **Security app → Permissions → Autostart** → Enable your app

**Programmatic:**
```dart
final info = await LibreLocation.isAutoStartEnabled();
if (info['manufacturer'] == 'xiaomi' && info['hasAutoStartSetting'] == true) {
  await LibreLocation.openPowerManagerSettings();
}
```

### Huawei / EMUI Issues

**User instructions:**
1. Open **Settings → Battery → App launch**
2. Find your app → Disable **Manage automatically**
3. Enable all three toggles: **Auto-launch**, **Secondary launch**, **Run in background**
4. Open **Settings → Apps → Apps → [Your App] → Battery → Power-intensive prompt** → Disable

### OnePlus / OxygenOS Issues

**User instructions:**
1. Open **Settings → Battery → Battery optimization**
2. Find your app → Select **Don't optimize**
3. Open **Settings → Apps → Special app access → Battery optimization**
4. Set your app to **Not optimized**

## Battery Optimization Guide by Manufacturer

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
|----------|----------------|-------|
| **Android** | API 21 (5.0 Lollipop) | Pure AOSP LocationManager, no Play Services |
| **iOS** | 13.0 | CoreLocation + CoreMotion, BGTaskScheduler for heartbeat |

## Known Limitations

- **Android first fix**: Without Google Play Services, the initial GPS fix can take 30-60 seconds outdoors. Subsequent fixes are fast.
- **Android network provider accuracy**: Network-only positioning uses cell/Wi-Fi and is ~20-100m. No Google location fusion.
- **iOS background limits**: iOS may throttle location updates in the background. Use `preventSuspend` and `heartbeatInterval` for critical apps.
- **iOS geofence limit**: iOS enforces a hard limit of 20 monitored regions. LRU eviction is applied automatically.
- **Activity recognition**: Without Google Play Services Activity Recognition API, activity detection uses accelerometer + step counter + GPS speed heuristics. Confidence may be lower than Play Services-based solutions.
- **No web support**: This plugin targets native mobile platforms only.
- **Heading/course**: On Android, heading is only available when the device is moving (derived from GPS bearing).

## Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork** the repository and create a feature branch
2. **Write tests** for new functionality
3. **Follow existing code style** — Kotlin for Android, Swift for iOS, Dart for the API
4. **Test on real devices** — location plugins behave differently on emulators
5. **Open a PR** with a clear description of changes

### Development Setup

```bash
git clone https://github.com/Rezivure/libre-location.git
cd libre-location

# Run Dart tests
flutter test

# Run Android tests
cd android && ./gradlew test

# Run example app
cd example && flutter run
```

### Reporting Issues

When filing issues, please include:
- Device model and OS version
- Flutter version (`flutter --version`)
- Plugin version
- Steps to reproduce
- Relevant logs (`adb logcat | grep LibreLocation` for Android)

## License

Apache License 2.0 — free for commercial use, no restrictions.
