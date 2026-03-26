# libre_location Integration Progress

## Grid Mobile Integration Test — 2026-03-26

### Summary
Successfully replaced `flutter_background_geolocation` with `libre_location` in Grid Mobile. Both Android and iOS compile cleanly.

### Branch
`feature/libre-location` on Grid Mobile (local only, not pushed)

### What Changed
| File | Change |
|---|---|
| `pubspec.yaml` | Replaced `flutter_background_geolocation: ^4.18.1` with path dep to libre_location |
| `location_manager.dart` | Full rewrite using preset API (368 → ~120 lines) |
| `room_service.dart` | `bg.Location` → `Position`, `.coords.latitude` → `.latitude` |
| `android_background_task.dart` | Rewritten for libre_location headless API (`registerHeadlessDispatcher`) |
| `main.dart` | `registerHeadlessTask` → `registerHeadlessDispatcher` |
| `settings_page.dart` | Removed direct `bg.BackgroundGeolocation.stop()/start()` calls (handled by LocationManager) |
| `onboarding_modal.dart` | Replaced `bg.BackgroundGeolocation.ready/requestPermission` with `LibreLocation.requestPermission/checkPermission` |
| `android/app/build.gradle` | Removed `flutter_background_geolocation` gradle plugin reference |
| `android/build.gradle` | Removed maven repo references for old plugin + background_fetch |

### Build Results
- **Android APK (debug)**: ✅ Builds successfully
- **iOS (no-codesign)**: ✅ Builds successfully

### Stats
- **Lines changed**: 138 insertions, 495 deletions (net -357 lines)
- **Config params managed by developer**: 15+ → 0
- **Adaptation contexts removed**: 4 (foreground, background, battery saver, activity-based)
- **Dependencies removed**: `flutter_background_geolocation`, `background_fetch`

### Key API Mappings
| flutter_background_geolocation | libre_location |
|---|---|
| `bg.BackgroundGeolocation.ready(Config(...))` + `start()` | `LibreLocation.start(preset: TrackingPreset.balanced)` |
| `bg.BackgroundGeolocation.setConfig(Config(...))` | `LibreLocation.setPreset(TrackingPreset.low)` |
| `bg.BackgroundGeolocation.requestPermission()` → int | `LibreLocation.requestPermission()` → `LocationPermission` enum |
| `bg.BackgroundGeolocation.onLocation(callback)` | `LibreLocation.onLocation.listen(callback)` |
| `bg.Location` with `location.coords.latitude` | `Position` with `position.latitude` |
| `bg.BackgroundGeolocation.registerHeadlessTask(fn)` | `LibreLocation.registerHeadlessDispatcher(dispatcher, callback)` |
| `bg.BackgroundGeolocation.getCurrentPosition(...)` | `LibreLocation.getCurrentPosition(...)` |

### Not Yet Tested
- Runtime behavior (actual location tracking on device)
- Headless mode callback delivery
- Preset switching at runtime
- Battery impact comparison
