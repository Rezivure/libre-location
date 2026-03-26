import 'dart:async';
import 'package:flutter/widgets.dart';

import 'tracking_preset.dart';
import 'libre_location_platform.dart';
import 'models/location_config.dart';
import 'models/activity_event.dart';
import 'enums/accuracy.dart';
import 'logger.dart';

/// Internal auto-adaptation engine.
///
/// Listens to app lifecycle (foreground/background) and activity changes,
/// then adjusts the native tracking config within the bounds of the
/// current [TrackingPreset]. This is the core "the plugin adapts, not the app"
/// mechanism.
class AutoAdapter with WidgetsBindingObserver {
  TrackingPreset _preset;
  LocationConfig _baseConfig;
  bool _isInForeground = true;
  String _currentActivity = 'unknown';
  bool _isActive = false;

  StreamSubscription<ActivityEvent>? _activitySub;

  AutoAdapter(this._preset, this._baseConfig);

  TrackingPreset get preset => _preset;
  LocationConfig get baseConfig => _baseConfig;

  /// Start listening to lifecycle and activity changes.
  void start() {
    if (_isActive) return;
    _isActive = true;

    // Register lifecycle observer
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);

    // Listen to activity changes from native
    _activitySub = LibreLocationPlatform.instance.activityChangeStream.listen(
      _onActivityChange,
      onError: (_) {}, // Ignore errors — activity detection may not be available
    );

    // Apply initial config based on current state
    _applyAdaptedConfig();
  }

  /// Stop listening and clean up.
  void stop() {
    if (!_isActive) return;
    _isActive = false;
    WidgetsBinding.instance.removeObserver(this);
    _activitySub?.cancel();
    _activitySub = null;
  }

  /// Switch to a new preset at runtime without stopping tracking.
  Future<void> setPreset(TrackingPreset preset) async {
    _preset = preset;
    _baseConfig = PresetConfig.baseConfig(
      preset,
      notification: _baseConfig.notification,
      backgroundPermissionRationale: _baseConfig.backgroundPermissionRationale,
      stopOnTerminate: _baseConfig.stopOnTerminate,
      startOnBoot: _baseConfig.startOnBoot,
      enableHeadless: _baseConfig.enableHeadless,
      debug: _baseConfig.debug,
      logLevel: _baseConfig.logLevel,
    );
    await _applyAdaptedConfig();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isInForeground;
    switch (state) {
      case AppLifecycleState.resumed:
        _isInForeground = true;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _isInForeground = false;
    }
    if (wasForeground != _isInForeground) {
      LibreLocationLogger.debug(
        'AutoAdapter: lifecycle ${_isInForeground ? "FOREGROUND" : "BACKGROUND"}',
      );
      _applyAdaptedConfig();
    }
  }

  void _onActivityChange(ActivityEvent event) {
    if (event.confidence < 70) return; // Ignore low confidence
    if (event.activity == _currentActivity) return; // No change

    _currentActivity = event.activity;
    LibreLocationLogger.debug('AutoAdapter: activity → $_currentActivity');
    _applyAdaptedConfig();
  }

  /// Compute and apply the adapted config based on preset + lifecycle + activity.
  Future<void> _applyAdaptedConfig() async {
    if (!_isActive) return;

    // Start with lifecycle overrides
    final lifecycle = _isInForeground
        ? PresetConfig.foregroundOverrides(_preset)
        : PresetConfig.backgroundOverrides(_preset);

    // Layer activity overrides on top
    final activity = PresetConfig.activityOverrides(_preset, _currentActivity);

    // Merge: lifecycle sets the base, activity fine-tunes distance/accuracy
    // In foreground, prefer tighter of lifecycle vs activity
    // In background, prefer activity-based (since it knows motion state)
    final double distanceFilter;
    final Accuracy accuracy;
    final int heartbeatInterval;

    if (_isInForeground) {
      // Foreground: use the tighter (smaller) distance filter
      distanceFilter = lifecycle.distanceFilter < activity.distanceFilter
          ? lifecycle.distanceFilter
          : activity.distanceFilter;
      // Use the higher accuracy
      accuracy = lifecycle.accuracy.index < activity.accuracy.index
          ? lifecycle.accuracy
          : activity.accuracy;
      heartbeatInterval = lifecycle.heartbeatInterval < activity.heartbeatInterval
          ? lifecycle.heartbeatInterval
          : activity.heartbeatInterval;
    } else {
      // Background: activity-based is primary, lifecycle is the floor
      distanceFilter = activity.distanceFilter;
      accuracy = activity.accuracy;
      heartbeatInterval = activity.heartbeatInterval > lifecycle.heartbeatInterval
          ? lifecycle.heartbeatInterval
          : activity.heartbeatInterval;
    }

    final adapted = _baseConfig.copyWith(
      distanceFilter: distanceFilter,
      accuracy: accuracy,
      heartbeatInterval: heartbeatInterval,
      intervalMs: lifecycle.intervalMs,
    );

    try {
      await LibreLocationPlatform.instance.setConfig(adapted);
    } catch (e) {
      LibreLocationLogger.error('AutoAdapter: failed to apply config: $e');
    }
  }
}
