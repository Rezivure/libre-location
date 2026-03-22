# libre_location

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Pub Version](https://img.shields.io/pub/v/libre_location)](https://pub.dev/packages/libre_location)
[![CI](https://github.com/Rezivure/libre-location/actions/workflows/ci.yml/badge.svg)](https://github.com/Rezivure/libre-location/actions)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-green.svg)](https://flutter.dev)

**Background location tracking for Flutter — without Google Play Services.**

A production-grade Flutter plugin that uses pure **AOSP LocationManager** on Android and **CoreLocation** on iOS. Zero proprietary dependencies. Built for privacy-focused apps, [GrapheneOS](https://grapheneos.org/), [CalyxOS](https://calyxos.org/), and degoogled devices.

## The Problem

Every popular Flutter location plugin depends on Google Play Services:

| Feature | libre_location | geolocator | background_geolocation | background_location |
|---|:---:|:---:|:---:|:---:|
| **No Play Services** | ✅ | ❌ | ❌ | ❌ |
| Background tracking | ✅ | ⚠️ | ✅ | ✅ |
| Motion detection | ✅ | ❌ | ✅ | ❌ |
| Geofencing | ✅ | ❌ | ✅ | ❌ |
| Open source | ✅ Apache 2.0 | ✅ MIT | ⚠️ Paid license | ✅ MIT |
| Works on GrapheneOS | ✅ | ❌ | ❌ | ❌ |
| Works on CalyxOS | ✅ | ❌ | ❌ | ❌ |
| Pure platform APIs | ✅ | ❌ | ❌ | ❌ |

If your users run degoogled phones, custom ROMs, or simply value privacy — their location features break with every other plugin. **libre_location fixes this.**

## Features

- 📍 **Background location tracking** with foreground service (Android) and background modes (iOS)
- 🏃 **Motion detection** — accelerometer-based on Android, CMMotionActivityManager on iOS
- 🎯 **Geofencing** — ProximityAlert (Android) / CLCircularRegion (iOS), no Play Services
- 🔋 **Three tracking modes** — Active, Balanced, Passive with configurable battery impact
- 🔒 **Zero proprietary dependencies** — no Google Play Services, no proprietary SDKs
- 📱 **Works everywhere** — stock Android, GrapheneOS, CalyxOS, LineageOS, /e/OS, iOS

## Quick Start

### Installation

```yaml
dependencies:
  libre_location: ^0.1.0
```

### Android Setup

Add permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

### iOS Setup

Add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to provide tracking features.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need background location access for continuous tracking.</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

## Usage

### Check & Request Permissions

```dart
final permission = await LibreLocation.checkPermission();
if (permission == LocationPermission.denied) {
  await LibreLocation.requestPermission();
}
```

### Get Current Position

```dart
final position = await LibreLocation.getCurrentPosition(
  accuracy: Accuracy.high,
);
print('${position.latitude}, ${position.longitude}');
print('Accuracy: ${position.accuracy}m, Provider: ${position.provider}');
```

### Background Tracking

```dart
// Start tracking
await LibreLocation.startTracking(const LocationConfig(
  accuracy: Accuracy.high,
  mode: TrackingMode.balanced,
  intervalMs: 30000,
  distanceFilter: 10.0,
  enableMotionDetection: true,
  notificationTitle: 'My App',
  notificationBody: 'Tracking your location',
));

// Listen to updates
LibreLocation.positionStream.listen((position) {
  print('New position: ${position.latitude}, ${position.longitude}');
  print('Provider: ${position.provider}'); // 'gps', 'network', or 'passive'
});

// Stop tracking
await LibreLocation.stopTracking();
```

### Geofencing

```dart
// Add a geofence
await LibreLocation.addGeofence(Geofence(
  id: 'home',
  latitude: 37.7749,
  longitude: -122.4194,
  radiusMeters: 100,
  triggers: {GeofenceTransition.enter, GeofenceTransition.exit},
));

// Listen for events
LibreLocation.geofenceStream.listen((event) {
  print('${event.transition.name} geofence: ${event.geofence.id}');
});

// Remove a geofence
await LibreLocation.removeGeofence('home');
```

## Tracking Modes

| Mode | Interval | Accuracy | Battery Impact | Best For |
|---|---|---|---|---|
| **Active** | 30s–2min | GPS (best) | ~5–8%/day | Navigation, fitness |
| **Balanced** | ~5 min | Network + GPS on motion | ~2–4%/day | General tracking |
| **Passive** | On significant change | ~500m | ~1%/day | Presence, analytics |

### Motion Detection

When `enableMotionDetection: true`, the plugin automatically:
- **Android:** Monitors accelerometer variance over a 30-second window. Pauses GPS when still, resumes on movement. Uses `TYPE_SIGNIFICANT_MOTION` sensor as a wake trigger.
- **iOS:** Uses `CMMotionActivityManager` to detect stationary/walking/driving states and adjusts accuracy accordingly.

## How It Works

### Android
- Uses `android.location.LocationManager` with `GPS_PROVIDER` and `NETWORK_PROVIDER`
- Foreground Service with persistent notification (required for Android 8+ background)
- `START_STICKY` service that survives process kills
- Geofencing via `LocationManager.addProximityAlert()` — pure AOSP API

### iOS
- Uses `CLLocationManager` with `allowsBackgroundLocationUpdates = true`
- `startUpdatingLocation()` for active tracking
- `startMonitoringSignificantLocationChanges()` for passive mode
- Geofencing via `CLCircularRegion` monitoring (up to 20 regions)

### What This Does NOT Use
- ❌ `com.google.android.gms.location.FusedLocationProviderClient`
- ❌ `com.google.android.gms.location.GeofencingClient`
- ❌ Any Google Play Services library
- ❌ Any proprietary SDK

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

```
Copyright 2024 Rezivure

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
```

See [LICENSE](LICENSE) for the full text.
