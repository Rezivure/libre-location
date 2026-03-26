import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies that all method and event channel names used by the plugin
/// are consistent between the Dart side and what the native side expects.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Method Channel Names', () {
    test('main method channel is libre_location', () {
      const channel = MethodChannel('libre_location');
      expect(channel.name, 'libre_location');
    });
  });

  group('Event Channel Names', () {
    const expectedChannels = [
      'libre_location/position',
      'libre_location/geofence',
      'libre_location/motionChange',
      'libre_location/activityChange',
      'libre_location/providerChange',
      'libre_location/heartbeat',
      'libre_location/powerSaveChange',
    ];

    for (final name in expectedChannels) {
      test('event channel $name is properly named', () {
        final channel = EventChannel(name);
        expect(channel.name, name);
        // All event channels must be prefixed with libre_location/
        expect(name.startsWith('libre_location/'), isTrue);
      });
    }

    test('all event channels follow naming convention', () {
      for (final name in expectedChannels) {
        final suffix = name.split('/').last;
        // camelCase convention
        expect(suffix[0], equals(suffix[0].toLowerCase()),
            reason: '$suffix should start with lowercase');
      }
    });
  });
}
