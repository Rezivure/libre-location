# libre_location

Production-grade background location tracking for Flutter — **zero Google Play Services dependency**.

Uses pure AOSP `LocationManager` on Android and `CoreLocation` on iOS. Built for privacy-focused apps running on GrapheneOS, CalyxOS, LineageOS, and any degoogled device.

## Features

- **Background tracking** that survives app termination
- **Start on boot** — automatic restart after device reboot
- **Heartbeat** — guaranteed periodic location updates even when stationary
- **Activity recognition** — walking, running, cycling, driving, stationary
- **Motion change detection** — moving ↔ stationary transitions with configurable thresholds
- **Dynamic config changes** at runtime via `setConfig()`
- **getCurrentPosition** with multi-sample averaging, timeout, and maximum age caching
- **Battery saver mode** — reduced accuracy/frequency when stationary
- **Foreground service** with configurable notification (Android)
- **Background location indicator** (iOS)
- **Permission handling** including background/always permission flow
- **Geofencing** with enter, exit, and dwell events
- **Zero Google Play Services** — works on any Android device

## Installation

```yaml
dependencies:
  libre_location:
    git:
      url: https://github.com/Rezivure/libre-location.git
```

## Quick Start

```dart
import 'package:libre_location/libre_location.dart';

// 1. Request permissions
final permission = await LibreLocation.requestPermission();
if (permission != LocationPermission.always) {
  // Handle — background tracking requires "always" permission
  return;
}

// 2. Start tracking
await LibreLocation.startTracking(LocationConfig(
  accuracy: Accuracy.high,
  distanceFilter: 10.0,
  stopOnTerminate: false,
  startOnBoot: true,
  heartbeatInterval: 300, // seconds
  notification: NotificationConfig(
    title: 'Grid',
    text: 'Sharing your location',
  ),
));

// 3. Listen for updates
LibreLocation.positionStream.listen((position) {
  print('${position.latitude}, ${position.longitude}');
});

LibreLocation.activityChangeStream.listen((activity) {
  print('${activity.activity}: ${activity.confidence}%');
});

LibreLocation.heartbeatStream.listen((heartbeat) {
  print('Heartbeat: ${heartbeat.position.latitude}');
});

// 4. Stop tracking
await LibreLocation.stopTracking();
```

## API Reference

### `LibreLocation` (static methods)

| Method | Description |
|--------|-------------|
| `startTracking(LocationConfig)` | Start background location tracking |
| `stopTracking()` | Stop tracking and remove foreground service |
| `setConfig(LocationConfig)` | Update config at runtime without restart |
| `getCurrentPosition(...)` | Get current position with optional multi-sample averaging |
| `checkPermission()` | Check current location permission status |
| `requestPermission()` | Request location permission (handles background escalation) |
| `addGeofence(Geofence)` | Add a geofence to monitor |
| `removeGeofence(String id)` | Remove a geofence by ID |
| `getGeofences()` | Get all registered geofences |
| `isTracking` | Whether tracking is currently active |

### Streams

| Stream | Type | Description |
|--------|------|-------------|
| `positionStream` | `Stream<Position>` | Location updates |
| `motionChangeStream` | `Stream<Position>` | Moving ↔ stationary transitions (with position) |
| `activityChangeStream` | `Stream<ActivityEvent>` | Activity type changes |
| `heartbeatStream` | `Stream<HeartbeatEvent>` | Periodic heartbeat locations |
| `providerChangeStream` | `Stream<ProviderEvent>` | GPS/network provider state changes |
| `geofenceStream` | `Stream<GeofenceEvent>` | Geofence enter/exit/dwell events |

### `LocationConfig`

```dart
LocationConfig(
  accuracy: Accuracy.high,          // high, balanced, low, passive, navigation
  intervalMs: 60000,                // ms between updates
  distanceFilter: 10.0,            // minimum meters between updates
  mode: TrackingMode.balanced,     // active, balanced, passive
  
  // Lifecycle
  stopOnTerminate: false,          // keep tracking after app is killed
  startOnBoot: true,               // restart tracking after device reboot
  enableHeadless: true,            // enable headless background execution
  
  // Motion detection
  enableMotionDetection: true,
  stopTimeout: 5,                  // minutes of stillness before "stationary"
  stationaryRadius: 25.0,         // meters
  motionTriggerDelay: 0,          // ms delay before declaring "moving"
  
  // Heartbeat
  heartbeatInterval: 300,         // seconds (0 = disabled)
  
  // Activity recognition
  activityRecognitionInterval: 10000,
  minimumActivityRecognitionConfidence: 75,
  
  // iOS-specific
  pausesLocationUpdatesAutomatically: false,
  activityType: ActivityType.other,
  preventSuspend: false,
  
  // Android notification
  notification: NotificationConfig(
    title: 'Location Tracking',
    text: 'Tracking in background',
    sticky: true,
    priority: NotificationPriority.low,
  ),
  
  // Permission rationale dialog
  backgroundPermissionRationale: PermissionRationale(
    title: 'Background Location',
    message: 'We need background location access to...',
  ),
)
```

### `Position`

```dart
Position(
  latitude: 37.7749,
  longitude: -122.4194,
  altitude: 10.0,
  accuracy: 5.0,          // meters
  speed: 1.5,             // m/s
  heading: 90.0,          // degrees
  timestamp: DateTime,
  provider: 'gps',        // 'gps', 'network', 'core_location'
  isMoving: true,
  activity: ActivityEvent?,
  battery: BatteryInfo?,
)
```

## Platform Setup

### Android

Add to `AndroidManifest.xml` (most are included by the plugin automatically):

```xml
<!-- Required -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<!-- Optional: for start on boot -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

### iOS

Add to `Info.plist`:

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to share with your contacts.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show on the map.</string>
<key>NSMotionUsageDescription</key>
<string>We use motion data to detect your activity type.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

## Migration from flutter_background_geolocation

| flutter_background_geolocation | libre_location |
|------|------|
| `bg.ready(Config(...))` | `LibreLocation.startTracking(LocationConfig(...))` |
| `bg.start()` | (included in `startTracking`) |
| `bg.stop()` | `LibreLocation.stopTracking()` |
| `bg.setConfig(Config(...))` | `LibreLocation.setConfig(LocationConfig(...))` |
| `bg.getCurrentPosition(...)` | `LibreLocation.getCurrentPosition(...)` |
| `bg.onLocation((loc) => ...)` | `LibreLocation.positionStream.listen(...)` |
| `bg.onMotionChange((loc) => ...)` | `LibreLocation.motionChangeStream.listen(...)` |
| `bg.onActivityChange((ev) => ...)` | `LibreLocation.activityChangeStream.listen(...)` |
| `bg.onHeartbeat((ev) => ...)` | `LibreLocation.heartbeatStream.listen(...)` |
| `bg.onGeofence((ev) => ...)` | `LibreLocation.geofenceStream.listen(...)` |
| `bg.onProviderChange((ev) => ...)` | `LibreLocation.providerChangeStream.listen(...)` |
| `bg.addGeofence(Geofence(...))` | `LibreLocation.addGeofence(Geofence(...))` |
| `bg.removeGeofence(id)` | `LibreLocation.removeGeofence(id)` |
| `Config.desiredAccuracy` | `LocationConfig.accuracy` |
| `Config.distanceFilter` | `LocationConfig.distanceFilter` |
| `Config.stopOnTerminate` | `LocationConfig.stopOnTerminate` |
| `Config.startOnBoot` | `LocationConfig.startOnBoot` |
| `Config.heartbeatInterval` | `LocationConfig.heartbeatInterval` |
| `location.coords.latitude` | `position.latitude` |
| `location.isMoving` | `position.isMoving` |
| `location.activity.type` | `position.activity?.activity` |

### Key differences:

1. **No license key** — libre_location is free and open source
2. **No Google Play Services** — works on GrapheneOS, CalyxOS, etc.
3. **Activity recognition** uses accelerometer heuristics (CMMotionActivity on iOS) instead of Google's Activity Recognition API
4. **Single entry point** — `startTracking()` replaces `ready()` + `start()`
5. **Config object** uses `LocationConfig` instead of `Config`

## Architecture

```
┌─────────────────────────────────────────┐
│              Dart API                    │
│  LibreLocation → MethodChannelLibre...  │
│  EventChannels for streams              │
└────────────────┬────────────────────────┘
                 │ MethodChannel / EventChannel
     ┌───────────┴───────────┐
     ▼                       ▼
┌─────────────────┐   ┌─────────────────┐
│   iOS Native    │   │ Android Native  │
│ CoreLocation    │   │ AOSP LocManager │
│ CoreMotion      │   │ ForegroundSvc   │
│ CLCircularRegion│   │ AlarmManager    │
│ UserDefaults    │   │ SQLite Buffer   │
└─────────────────┘   └─────────────────┘
```

## License

Apache 2.0
