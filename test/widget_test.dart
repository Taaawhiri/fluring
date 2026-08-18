import 'package:flutter_test/flutter_test.dart';

import 'package:fluring/src/ring/models.dart';

void main() {
  group('RingCamera', () {
    test('reads a stickup cam', () {
      final camera = RingCamera.fromJson(
        {'id': 42, 'description': 'Garden', 'kind': 'stickup_cam_v4',
         'battery_life': 88},
        isDoorbell: false,
      );

      expect(camera.id, 42);
      expect(camera.description, 'Garden');
      expect(camera.batteryLife, 88);
      expect(camera.isDoorbell, isFalse);
    });

    test('accepts battery reported as a string', () {
      // Older devices send the level as a numeric string.
      final camera = RingCamera.fromJson(
        {'id': 1, 'battery_life': '73'},
        isDoorbell: true,
      );

      expect(camera.batteryLife, 73);
    });

    test('leaves battery null for mains-powered cameras', () {
      final camera = RingCamera.fromJson({'id': 2}, isDoorbell: false);

      expect(camera.batteryLife, isNull);
    });

    test('falls back to the id when Ring sends no description', () {
      final camera = RingCamera.fromJson(
        {'id': 7, 'description': '   '},
        isDoorbell: false,
      );

      expect(camera.description, 'Camera 7');
    });
  });
}
