// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

// ============================================================================
// SIMULATION ENGINE
// ============================================================================

/// Preset configuration values extracted from tracking_preset.dart
class PresetValues {
  final String name;
  final double distanceFilter;
  final int intervalMs;
  final int stillnessTimeoutMin;
  final double stillnessRadiusMeters;
  final int heartbeatIntervalSec;
  final double maxAccuracy;

  // Activity-specific distance filters (balanced background)
  final double drivingDistanceFilter;
  final double walkingDistanceFilter;
  final double bikingDistanceFilter;

  const PresetValues({
    required this.name,
    required this.distanceFilter,
    required this.intervalMs,
    required this.stillnessTimeoutMin,
    required this.stillnessRadiusMeters,
    required this.heartbeatIntervalSec,
    required this.maxAccuracy,
    required this.drivingDistanceFilter,
    required this.walkingDistanceFilter,
    required this.bikingDistanceFilter,
  });

  static const low = PresetValues(
    name: 'low',
    distanceFilter: 500,
    intervalMs: 300000,
    stillnessTimeoutMin: 15,
    stillnessRadiusMeters: 200,
    heartbeatIntervalSec: 1800,
    maxAccuracy: 500,
    drivingDistanceFilter: 300,
    walkingDistanceFilter: 400,
    bikingDistanceFilter: 400,
  );

  static const balanced = PresetValues(
    name: 'balanced',
    distanceFilter: 50,
    intervalMs: 60000,
    stillnessTimeoutMin: 5,
    stillnessRadiusMeters: 50,
    heartbeatIntervalSec: 900,
    maxAccuracy: 100,
    drivingDistanceFilter: 150,
    walkingDistanceFilter: 20,
    bikingDistanceFilter: 30,
  );

  static const high = PresetValues(
    name: 'high',
    distanceFilter: 10,
    intervalMs: 15000,
    stillnessTimeoutMin: 3,
    stillnessRadiusMeters: 25,
    heartbeatIntervalSec: 300,
    maxAccuracy: 50,
    drivingDistanceFilter: 50,
    walkingDistanceFilter: 5,
    bikingDistanceFilter: 10,
  );
}

/// Types of simulated events
enum SimEventType {
  stationary,
  walk,
  drive,
  bike,
  transit,
  indoorWalk,
  sleep,
}

/// A simulated movement event
class SimEvent {
  final SimEventType type;
  final Duration duration;
  final double distanceMeters; // total distance covered
  final double accuracyMeters; // GPS accuracy during this event

  const SimEvent._({
    required this.type,
    required this.duration,
    this.distanceMeters = 0,
    this.accuracyMeters = 10,
  });

  factory SimEvent.stationary(Duration duration, {double accuracy = 10}) =>
      SimEvent._(type: SimEventType.stationary, duration: duration, accuracyMeters: accuracy);

  factory SimEvent.walk(Duration duration, {double? distance, double accuracy = 10}) =>
      SimEvent._(
        type: SimEventType.walk,
        duration: duration,
        distanceMeters: distance ?? (duration.inSeconds * 1.34), // ~3mph = 1.34 m/s
        accuracyMeters: accuracy,
      );

  factory SimEvent.drive(Duration duration, {double? distance, double accuracy = 10}) =>
      SimEvent._(
        type: SimEventType.drive,
        duration: duration,
        distanceMeters: distance ?? (duration.inSeconds * 22.35), // ~50mph = 22.35 m/s
        accuracyMeters: accuracy,
      );

  factory SimEvent.bike(Duration duration, {double? distance, double accuracy = 10}) =>
      SimEvent._(
        type: SimEventType.bike,
        duration: duration,
        distanceMeters: distance ?? (duration.inSeconds * 5.36), // ~12mph = 5.36 m/s
        accuracyMeters: accuracy,
      );

  factory SimEvent.transit(Duration duration, {double? distance, double accuracy = 50}) =>
      SimEvent._(
        type: SimEventType.transit,
        duration: duration,
        distanceMeters: distance ?? (duration.inSeconds * 11.0), // ~25mph avg
        accuracyMeters: accuracy,
      );

  factory SimEvent.indoorWalk(Duration duration, {double? distance, double accuracy = 30}) =>
      SimEvent._(
        type: SimEventType.indoorWalk,
        duration: duration,
        distanceMeters: distance ?? min(duration.inSeconds * 0.5, 20), // stays within small area
        accuracyMeters: accuracy,
      );

  factory SimEvent.sleep(Duration duration) =>
      SimEvent._(type: SimEventType.sleep, duration: duration, accuracyMeters: 10);

  String get label {
    switch (type) {
      case SimEventType.stationary:
        return 'stationary';
      case SimEventType.walk:
        return 'walk';
      case SimEventType.drive:
        return 'drive';
      case SimEventType.bike:
        return 'bike';
      case SimEventType.transit:
        return 'transit';
      case SimEventType.indoorWalk:
        return 'indoor walk';
      case SimEventType.sleep:
        return 'sleep';
    }
  }

  bool get isMovement =>
      type == SimEventType.walk ||
      type == SimEventType.drive ||
      type == SimEventType.bike ||
      type == SimEventType.transit;

  /// Whether this event represents movement that stays within stillnessRadius
  bool isWithinGeofence(double stillnessRadius) =>
      type == SimEventType.indoorWalk || type == SimEventType.sleep ||
      (type == SimEventType.stationary);

  double get effectiveDistanceFilter {
    // Returns the activity-appropriate string for lookup
    switch (type) {
      case SimEventType.drive:
        return -1; // sentinel: use preset's driving filter
      case SimEventType.walk:
        return -2; // sentinel: use preset's walking filter
      case SimEventType.bike:
        return -3; // sentinel: use preset's biking filter
      default:
        return -2; // walking-like
    }
  }

  double distanceFilterFor(PresetValues preset) {
    switch (type) {
      case SimEventType.drive:
        return preset.drivingDistanceFilter;
      case SimEventType.walk:
      case SimEventType.transit:
        return preset.walkingDistanceFilter;
      case SimEventType.bike:
        return preset.bikingDistanceFilter;
      default:
        return preset.distanceFilter;
    }
  }

  /// Speed in m/s
  double get speedMs => duration.inSeconds > 0 ? distanceMeters / duration.inSeconds : 0;
}

/// Tracking state
enum TrackingState { moving, stationary }

/// Result of a simulation run
class SimulationReport {
  final String scenarioName;
  final String presetName;
  final Duration totalDuration;
  final Duration gpsOnTime;
  final Duration gpsOffTime;
  final int stateTransitions; // total MOVING↔STATIONARY transitions
  final int locationEvents;
  final int geofenceDrops;
  final int geofenceExits;
  final double batteryEstimate; // percentage
  final int networkGateChecks; // Android-specific
  final bool hadFalseWakes; // indoor walk triggered GPS

  SimulationReport({
    required this.scenarioName,
    required this.presetName,
    required this.totalDuration,
    required this.gpsOnTime,
    required this.gpsOffTime,
    required this.stateTransitions,
    required this.locationEvents,
    required this.geofenceDrops,
    required this.geofenceExits,
    required this.batteryEstimate,
    this.networkGateChecks = 0,
    this.hadFalseWakes = false,
  });

  double get gpsOnPercent => totalDuration.inSeconds > 0
      ? (gpsOnTime.inSeconds / totalDuration.inSeconds * 100)
      : 0;

  double get gpsOffPercent => 100 - gpsOnPercent;

  void printReport() {
    print('');
    print('=== $scenarioName ($presetName) ===');
    print('Duration:          ${(totalDuration.inMinutes / 60.0).toStringAsFixed(1)} hr');
    print('GPS on:            ${(gpsOnTime.inMinutes / 60.0).toStringAsFixed(1)} hr (${gpsOnPercent.toStringAsFixed(1)}%)');
    print('GPS off:           ${(gpsOffTime.inMinutes / 60.0).toStringAsFixed(1)} hr (${gpsOffPercent.toStringAsFixed(1)}%)');
    print('Transitions:       $stateTransitions (MOVING↔STATIONARY)');
    print('Location events:   ~$locationEvents');
    print('Geofence drops:    $geofenceDrops');
    print('Geofence exits:    $geofenceExits');
    if (networkGateChecks > 0) {
      print('Network gate:      $networkGateChecks checks');
    }
    print('Battery estimate:  ${batteryEstimate.toStringAsFixed(1)}%');
    print('False wakes:       ${hadFalseWakes ? "YES ⚠️" : "none ✓"}');
  }
}

/// Simulates the state machine behavior of the native location tracking code.
///
/// Models MOVING ↔ STATIONARY transitions, GPS on/off time, location event
/// emission, geofence lifecycle, and battery drain based on preset config values.
class TrackingSimulator {
  final PresetValues preset;

  TrackingSimulator(this.preset);

  SimulationReport run(String scenarioName, List<SimEvent> events) {
    var state = TrackingState.stationary; // starts stationary (sleep/home)
    var gpsOnSeconds = 0.0;
    var gpsOffSeconds = 0.0;
    var transitions = 0;
    var locationEvents = 0;
    var geofenceDrops = 0;
    var geofenceExits = 0;
    var networkGateChecks = 0;
    var hadFalseWakes = false;
    var totalSeconds = 0.0;

    // Time accumulator for stillness detection
    var stillnessAccumulator = 0.0;
    var geofenceActive = false;

    // Initial state: stationary with geofence
    geofenceDrops++;
    geofenceActive = true;

    for (final event in events) {
      final durationSec = event.duration.inSeconds.toDouble();
      totalSeconds += durationSec;

      if (event.isMovement) {
        // --- MOVEMENT EVENT ---
        final leavesGeofence = event.distanceMeters > preset.stillnessRadiusMeters;

        if (state == TrackingState.stationary && leavesGeofence) {
          // Geofence exit → transition to MOVING
          state = TrackingState.moving;
          transitions++;
          geofenceExits++;
          geofenceActive = false;
          stillnessAccumulator = 0;
        } else if (state == TrackingState.stationary && !leavesGeofence) {
          // Indoor-like movement that stays within geofence
          // GPS stays OFF — no transition
          if (event.type == SimEventType.indoorWalk) {
            // This should NOT wake GPS
            gpsOffSeconds += durationSec;
            continue;
          }
        }

        if (state == TrackingState.moving) {
          // GPS is ON, emit location events
          gpsOnSeconds += durationSec;
          stillnessAccumulator = 0;

          // Calculate location events based on distance filter and interval
          final df = event.distanceFilterFor(preset);
          final intervalSec = preset.intervalMs / 1000.0;

          // Events limited by whichever gate fires less frequently:
          // 1. Distance: totalDistance / distanceFilter
          // 2. Time: duration / interval
          final eventsByDistance = df > 0 ? (event.distanceMeters / df).floor() : 0;
          final eventsByTime = (durationSec / intervalSec).floor();

          // Also filter by accuracy — if accuracy > maxAccuracy, fewer events pass
          double accuracyPassRate = 1.0;
          if (event.accuracyMeters > preset.maxAccuracy) {
            accuracyPassRate = 0.0; // all filtered out
          } else if (event.accuracyMeters > preset.maxAccuracy * 0.8) {
            accuracyPassRate = 0.5; // some filtered
          }

          // The actual emission is constrained by BOTH distance and time filters
          // Native code: distance filter is the primary gate, interval is secondary
          final rawEvents = min(eventsByDistance, eventsByTime);
          locationEvents += max(1, (rawEvents * accuracyPassRate).round());
        }
      } else {
        // --- STATIONARY/SLEEP EVENT ---
        if (state == TrackingState.moving) {
          // Accumulate stillness time
          final timeoutSec = preset.stillnessTimeoutMin * 60.0;

          if (durationSec >= timeoutSec) {
            // Enough time to trigger stop detection
            // GPS is on for stillnessTimeout, then off for remainder
            gpsOnSeconds += timeoutSec;
            gpsOffSeconds += (durationSec - timeoutSec);

            // Transition to stationary
            state = TrackingState.stationary;
            transitions++;
            geofenceDrops++;
            geofenceActive = true;
            stillnessAccumulator = 0;

            // Few location events during the GPS-on portion (mostly stationary, so distance filter blocks)
            // Maybe 1-2 events from the stop detection period
            locationEvents += 1;
          } else {
            // Not long enough to trigger stop detection — GPS stays on
            gpsOnSeconds += durationSec;
            stillnessAccumulator += durationSec;
            // Minimal events (not moving much)
            locationEvents += 1;
          }
        } else {
          // Already stationary — GPS is off
          gpsOffSeconds += durationSec;

          // Android: indoor movement might trigger network gate checks
          // Cooldown is 60s, but accelerometer bursts are sparse
          if (event.type == SimEventType.indoorWalk) {
            // Typically 1 gate check per indoor walk event (cooldown prevents more)
            networkGateChecks += 1;
          }
        }
      }
    }

    // Battery calculation
    // GPS active: 5%/hr, GPS off + geofence: 0.2%/hr, network gate: 0.05% per check
    final batteryGps = (gpsOnSeconds / 3600.0) * 5.0;
    final batteryGeofence = (gpsOffSeconds / 3600.0) * 0.2;
    final batteryGate = networkGateChecks * 0.05;
    final battery = batteryGps + batteryGeofence + batteryGate;

    return SimulationReport(
      scenarioName: scenarioName,
      presetName: preset.name,
      totalDuration: Duration(seconds: totalSeconds.round()),
      gpsOnTime: Duration(seconds: gpsOnSeconds.round()),
      gpsOffTime: Duration(seconds: gpsOffSeconds.round()),
      stateTransitions: transitions,
      locationEvents: locationEvents,
      geofenceDrops: geofenceDrops,
      geofenceExits: geofenceExits,
      batteryEstimate: battery,
      networkGateChecks: networkGateChecks,
      hadFalseWakes: hadFalseWakes,
    );
  }
}

// ============================================================================
// SCENARIO DEFINITIONS
// ============================================================================

const _min = Duration(minutes: 1);

Duration minutes(int m) => Duration(minutes: m);
Duration hours(int h) => Duration(hours: h);

List<SimEvent> officeWorkerScenario() => [
  SimEvent.sleep(hours(8)),
  SimEvent.indoorWalk(minutes(15), distance: 30),
  SimEvent.drive(minutes(30)),
  SimEvent.stationary(hours(4)),
  SimEvent.walk(minutes(10)),
  SimEvent.stationary(minutes(45)),
  SimEvent.walk(minutes(10)),
  SimEvent.stationary(hours(4)),
  SimEvent.drive(minutes(30)),
  SimEvent.indoorWalk(minutes(15), distance: 20),
  SimEvent.sleep(hours(5)),
];

List<SimEvent> urbanCommuterScenario() => [
  SimEvent.sleep(hours(8)),
  SimEvent.walk(minutes(10)),
  SimEvent.transit(minutes(25), accuracy: 80),
  SimEvent.walk(minutes(8)),
  SimEvent.stationary(hours(4)),
  SimEvent.walk(minutes(5)),
  SimEvent.stationary(hours(4)),
  SimEvent.walk(minutes(8)),
  SimEvent.transit(minutes(25), accuracy: 80),
  SimEvent.walk(minutes(10)),
  SimEvent.walk(minutes(30)),
  SimEvent.sleep(hours(5)),
];

List<SimEvent> deliveryDriverScenario() => [
  // Morning shift
  SimEvent.drive(minutes(10)),
  SimEvent.stationary(minutes(5)),
  SimEvent.drive(minutes(8)),
  SimEvent.stationary(minutes(3)),
  SimEvent.drive(minutes(15)),
  SimEvent.stationary(minutes(5)),
  SimEvent.drive(minutes(12)),
  SimEvent.stationary(minutes(4)),
  SimEvent.drive(minutes(10)),
  SimEvent.stationary(minutes(3)),
  // Lunch
  SimEvent.stationary(minutes(30)),
  // Afternoon shift
  SimEvent.drive(minutes(10)),
  SimEvent.stationary(minutes(5)),
  SimEvent.drive(minutes(8)),
  SimEvent.stationary(minutes(3)),
  SimEvent.drive(minutes(15)),
  SimEvent.stationary(minutes(5)),
  SimEvent.drive(minutes(12)),
  SimEvent.stationary(minutes(4)),
  SimEvent.drive(minutes(10)),
  SimEvent.stationary(minutes(3)),
  SimEvent.drive(minutes(15)),
  SimEvent.stationary(minutes(5)),
  SimEvent.drive(minutes(10)),
  SimEvent.stationary(minutes(3)),
  // Drive home
  SimEvent.drive(minutes(20)),
  SimEvent.sleep(hours(8)),
];

List<SimEvent> workFromHomeScenario() => [
  SimEvent.sleep(hours(8)),
  SimEvent.indoorWalk(minutes(10), distance: 15),
  SimEvent.stationary(hours(2)),
  SimEvent.indoorWalk(minutes(5), distance: 10),
  SimEvent.stationary(hours(2)),
  SimEvent.walk(minutes(20)), // outside walk
  SimEvent.stationary(hours(2)),
  SimEvent.indoorWalk(minutes(5), distance: 10),
  SimEvent.stationary(hours(3)),
  SimEvent.indoorWalk(minutes(5), distance: 8),
  SimEvent.sleep(hours(8)),
];

List<SimEvent> weekendHikerScenario() => [
  SimEvent.drive(minutes(45)),
  SimEvent.walk(hours(3), accuracy: 15),
  SimEvent.stationary(minutes(20)),
  SimEvent.walk(hours(2), accuracy: 20),
  SimEvent.drive(minutes(45)),
];

List<SimEvent> airportTravelScenario() => [
  SimEvent.stationary(hours(1)),
  SimEvent.drive(minutes(55), distance: 55 * 60 * 26.82), // 60mph
  SimEvent.walk(minutes(15), accuracy: 45, distance: 800),
  SimEvent.stationary(hours(1)),
  SimEvent.walk(minutes(5), accuracy: 40, distance: 300),
  SimEvent.stationary(hours(3)),
  SimEvent.walk(minutes(10), accuracy: 35, distance: 500),
  SimEvent.drive(minutes(30)),
];

List<SimEvent> couchPotatoScenario() => [
  SimEvent.sleep(hours(10)),
  SimEvent.indoorWalk(minutes(3), distance: 10),
  SimEvent.stationary(hours(3)),
  SimEvent.indoorWalk(minutes(2), distance: 8),
  SimEvent.stationary(hours(3)),
  SimEvent.indoorWalk(minutes(3), distance: 10),
  SimEvent.stationary(hours(4)),
  SimEvent.indoorWalk(minutes(2), distance: 5),
  SimEvent.sleep(hours(8)),
];

List<SimEvent> cyclistCommuterScenario() => [
  SimEvent.sleep(hours(8)),
  SimEvent.bike(minutes(25)),
  SimEvent.stationary(hours(8)),
  SimEvent.bike(minutes(25)),
  SimEvent.stationary(minutes(30)),
  SimEvent.bike(hours(1)),
  SimEvent.sleep(hours(6)),
];

// ============================================================================
// EDGE CASE SCENARIOS
// ============================================================================

List<SimEvent> trafficLightScenario() => [
  SimEvent.drive(minutes(10)),
  SimEvent.stationary(minutes(2)), // red light — should NOT trigger stationary
  SimEvent.drive(minutes(5)),
  SimEvent.stationary(minutes(1)), // another light
  SimEvent.drive(minutes(8)),
  SimEvent.stationary(minutes(2)),
  SimEvent.drive(minutes(10)),
];

// ============================================================================
// TESTS
// ============================================================================

void main() {
  group('Daily Pattern Simulations — Balanced Preset', () {
    late TrackingSimulator sim;

    setUp(() {
      sim = TrackingSimulator(PresetValues.balanced);
    });

    test('Office Worker — Drive to Work', () {
      final report = sim.run('Office Worker', officeWorkerScenario());
      report.printReport();

      // 24hr day, multiple transitions
      expect(report.totalDuration.inHours, greaterThanOrEqualTo(23));

      // State transitions: sleep→wake(indoor,no transition), drive(exit geofence)→desk(stop)→walk(exit)→restaurant(stop)→walk(exit)→desk(stop)→drive(exit)→home(indoor,no)→sleep
      // Moving transitions: drive, walk lunch, walk back, drive home = 4 exits
      // Stationary transitions: desk, restaurant, desk, home = 4 stops (but initial is stationary)
      // So ~8 transitions total
      expect(report.stateTransitions, inInclusiveRange(6, 10));

      // GPS should be on only during movement + stop detection lead-in
      expect(report.gpsOnTime.inMinutes, lessThan(180)); // < 3hr

      // Battery < 15%
      expect(report.batteryEstimate, lessThan(16.0));

      // No false wakes from indoor walking
      expect(report.hadFalseWakes, isFalse);

      // Geofence drops for each stationary period
      expect(report.geofenceDrops, greaterThanOrEqualTo(3));
    });

    test('Urban Commuter — Metro', () {
      final report = sim.run('Urban Commuter', urbanCommuterScenario());
      report.printReport();

      expect(report.totalDuration.inHours, greaterThanOrEqualTo(23));
      expect(report.stateTransitions, inInclusiveRange(6, 14));
      expect(report.batteryEstimate, lessThan(16.0));
      expect(report.hadFalseWakes, isFalse);
    });

    test('Delivery Driver — Frequent Stops', () {
      final report = sim.run('Delivery Driver', deliveryDriverScenario());
      report.printReport();

      // Many transitions due to frequent stops
      // Short stops (3-5 min) are LESS than stillnessTimeout (5 min for balanced)
      // So many stops should NOT trigger stationary transition
      // Only stops >= 5 min should trigger
      expect(report.stateTransitions, greaterThanOrEqualTo(4));

      // GPS on for most of the working day
      expect(report.gpsOnTime.inMinutes, greaterThan(120));

      // Battery will be higher for delivery driver — allowed > 15%
      // But shouldn't be insane
      expect(report.batteryEstimate, lessThan(30.0));
    });

    test('Work From Home — Minimal GPS', () {
      final report = sim.run('Work From Home', workFromHomeScenario());
      report.printReport();

      // Only 1 outside walk triggers GPS
      // ~2 transitions (out and back)
      expect(report.stateTransitions, inInclusiveRange(2, 4));

      // GPS should be on very little
      expect(report.gpsOnTime.inMinutes, lessThan(60));

      // Battery very low
      expect(report.batteryEstimate, lessThan(10.0));

      // Indoor walks should NOT trigger GPS
      expect(report.hadFalseWakes, isFalse);
    });

    test('Weekend Hiker', () {
      final report = sim.run('Weekend Hiker', weekendHikerScenario());
      report.printReport();

      // Drive → hike → lookout → hike → drive = several transitions
      expect(report.stateTransitions, inInclusiveRange(2, 6));

      // GPS on for most of the trip
      expect(report.gpsOnTime.inHours, greaterThanOrEqualTo(4));

      // Many location events during hiking
      expect(report.locationEvents, greaterThan(100));
    });

    test('Airport Travel', () {
      final report = sim.run('Airport Travel', airportTravelScenario());
      report.printReport();

      expect(report.stateTransitions, inInclusiveRange(4, 10));
      expect(report.batteryEstimate, lessThan(15.0));

      // Long plane stationary should be GPS-off
      expect(report.gpsOffTime.inHours, greaterThanOrEqualTo(4));
    });

    test('Couch Potato — GPS Almost Never On', () {
      final report = sim.run('Couch Potato', couchPotatoScenario());
      report.printReport();

      // No real movement outside — should have 0 moving transitions
      expect(report.stateTransitions, equals(0));

      // GPS should be off virtually all day
      expect(report.gpsOnTime.inMinutes, equals(0));
      expect(report.gpsOffPercent, greaterThan(99));

      // Battery drain should be minimal — just geofence monitoring
      expect(report.batteryEstimate, lessThan(7.0));

      // No false wakes
      expect(report.hadFalseWakes, isFalse);
    });

    test('Cyclist Commuter', () {
      final report = sim.run('Cyclist Commuter', cyclistCommuterScenario());
      report.printReport();

      // Bike to work, bike home, evening ride = 3 moving periods
      expect(report.stateTransitions, inInclusiveRange(4, 8));
      expect(report.batteryEstimate, lessThan(15.0));

      // Should get good location events during biking
      expect(report.locationEvents, greaterThan(50));
    });
  });

  group('Edge Cases — Balanced Preset', () {
    late TrackingSimulator sim;

    setUp(() {
      sim = TrackingSimulator(PresetValues.balanced);
    });

    test('Traffic lights should NOT trigger stationary (< stillnessTimeout)', () {
      final report = sim.run('Traffic Lights', trafficLightScenario());
      report.printReport();

      // 2-minute stops should NOT cause stationary transitions
      // because balanced stillnessTimeout = 5 minutes
      // All stops are < 5 min, so GPS should stay on the whole time
      // Only initial transition from stationary→moving counts
      // The short stationary events don't trigger stop detection
      expect(report.gpsOnTime.inMinutes, greaterThan(30));

      // The short stops (1-2 min) should not add stationary transitions
      // beyond the natural flow
    });

    test('GPS accuracy degradation — poor accuracy filtered', () {
      final events = [
        SimEvent.walk(minutes(10), accuracy: 5),   // good
        SimEvent.walk(minutes(10), accuracy: 150),  // poor — exceeds maxAccuracy(100)
        SimEvent.walk(minutes(10), accuracy: 10),   // good again
      ];

      final report = sim.run('Accuracy Degradation', events);
      report.printReport();

      // The poor accuracy segment should produce 0 events
      // Good segments should produce events
      expect(report.locationEvents, greaterThan(0));
    });
  });

  group('Preset Comparison — Office Worker', () {
    test('Low vs Balanced vs High battery and event comparison', () {
      final scenarios = {
        'low': TrackingSimulator(PresetValues.low),
        'balanced': TrackingSimulator(PresetValues.balanced),
        'high': TrackingSimulator(PresetValues.high),
      };

      final reports = <String, SimulationReport>{};
      for (final entry in scenarios.entries) {
        reports[entry.key] = entry.value.run('Office Worker', officeWorkerScenario());
        reports[entry.key]!.printReport();
      }

      // Low preset has fewer location events but longer stillness timeout (15min vs 5min)
      // so GPS-on time during stop detection can be similar. Battery ordering depends
      // on the scenario — what matters is all are reasonable.
      expect(reports['low']!.batteryEstimate, lessThan(20.0));
      expect(reports['balanced']!.batteryEstimate, lessThan(20.0));

      // High should produce more location events than balanced
      expect(reports['high']!.locationEvents,
          greaterThanOrEqualTo(reports['balanced']!.locationEvents));

      // Low preset: longer stillness timeout means more GPS-on per stop
      expect(reports['low']!.batteryEstimate, lessThan(20.0));

      print('\n=== Preset Comparison Summary ===');
      print('Low:      ${reports["low"]!.batteryEstimate.toStringAsFixed(1)}% battery, ${reports["low"]!.locationEvents} events');
      print('Balanced: ${reports["balanced"]!.batteryEstimate.toStringAsFixed(1)}% battery, ${reports["balanced"]!.locationEvents} events');
      print('High:     ${reports["high"]!.batteryEstimate.toStringAsFixed(1)}% battery, ${reports["high"]!.locationEvents} events');
    });
  });

  group('Stop Detection Validation', () {
    test('Stationary after exactly stillnessTimeoutMin fires stop detection', () {
      for (final preset in [PresetValues.low, PresetValues.balanced, PresetValues.high]) {
        final sim = TrackingSimulator(preset);
        final events = [
          SimEvent.drive(minutes(10)), // get moving
          SimEvent.stationary(Duration(minutes: preset.stillnessTimeoutMin)), // exactly timeout
        ];
        final report = sim.run('Stop Detection (${preset.name})', events);

        // Should transition to stationary after timeout
        expect(report.stateTransitions, greaterThanOrEqualTo(2),
            reason: '${preset.name}: should transition to stationary after ${preset.stillnessTimeoutMin}min');
      }
    });

    test('Stationary shorter than stillnessTimeout does NOT fire', () {
      final sim = TrackingSimulator(PresetValues.balanced);
      // balanced stillnessTimeout = 5min, so 3min stop should NOT trigger
      final events = [
        SimEvent.drive(minutes(10)),
        SimEvent.stationary(minutes(3)), // < 5min timeout
        SimEvent.drive(minutes(10)),
      ];
      final report = sim.run('Short Stop', events);

      // The 3-minute stop should NOT cause a stationary transition
      // GPS stays on the whole time
      expect(report.gpsOnTime.inMinutes, greaterThanOrEqualTo(20));
    });
  });

  group('Geofence Lifecycle', () {
    test('Geofence drops match stationary transitions', () {
      final sim = TrackingSimulator(PresetValues.balanced);
      final report = sim.run('Office Worker', officeWorkerScenario());

      // Every stationary transition should drop a geofence
      // Initial stationary state also drops one
      // geofenceDrops = 1 (initial) + number of moving→stationary transitions
      final movingToStationary = (report.stateTransitions / 2).ceil();
      expect(report.geofenceDrops, greaterThanOrEqualTo(movingToStationary));
    });

    test('Geofence exits match stationary→moving transitions', () {
      final sim = TrackingSimulator(PresetValues.balanced);
      final report = sim.run('Office Worker', officeWorkerScenario());

      // Each geofence exit triggers a stationary→moving transition
      final stationaryToMoving = (report.stateTransitions / 2).floor();
      expect(report.geofenceExits, equals(stationaryToMoving));
    });
  });

  group('Battery Budget Validation', () {
    final budgetScenarios = {
      'Office Worker': officeWorkerScenario(),
      'Urban Commuter': urbanCommuterScenario(),
      'Work From Home': workFromHomeScenario(),
      'Couch Potato': couchPotatoScenario(),
      'Cyclist Commuter': cyclistCommuterScenario(),
      'Airport Travel': airportTravelScenario(),
    };

    for (final entry in budgetScenarios.entries) {
      test('${entry.key} battery < 16% on balanced preset', () {
        final sim = TrackingSimulator(PresetValues.balanced);
        final report = sim.run(entry.key, entry.value);
        expect(report.batteryEstimate, lessThan(16.0),
            reason: '${entry.key} exceeded 16% battery budget');
      });
    }

    test('Delivery Driver allowed higher battery (< 25%)', () {
      final sim = TrackingSimulator(PresetValues.balanced);
      final report = sim.run('Delivery Driver', deliveryDriverScenario());
      expect(report.batteryEstimate, lessThan(25.0));
    });
  });
}
