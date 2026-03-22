import 'dart:async';
import 'package:flutter/material.dart';
import 'package:libre_location/libre_location.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Libre Location Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
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
  StreamSubscription<Position>? _positionSub;
  final List<Position> _positions = [];

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final perm = await LibreLocation.checkPermission();
    setState(() => _permission = perm);
  }

  Future<void> _requestPermission() async {
    final perm = await LibreLocation.requestPermission();
    setState(() => _permission = perm);
  }

  Future<void> _getCurrentPosition() async {
    final pos = await LibreLocation.getCurrentPosition();
    setState(() => _currentPosition = pos);
  }

  Future<void> _startTracking() async {
    await LibreLocation.startTracking(const LocationConfig(
      accuracy: Accuracy.high,
      mode: TrackingMode.balanced,
      intervalMs: 30000,
      distanceFilter: 5.0,
      enableMotionDetection: true,
      notificationTitle: 'Libre Location Demo',
      notificationBody: 'Tracking your location',
    ));

    _positionSub = LibreLocation.positionStream.listen((pos) {
      setState(() {
        _currentPosition = pos;
        _positions.add(pos);
      });
    });

    setState(() => _isTracking = true);
  }

  Future<void> _stopTracking() async {
    await LibreLocation.stopTracking();
    _positionSub?.cancel();
    setState(() => _isTracking = false);
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Permission: ${_permission.name}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_permission == LocationPermission.denied)
                      ElevatedButton(
                        onPressed: _requestPermission,
                        child: const Text('Request Permission'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _getCurrentPosition,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Get Position'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTracking ? _stopTracking : _startTracking,
                    icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                    label: Text(_isTracking ? 'Stop' : 'Start Tracking'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isTracking ? Colors.red.shade100 : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_currentPosition != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Position',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}'),
                      Text('Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}'),
                      Text('Alt: ${_currentPosition!.altitude.toStringAsFixed(1)}m'),
                      Text('Accuracy: ${_currentPosition!.accuracy.toStringAsFixed(1)}m'),
                      Text('Speed: ${_currentPosition!.speed.toStringAsFixed(1)} m/s'),
                      Text('Provider: ${_currentPosition!.provider}'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Track points: ${_positions.length}',
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
