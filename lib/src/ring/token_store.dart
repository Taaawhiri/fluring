import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Ring refresh token and the device's hardware id.
///
/// Both values are long-lived by design: the refresh token is what spares the
/// user from typing an email, a password and a 2FA code on a TV remote at every
/// launch, and the hardware id is what stops Ring from treating each launch as
/// a new device (which would re-trigger 2FA).
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshTokenKey = 'ring_refresh_token';
  static const _hardwareIdKey = 'ring_hardware_id';

  final FlutterSecureStorage _storage;

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<void> clearRefreshToken() => _storage.delete(key: _refreshTokenKey);

  /// The stable per-installation id, generated once on first launch.
  Future<String> hardwareId() async {
    final existing = await _storage.read(key: _hardwareIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _randomUuidV4();
    await _storage.write(key: _hardwareIdKey, value: generated);
    return generated;
  }

  String _randomUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
