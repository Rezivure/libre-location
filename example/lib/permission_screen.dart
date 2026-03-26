import 'dart:async';
import 'package:flutter/material.dart';
import 'package:libre_location/libre_location.dart';

/// Demonstrates the full permission flow:
/// check → request → upgrade to always → deep link to settings
class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  LocationPermission _permission = LocationPermission.denied;
  bool _serviceEnabled = false;
  bool _showRationale = false;
  StreamSubscription<LocationPermission>? _permSub;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _permSub = LibreLocation.onPermissionChange.listen((perm) {
      _addLog('Permission changed → ${perm.name}');
      setState(() => _permission = perm);
    });
  }

  @override
  void dispose() {
    _permSub?.cancel();
    super.dispose();
  }

  void _addLog(String msg) {
    setState(() {
      _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} $msg');
      if (_log.length > 50) _log.removeLast();
    });
  }

  Future<void> _refresh() async {
    final perm = await LibreLocation.checkPermission();
    final svc = await LibreLocation.isLocationServiceEnabled();
    final rationale = await LibreLocation.shouldShowRequestRationale();
    setState(() {
      _permission = perm;
      _serviceEnabled = svc;
      _showRationale = rationale;
    });
    _addLog('Refreshed: perm=${perm.name}, svc=$svc, rationale=$rationale');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permission Flow')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Permission: ${_permission.name}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Location services: ${_serviceEnabled ? "ON" : "OFF"}'),
                  Text('Should show rationale: $_showRationale'),
                  const SizedBox(height: 8),
                  _permissionIcon(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Actions
          ElevatedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Status'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              _addLog('Requesting permission...');
              final result = await LibreLocation.requestPermission();
              _addLog('requestPermission → ${result.name}');
              _refresh();
            },
            icon: const Icon(Icons.location_on),
            label: const Text('Request Permission (When In Use)'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              _addLog('Requesting Always permission...');
              final result = await LibreLocation.requestAlwaysPermission();
              _addLog('requestAlwaysPermission → ${result.name}');
              _refresh();
            },
            icon: const Icon(Icons.location_on_outlined),
            label: const Text('Request Always Permission'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              _addLog('Opening app settings...');
              await LibreLocation.openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open App Settings'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              _addLog('Opening location settings...');
              await LibreLocation.openLocationSettings();
            },
            icon: const Icon(Icons.gps_fixed),
            label: const Text('Open Location Settings'),
          ),
          const SizedBox(height: 16),

          // Recommended flow
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recommended Flow',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_recommendedAction()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Log
          const Text('Event Log', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._log.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              )),
        ],
      ),
    );
  }

  Widget _permissionIcon() {
    switch (_permission) {
      case LocationPermission.denied:
        return const Row(children: [
          Icon(Icons.close, color: Colors.red),
          SizedBox(width: 8),
          Text('Not granted — tap "Request Permission"'),
        ]);
      case LocationPermission.deniedForever:
        return const Row(children: [
          Icon(Icons.block, color: Colors.red),
          SizedBox(width: 8),
          Text('Permanently denied — open Settings'),
        ]);
      case LocationPermission.whileInUse:
        return const Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.orange),
          SizedBox(width: 8),
          Text('When In Use — upgrade to Always'),
        ]);
      case LocationPermission.always:
        return const Row(children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('Always — full background access'),
        ]);
    }
  }

  String _recommendedAction() {
    if (!_serviceEnabled) {
      return '1. Location services are OFF. Tap "Open Location Settings" to enable GPS.';
    }
    switch (_permission) {
      case LocationPermission.denied:
        if (_showRationale) {
          return '1. User previously denied. Show explanation, then tap "Request Permission".';
        }
        return '1. Tap "Request Permission" to ask for When In Use access.';
      case LocationPermission.deniedForever:
        return '1. Permission permanently denied. Tap "Open App Settings" and enable location manually.';
      case LocationPermission.whileInUse:
        return '1. You have When In Use. Tap "Request Always Permission" for background access.';
      case LocationPermission.always:
        return '✅ All set! You have full background location access.';
    }
  }
}
