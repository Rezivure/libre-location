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
