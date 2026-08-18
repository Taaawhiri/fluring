import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ring_exceptions.dart';
import 'token_store.dart';

/// Holds an OAuth session against Ring's private auth server.
///
/// The flow mirrors what the official Android app does:
///   1. password grant, with the `2fa-support` header set;
///   2. Ring answers 412 asking for a code, which we surface as
///      [RingTwoFactorRequired];
///   3. the same call is repeated with the `2fa-code` header;
///   4. the resulting refresh token is persisted, and from then on every
///      launch renews silently.
///
/// The hardware id must stay stable across launches — Ring treats a new id as
/// a new device and re-triggers two-factor, which would defeat the whole point
/// of persisting the token on a TV the user rarely types on.
class RingAuth {
  RingAuth({
    required TokenStore store,
    http.Client? httpClient,
  })  : _store = store, // ignore: prefer_initializing_formals
        _http = httpClient ?? http.Client();

  static const _oauthUrl = 'https://oauth.ring.com/oauth/token';
  static const _clientId = 'ring_official_android';

  final TokenStore _store;
  final http.Client _http;

  String? _accessToken;
  DateTime? _expiresAt;

  /// True once we hold a refresh token, whether or not it still works.
  Future<bool> get hasSession async => await _store.readRefreshToken() != null;

  /// A valid bearer token, renewing it when it is about to lapse.
  ///
  /// Renewal starts a minute before the real deadline so a stream that is being
  /// set up right on the boundary does not fail midway.
  Future<String> accessToken() async {
    final token = _accessToken;
    final expiry = _expiresAt;
    if (token != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry.subtract(const Duration(minutes: 1)))) {
      return token;
    }
    return _refresh();
  }

  /// Headers Ring expects on every authenticated call.
  Future<Map<String, String>> authHeaders() async {
    return {
      'Authorization': 'Bearer ${await accessToken()}',
      'User-Agent': 'android:com.ringapp',
      'hardware_id': await _store.hardwareId(),
    };
  }

  /// Logs in with email and password.
  ///
  /// Throws [RingTwoFactorRequired] when Ring wants a code; call
  /// [submitTwoFactorCode] with the same credentials to finish.
  Future<void> logIn({
    required String email,
    required String password,
    String? twoFactorCode,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'android:com.ringapp',
      'hardware_id': await _store.hardwareId(),
      '2fa-support': 'true',
    };
    if (twoFactorCode != null) {
      headers['2fa-code'] = twoFactorCode;
    }

    final response = await _http.post(
      Uri.parse(_oauthUrl),
      headers: headers,
      body: jsonEncode({
        'client_id': _clientId,
        'grant_type': 'password',
        'scope': 'client',
        'username': email,
        'password': password,
      }),
    );

    if (response.statusCode == 412 || _needsTwoFactor(response)) {
      final body = _decode(response);
      throw RingTwoFactorRequired(
        phone: body['phone'] as String?,
        tsvState: body['tsv_state'] as String?,
      );
    }
    if (response.statusCode == 401 || response.statusCode == 400) {
      throw RingAuthException(_errorMessage(response));
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw RingException('Login failed (HTTP ${response.statusCode})');
    }

    await _adopt(_decode(response));
  }

  /// Finishes a login that Ring interrupted with a two-factor challenge.
  Future<void> submitTwoFactorCode({
    required String email,
    required String password,
    required String code,
  }) {
    return logIn(email: email, password: password, twoFactorCode: code.trim());
  }

  /// Drops the stored session. The hardware id survives on purpose, so logging
  /// back in on the same TV does not look like a brand new device.
  Future<void> logOut() async {
    _accessToken = null;
    _expiresAt = null;
    await _store.clearRefreshToken();
  }

  Future<String> _refresh() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null) {
      throw const RingSessionExpired();
    }

    final response = await _http.post(
      Uri.parse(_oauthUrl),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'android:com.ringapp',
        'hardware_id': await _store.hardwareId(),
        '2fa-support': 'true',
      },
      body: jsonEncode({
        'client_id': _clientId,
        'grant_type': 'refresh_token',
        'scope': 'client',
        'refresh_token': refreshToken,
      }),
    );

    // A refresh token that Ring no longer honours is not a transient failure:
    // clear it so the app asks for a fresh login instead of retrying forever.
    if (response.statusCode == 401 || response.statusCode == 400) {
      await _store.clearRefreshToken();
      throw const RingSessionExpired();
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw RingException('Token refresh failed (HTTP ${response.statusCode})');
    }

    await _adopt(_decode(response));
    return _accessToken!;
  }

  Future<void> _adopt(Map<String, dynamic> body) async {
    final access = body['access_token'] as String?;
    final refresh = body['refresh_token'] as String?;
    if (access == null) {
      throw const RingException('Ring returned no access token');
    }

    _accessToken = access;
    final lifetime = (body['expires_in'] as num?)?.toInt() ?? 3600;
    _expiresAt = DateTime.now().add(Duration(seconds: lifetime));

    if (refresh != null) {
      await _store.writeRefreshToken(refresh);
    }
  }

  bool _needsTwoFactor(http.Response response) {
    if (response.statusCode != 400) return false;
    final body = _decode(response);
    return body['error'] == 'Verification Code is required' ||
        body.containsKey('tsv_state');
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  String _errorMessage(http.Response response) {
    final body = _decode(response);
    final description = body['error_description'] ?? body['error'];
    return description is String && description.isNotEmpty
        ? description
        : 'Email or password not accepted';
  }

  void dispose() => _http.close();
}
