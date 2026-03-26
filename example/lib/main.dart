import 'dart:async';
import 'package:flutter/material.dart';
import 'package:libre_location/libre_location.dart';
import 'permission_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Libre Location Demo',
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
  // State
  Position? _currentPosition;
  bool _isTracking = false;
  bool _isMoving = false;
  LocationPermission _permission = LocationPermission.denied;
  ActivityEvent? _currentActivity;
  int _heartbeatCount = 0;
  bool _powerSaveEnabled = false;
  TrackingPreset _selectedPreset = TrackingPreset.balanced;
  List<Geofence> _geofences = [];
  final List<String> _logs = [];

  // Subscriptions
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Position>? _motionSub;
  StreamSubscription<ActivityEvent>? _activitySub;
  StreamSubscription<HeartbeatEvent>? _heartbeatSub;
  StreamSubscription<bool>? _powerSaveSub;
  StreamSubscription<GeofenceEvent>? _geofenceSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _checkPermission();
    final tracking = await LibreLocation.isTracking;
    if (tracking) {
      setState(() {
        _isTracking = true;
        _selectedPreset = LibreLocation.currentPreset ?? TrackingPreset.balanced;
      });
      _subscribeAll();
    }
    _loadGeofences();
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
    _heartbeatSub?.cancel();
    _powerSaveSub?.cancel();
    _geofenceSub?.cancel();
  }

  void _subscribeAll() {
    _positionSub = LibreLocation.onLocation.listen((pos) {
      setState(() => _currentPosition = pos);
      _addLog('Position: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} ±${pos.accuracy.toStringAsFixed(0)}m');
    });

    _motionSub = LibreLocation.onMotionChange.listen((pos) {
      setState(() => _isMoving = pos.isMoving);
      _addLog('Motion: ${pos.isMoving ? "MOVING" : "STATIONARY"}');
    });

    _activitySub = LibreLocation.onActivityChange.listen((activity) {
      setState(() => _currentActivity = activity);
      _addLog('Activity: ${activity.activity} (${activity.confidence}%)');
    });

    _heartbeatSub = LibreLocation.onHeartbeat.listen((_) {
      setState(() => _heartbeatCount++);
      _addLog('Heartbeat #$_heartbeatCount');
    });

    _powerSaveSub = LibreLocation.onPowerSaveChange.listen((enabled) {
      setState(() => _powerSaveEnabled = enabled);
      _addLog('Power save: ${enabled ? "ON" : "OFF"}');
    });

    _geofenceSub = LibreLocation.geofenceStream.listen((event) {
      _addLog('Geofence ${event.geofence.id}: ${event.transition}');
    });
  }

  void _addLog(String msg) {
    final time = TimeOfDay.now();
    final entry = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $msg';
    setState(() {
      _logs.insert(0, entry);
      if (_logs.length > 100) _logs.removeLast();
    });
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
    try {
      final pos = await LibreLocation.getCurrentPosition();
      setState(() => _currentPosition = pos);
      _addLog('Got position: ±${pos.accuracy.toStringAsFixed(0)}m');
    } catch (e) {
      _addLog('Error getting position: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  THIS IS THE MAGIC — just one line to start
  // ═══════════════════════════════════════════
  Future<void> _startTracking() async {
    await LibreLocation.start(
      preset: _selectedPreset,
      notification: const NotificationConfig(
        title: 'Libre Location Demo',
        text: 'Tracking your location',
      ),
    );

    _subscribeAll();
    setState(() {
      _isTracking = true;
      _heartbeatCount = 0;
    });
    _addLog('Tracking started (preset: ${_selectedPreset.name})');
  }

  Future<void> _stopTracking() async {
    await LibreLocation.stop();
    _cancelAll();
    setState(() => _isTracking = false);
    _addLog('Tracking stopped');
  }

  Future<void> _switchPreset(TrackingPreset preset) async {
    setState(() => _selectedPreset = preset);
    if (_isTracking) {
      await LibreLocation.setPreset(preset);
      _addLog('Switched preset to ${preset.name}');
    }
  }

  Future<void> _loadGeofences() async {
    try {
      final fences = await LibreLocation.getGeofences();
      setState(() => _geofences = fences);
    } catch (_) {}
  }

  Future<void> _addGeofence() async {
    if (_currentPosition == null) {
      _addLog('Get a position first before adding geofence');
      return;
    }
    final id = 'fence_${DateTime.now().millisecondsSinceEpoch}';
    final geofence = Geofence(
      id: id,
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      radiusMeters: 100,
    );
    await LibreLocation.addGeofence(geofence);
    _addLog('Added geofence: $id');
    _loadGeofences();
  }

  Future<void> _removeGeofence(String id) async {
    await LibreLocation.removeGeofence(id);
    _addLog('Removed geofence: $id');
    _loadGeofences();
  }

  Future<void> _loadLogs() async {
    try {
      final logs = await LibreLocation.getLog();
      for (final log in logs.take(20)) {
        _addLog('[native] ${log['level']}: ${log['message']}');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Libre Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.security),
            tooltip: 'Permission flow',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PermissionScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Load native logs',
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Permission
          _buildCard(
            title: 'Permission',
            trailing: Chip(label: Text(_permission.name)),
            children: [
              if (_permission == LocationPermission.denied ||
                  _permission == LocationPermission.deniedForever)
                FilledButton.tonal(
                  onPressed: _requestPermission,
                  child: const Text('Request Permission'),
                ),
            ],
          ),

          // Preset selector
          _buildCard(
            title: 'Tracking Preset',
            children: [
              SegmentedButton<TrackingPreset>(
                segments: const [
                  ButtonSegment(
                    value: TrackingPreset.low,
                    label: Text('Low'),
                    icon: Icon(Icons.battery_full),
                  ),
                  ButtonSegment(
                    value: TrackingPreset.balanced,
                    label: Text('Balanced'),
                    icon: Icon(Icons.balance),
                  ),
                  ButtonSegment(
                    value: TrackingPreset.high,
                    label: Text('High'),
                    icon: Icon(Icons.gps_fixed),
                  ),
                ],
                selected: {_selectedPreset},
                onSelectionChanged: (selected) => _switchPreset(selected.first),
              ),
              const SizedBox(height: 8),
              Text(
                _presetDescription(_selectedPreset),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),

          // Controls
          _buildCard(
            title: 'Tracking',
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _getCurrentPosition,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Get Position'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _isTracking
                        ? FilledButton.icon(
                            onPressed: _stopTracking,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                              foregroundColor: theme.colorScheme.onError,
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: _startTracking,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start'),
                          ),
                  ),
                ],
              ),
            ],
          ),

          // Position
          if (_currentPosition != null) _buildPositionCard(),

          // Status row
          _buildCard(
            title: 'Status',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(
                    _isMoving ? 'Moving' : 'Stationary',
                    _isMoving ? Icons.directions_walk : Icons.accessibility_new,
                    _isMoving ? Colors.green : Colors.orange,
                  ),
                  if (_currentActivity != null)
                    _statusChip(
                      _activityLabel(_currentActivity!.activity),
                      _activityIcon(_currentActivity!.activity),
                      Colors.blue,
                    ),
                  _statusChip(
                    '♥ $_heartbeatCount',
                    Icons.favorite,
                    Colors.red,
                  ),
                  if (_powerSaveEnabled)
                    _statusChip('Power Save', Icons.battery_saver, Colors.amber),
                  if (LibreLocation.currentPreset != null)
                    _statusChip(
                      'Preset: ${LibreLocation.currentPreset!.name}',
                      Icons.tune,
                      Colors.purple,
                    ),
                ],
              ),
            ],
          ),

          // Geofences
          _buildCard(
            title: 'Geofences (${_geofences.length})',
            trailing: IconButton(
              icon: const Icon(Icons.add_location_alt),
              onPressed: _addGeofence,
              tooltip: 'Add at current position',
            ),
            children: [
              if (_geofences.isEmpty)
                const Text('No geofences. Tap + to add one at current position.',
                    style: TextStyle(color: Colors.grey)),
              for (final fence in _geofences)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on, size: 20),
                  title: Text(fence.id, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${fence.latitude.toStringAsFixed(4)}, ${fence.longitude.toStringAsFixed(4)} r=${fence.radiusMeters.round()}m',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    onPressed: () => _removeGeofence(fence.id),
                  ),
                ),
            ],
          ),

          // Log viewer
          _buildCard(
            title: 'Log (${_logs.length})',
            trailing: TextButton(
              onPressed: () => setState(() => _logs.clear()),
              child: const Text('Clear'),
            ),
            children: [
              SizedBox(
                height: 200,
                child: _logs.isEmpty
                    ? const Center(child: Text('No log entries', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            _logs[i],
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPositionCard() {
    final pos = _currentPosition!;
    return _buildCard(
      title: 'Current Position',
      children: [
        _infoRow('Latitude', pos.latitude.toStringAsFixed(6)),
        _infoRow('Longitude', pos.longitude.toStringAsFixed(6)),
        _infoRow('Altitude', '${pos.altitude.toStringAsFixed(1)} m'),
        _infoRow('Accuracy', '±${pos.accuracy.toStringAsFixed(1)} m'),
        _infoRow('Speed', '${pos.speed.toStringAsFixed(1)} m/s'),
        _infoRow('Heading', '${pos.heading.toStringAsFixed(0)}°'),
        _infoRow('Provider', pos.provider),
        _infoRow('Time', '${pos.timestamp.hour.toString().padLeft(2, '0')}:${pos.timestamp.minute.toString().padLeft(2, '0')}:${pos.timestamp.second.toString().padLeft(2, '0')}'),
      ],
    );
  }

  String _presetDescription(TrackingPreset preset) {
    switch (preset) {
      case TrackingPreset.low:
        return '~1%/day • Significant changes only • ~500m resolution\nFor "I just want friends to know roughly where I am"';
      case TrackingPreset.balanced:
        return '~2-4%/day • Smart motion detection • ~50m resolution\nReliable background tracking for most apps';
      case TrackingPreset.high:
        return '~5-8%/day • Frequent GPS updates • ~10m resolution\nFor navigation, fitness, delivery tracking';
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (trailing != null) trailing,
              ],
            ),
            if (children.isNotEmpty) const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, IconData icon, Color color) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }

  String _activityLabel(String activity) {
    switch (activity) {
      case 'still': return 'Still';
      case 'walking': return 'Walking';
      case 'running': return 'Running';
      case 'in_vehicle': return 'Driving';
      case 'on_bicycle': return 'Cycling';
      case 'on_foot': return 'On Foot';
      default: return activity;
    }
  }

  IconData _activityIcon(String activity) {
    switch (activity) {
      case 'still': return Icons.accessibility_new;
      case 'walking': return Icons.directions_walk;
      case 'running': return Icons.directions_run;
      case 'in_vehicle': return Icons.directions_car;
      case 'on_bicycle': return Icons.directions_bike;
      case 'on_foot': return Icons.directions_walk;
      default: return Icons.help_outline;
    }
  }
}
