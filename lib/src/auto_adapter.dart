import 'dart:async';
import 'package:flutter/widgets.dart';

import 'tracking_preset.dart';
import 'libre_location_platform.dart';
import 'models/location_config.dart';
import 'models/native_config.dart';
import 'models/activity_event.dart';
import 'enums/accuracy.dart';
import 'logger.dart';

/// Internal auto-adaptation engine.
///
/// Listens to app lifecycle (foreground/background) and activity changes,
/// then adjusts the native tracking config within the bounds of the
/// current [TrackingPreset].
class AutoAdapter with WidgetsBindingObserver {
  TrackingPreset _preset;
  final LocationConfig _userConfig;
  NativeConfig _baseNativeConfig;
  bool _isInForeground = true;
  String _currentActivity = 'unknown';
  bool _isActive = false;

  StreamSubscription<ActivityEvent>? _activitySub;

  AutoAdapter(this._preset, this._userConfig, this._baseNativeConfig);

  TrackingPreset get preset => _preset;
  LocationConfig get userConfig => _userConfig;
  NativeConfig get baseNativeConfig => _baseNativeConfig;

  /// Start listening to lifecycle and activity changes.
  void start() {
    if (_isActive) return;
    _isActive = true;

    final binding = WidgetsBinding.instance;
    binding.addObserver(this);

    _activitySub = LibreLocationPlatform.instance.activityChangeStream.listen(
      _onActivityChange,
      onError: (_) {},
    );

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
    _baseNativeConfig = PresetConfig.buildNativeConfig(preset, _userConfig);
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
    if (event.confidence < 70) return;
    if (event.activity == _currentActivity) return;

    _currentActivity = event.activity;
    LibreLocationLogger.debug('AutoAdapter: activity → $_currentActivity');
    _applyAdaptedConfig();
  }

  /// Compute and apply the adapted config based on preset + lifecycle + activity.
  Future<void> _applyAdaptedConfig() async {
    if (!_isActive) return;

    final lifecycle = _isInForeground
        ? PresetConfig.foregroundOverrides(_preset)
        : PresetConfig.backgroundOverrides(_preset);

    final activity = PresetConfig.activityOverrides(_preset, _currentActivity);

    final double distanceFilter;
    final Accuracy accuracy;
    final int heartbeatInterval;

    if (_isInForeground) {
      distanceFilter = lifecycle.distanceFilter < activity.distanceFilter
          ? lifecycle.distanceFilter
          : activity.distanceFilter;
      accuracy = lifecycle.accuracy.index < activity.accuracy.index
          ? lifecycle.accuracy
          : activity.accuracy;
      heartbeatInterval = lifecycle.heartbeatInterval < activity.heartbeatInterval
          ? lifecycle.heartbeatInterval
          : activity.heartbeatInterval;
    } else {
      distanceFilter = activity.distanceFilter;
      accuracy = activity.accuracy;
      heartbeatInterval = activity.heartbeatInterval > lifecycle.heartbeatInterval
          ? lifecycle.heartbeatInterval
          : activity.heartbeatInterval;
    }

    final adapted = _baseNativeConfig.copyWith(
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
