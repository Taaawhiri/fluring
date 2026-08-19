import 'package:flutter/services.dart';

/// Whether this device is Android TV/Google TV firmware, as opposed to a
/// phone or tablet running the same APK.
///
/// The two need different UIs: a TV has no comfortable keyboard and only a
/// D-pad, so it gets the QR-code login and a landscape-only lock; a phone has
/// both a touch keyboard and a natural portrait orientation, so it gets the
/// plain email/password form and free rotation. Detection goes through
/// Android's own `UiModeManager` on the native side — the platform's own
/// signal, not a screen-size or DPI guess that would misfire on a large
/// tablet or a small TV stick.
class DeviceFormFactor {
  DeviceFormFactor._();

  static const _channel = MethodChannel('fluring/platform');

  static bool? _cached;

  static Future<bool> isTelevision() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final result = await _channel.invokeMethod<bool>('isTelevision');
      final isTv = result ?? false;
      _cached = isTv;
      return isTv;
    } on PlatformException {
      // Fail toward the more capable UI: a keyboard-and-touch form still
      // works on a TV, whereas a QR flow would strand someone on a phone.
      return false;
    }
  }
}
