import 'dart:async';
import 'package:flutter/material.dart';
import 'package:libre_location/libre_location.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Libre Location Example',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const LocationPage(),
    );
  }
}

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  Position? _currentPosition;
  bool _isTracking = false;
  LocationPermission _permission = LocationPermission.denied;
  final List<String> _log = [];

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Position>? _motionSub;
  StreamSubscription<ActivityEvent>? _activitySub;
  StreamSubscription<ProviderEvent>? _providerSub;
  StreamSubscription<HeartbeatEvent>? _heartbeatSub;
  StreamSubscription<GeofenceEvent>? _geofenceSub;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  void _cancelAll() {
    _positionSub?.cancel();
    _motionSub?.cancel();
    _activitySub?.cancel();
    _providerSub?.cancel();
    _heartbeatSub?.cancel();
    _geofenceSub?.cancel();
  }

  void _addLog(String msg) {
    setState(() {
      _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} $msg');
      if (_log.length > 100) _log.removeLast();
    });
  }

  Future<void> _checkPermission() async {
    final p = await LibreLocation.checkPermission();
    setState(() => _permission = p);
    _addLog('Permission: ${p.name}');
  }

  Future<void> _requestPermission() async {
    final p = await LibreLocation.requestPermission();
    setState(() => _permission = p);
    _addLog('Permission granted: ${p.name}');
  }

  Future<void> _getCurrentPosition() async {
    _addLog('Requesting position...');
    try {
      final pos = await LibreLocation.getCurrentPosition(
        accuracy: Accuracy.high, samples: 3, timeout: 30,
      );
      setState(() => _currentPosition = pos);
      _addLog('Position: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
    } catch (e) {
      _addLog('Error: $e');
    }
  }

  void _subscribeAll() {
    _positionSub = LibreLocation.positionStream.listen((pos) {
      setState(() => _currentPosition = pos);
      _addLog('Location: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)} (${pos.accuracy.toStringAsFixed(0)}m)');
    });
    _motionSub = LibreLocation.motionChangeStream.listen((pos) {
      _addLog('Motion: ${pos.isMoving ? "MOVING" : "STATIONARY"}');
    });
    _activitySub = LibreLocation.activityChangeStream.listen((e) {
      _addLog('Activity: ${e.activity} (${e.confidence}%)');
    });
    _providerSub = LibreLocation.providerChangeStream.listen((e) {
      _addLog('Provider: enabled=${e.enabled}, gps=${e.gps}');
    });
    _heartbeatSub = LibreLocation.heartbeatStream.listen((e) {
      _addLog('Heartbeat: ${e.position.latitude.toStringAsFixed(4)}, ${e.position.longitude.toStringAsFixed(4)}');
    });
    _geofenceSub = LibreLocation.geofenceStream.listen((e) {
      _addLog('Geofence: ${e.geofence.id} ${e.transition.name}');
    });
  }

  Future<void> _startTracking() async {
    const config = LocationConfig(
      accuracy: Accuracy.high,
      distanceFilter: 10.0,
      stopOnTerminate: false,
      startOnBoot: true,
      enableHeadless: true,
      heartbeatInterval: 60,
      debug: true,
      logLevel: LogLevel.info,
      notification: NotificationConfig(
        title: 'Libre Location Demo',
        text: 'Tracking location',
        sticky: true,
      ),
      backgroundPermissionRationale: PermissionRationale(
        title: 'Background Location',
        message: 'This app needs background location for tracking.',
      ),
      locationAuthorizationRequest: LocationAuthorizationRequest.always,
    );
    await LibreLocation.startTracking(config);
    _subscribeAll();
    setState(() => _isTracking = true);
    _addLog('Tracking started');
  }

  Future<void> _stopTracking() async {
    await LibreLocation.stopTracking();
    _cancelAll();
    setState(() => _isTracking = false);
    _addLog('Tracking stopped');
  }

  Future<void> _updateConfig() async {
    const config = LocationConfig(
      accuracy: Accuracy.navigation,
      distanceFilter: 5.0,
      heartbeatInterval: 30,
    );
    await LibreLocation.setConfig(config);
    _addLog('Config updated');
  }

  Future<void> _addGeofence() async {
    if (_currentPosition == null) { _addLog('Get position first'); return; }
    final g = Geofence(
      id: 'test_geofence',
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      radiusMeters: 100.0,
      triggers: const {GeofenceTransition.enter, GeofenceTransition.exit, GeofenceTransition.dwell},
      dwellDuration: const Duration(minutes: 1),
    );
    await LibreLocation.addGeofence(g);
    _addLog('Geofence added (100m)');
  }

  Future<void> _removeGeofence() async {
    await LibreLocation.removeGeofence('test_geofence');
    _addLog('Geofence removed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Libre Location')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(_permission == LocationPermission.always ? Icons.check_circle : Icons.warning,
                    color: _permission == LocationPermission.always ? Colors.green : Colors.orange),
                  const SizedBox(width: 8),
                  Text('Permission: ${_permission.name}'),
                  const Spacer(),
                  if (_permission == LocationPermission.denied)
                    TextButton(onPressed: _requestPermission, child: const Text('Request')),
                ]),
              ),
            ),
            if (_currentPosition != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.titleMedium),
                    Text('Acc: ${_currentPosition!.accuracy.toStringAsFixed(1)}m | Speed: ${_currentPosition!.speed.toStringAsFixed(1)} m/s | Moving: ${_currentPosition!.isMoving}'),
                    if (_currentPosition!.activity != null)
                      Text('Activity: ${_currentPosition!.activity!.activity} (${_currentPosition!.activity!.confidence}%)'),
                    if (_currentPosition!.battery != null)
                      Text('Battery: ${(_currentPosition!.battery!.level * 100).toStringAsFixed(0)}%${_currentPosition!.battery!.isCharging ? " charging" : ""}'),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(onPressed: _getCurrentPosition, icon: const Icon(Icons.my_location), label: const Text('Get Position')),
              ElevatedButton.icon(
                onPressed: _isTracking ? _stopTracking : _startTracking,
                icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                label: Text(_isTracking ? 'Stop' : 'Start'),
                style: ElevatedButton.styleFrom(backgroundColor: _isTracking ? Colors.red.shade100 : null),
              ),
              if (_isTracking) OutlinedButton(onPressed: _updateConfig, child: const Text('Update Config')),
              OutlinedButton(onPressed: _addGeofence, child: const Text('+ Fence')),
              OutlinedButton(onPressed: _removeGeofence, child: const Text('- Fence')),
            ]),
            const SizedBox(height: 12),
            Text('Event Log', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(_log[i], style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
