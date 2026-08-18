import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'ring_auth.dart';
import 'ring_exceptions.dart';

/// Reads devices and snapshots from Ring's private client API.
///
/// Snapshots are the app's backbone: they are a plain authenticated JPEG GET,
/// far more forgiving than the live WebRTC path, so the grid stays useful even
/// when streaming misbehaves on a weak TV chipset.
class RingClient {
  RingClient({required RingAuth auth, http.Client? httpClient})
      : _auth = auth, // ignore: prefer_initializing_formals
        _http = httpClient ?? http.Client();

  static const _base = 'https://api.ring.com/clients_api';

  final RingAuth _auth;
  final http.Client _http;

  /// Every camera and doorbell on the account.
  Future<List<RingCamera>> cameras() async {
    final response = await _http.get(
      Uri.parse('$_base/ring_devices'),
      headers: await _auth.authHeaders(),
    );

    if (response.statusCode == 401) throw const RingSessionExpired();
    if (response.statusCode != 200) {
      throw RingException('Could not load devices (HTTP ${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return [
      ..._camerasUnder(body, 'doorbots', isDoorbell: true),
      ..._camerasUnder(body, 'authorized_doorbots', isDoorbell: true),
      ..._camerasUnder(body, 'stickup_cams', isDoorbell: false),
    ];
  }

  /// The latest still image Ring holds for [cameraId].
  ///
  /// Ring answers 404 while a battery camera is still waking up and has no
  /// snapshot yet; that is an ordinary state, not an error, so it comes back as
  /// null and the tile keeps its previous frame.
  Future<Uint8List?> snapshot(int cameraId) async {
    final response = await _http.get(
      Uri.parse('$_base/snapshots/image/$cameraId'),
      headers: await _auth.authHeaders(),
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode == 401) throw const RingSessionExpired();
    if (response.statusCode != 200) {
      throw RingException('Snapshot failed (HTTP ${response.statusCode})');
    }
    if (response.bodyBytes.isEmpty) return null;
    return response.bodyBytes;
  }

  /// Asks Ring to capture a fresh frame.
  ///
  /// Best-effort: battery cameras often decline to wake on demand, and the grid
  /// is expected to fall back to whatever snapshot already exists.
  Future<void> requestFreshSnapshot(int cameraId) async {
    final headers = await _auth.authHeaders();
    headers['Content-Type'] = 'application/json';
    await _http.put(
      Uri.parse('$_base/doorbots/$cameraId/snapshot'),
      headers: headers,
      body: jsonEncode({'doorbot_id': cameraId}),
    );
  }

  List<RingCamera> _camerasUnder(
    Map<String, dynamic> body,
    String key, {
    required bool isDoorbell,
  }) {
    final raw = body[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .where((json) => json['id'] is num)
        .map((json) => RingCamera.fromJson(json, isDoorbell: isDoorbell))
        .toList();
  }

  void dispose() => _http.close();
}
