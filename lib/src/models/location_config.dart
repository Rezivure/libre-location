import 'notification_config.dart';
import 'permission_rationale.dart';

/// Developer-facing configuration for libre_location.
///
/// This is intentionally simple. All the GPS tuning knobs (distance filters,
/// accuracy levels, activity recognition intervals, etc.) are handled
/// internally by [TrackingPreset] and the auto-adaptation engine.
///
/// You only need to configure things that are genuinely app-specific:
///
/// ```dart
/// await LibreLocation.start(
///   preset: TrackingPreset.balanced,
///   config: LocationConfig(
///     notification: NotificationConfig(
///       title: 'My App',
///       text: 'Tracking your location',
///     ),
///   ),
/// );
/// ```
class LocationConfig {
  /// Android foreground service notification. Required for reliable
  /// background tracking on Android 8+.
  final NotificationConfig? notification;

  /// Android background permission rationale dialog text.
  final PermissionRationale? backgroundPermissionRationale;

  /// Whether to stop tracking when the app is terminated.
  /// Default: `false` (keeps tracking after app close).
  final bool stopOnTerminate;

  /// Whether to restart tracking after device reboot.
  /// Default: `true`.
  final bool startOnBoot;

  /// Whether to enable headless Dart callbacks after app termination (Android).
  /// Default: `true`.
  final bool enableHeadless;

  /// Enable debug logging. Default: `false`.
  final bool debug;

  const LocationConfig({
    this.notification,
    this.backgroundPermissionRationale,
    this.stopOnTerminate = false,
    this.startOnBoot = true,
    this.enableHeadless = true,
    this.debug = false,
  });

  LocationConfig copyWith({
    NotificationConfig? notification,
    PermissionRationale? backgroundPermissionRationale,
    bool? stopOnTerminate,
    bool? startOnBoot,
    bool? enableHeadless,
    bool? debug,
  }) {
    return LocationConfig(
      notification: notification ?? this.notification,
      backgroundPermissionRationale: backgroundPermissionRationale ?? this.backgroundPermissionRationale,
      stopOnTerminate: stopOnTerminate ?? this.stopOnTerminate,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      enableHeadless: enableHeadless ?? this.enableHeadless,
      debug: debug ?? this.debug,
    );
  }

  @override
  String toString() =>
      'LocationConfig(stopOnTerminate: $stopOnTerminate, startOnBoot: $startOnBoot, debug: $debug)';
}
