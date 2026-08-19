import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../ring/ring_auth.dart';
import '../ring/ring_exceptions.dart';

/// Lets the user sign in from their phone instead of typing a Ring password
/// with a TV remote.
///
/// The TV opens an HTTPS server on the home network and shows its address as a
/// QR code; the phone's own browser — and its own keyboard — does the actual
/// form filling. Credentials only ever travel across the LAN, and only as far
/// as this device: there is no cloud relay, no pairing service, nothing to
/// keep running afterwards.
///
/// The certificate is self-signed and baked into the app, the same on every
/// install — there is no certificate authority a LAN-only server could get a
/// trusted certificate from. That means the phone's browser still shows a
/// "connection is not private" warning to click through: the point of this
/// certificate isn't to prove identity, it's to encrypt the hop so a passive
/// listener on the Wi-Fi can't read the password off the wire in the clear.
/// The server binds only for the few minutes login takes and shuts itself
/// down the moment it succeeds.
class LoginServer {
  LoginServer({required RingAuth auth}) : _auth = auth; // ignore: prefer_initializing_formals

  final RingAuth _auth;

  HttpServer? _server;
  final _signedIn = Completer<void>();

  /// Pending credentials, kept only long enough to retry with a 2FA code.
  String? _pendingEmail;
  String? _pendingPassword;
  RingTwoFactorRequired? _pendingChallenge;

  /// Completes once a login submitted through the page has succeeded.
  Future<void> get signedIn => _signedIn.future;

  /// Starts the server and returns the URL to encode as a QR code, or null if
  /// no usable LAN address could be found — e.g. Ethernet-only setups where
  /// Android sometimes fails to report an address this way.
  Future<Uri?> start() async {
    final address = await _lanAddress();
    if (address == null) return null;

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_route);

    final context = await _certificateContext();
    final server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      0,
      context,
    );
    _server = server;
    shelf_io.serveRequests(server, handler);

    return Uri(scheme: 'https', host: address, port: server.port);
  }

  Future<SecurityContext> _certificateContext() async {
    final cert = await rootBundle.load('assets/tls/cert.pem');
    final key = await rootBundle.load('assets/tls/key.pem');
    return SecurityContext()
      ..useCertificateChainBytes(cert.buffer.asUint8List())
      ..usePrivateKeyBytes(key.buffer.asUint8List());
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }

  Future<Response> _route(Request request) async {
    if (request.method == 'GET' && request.url.path.isEmpty) {
      return _htmlResponse(_renderPage());
    }
    if (request.method == 'POST' && request.url.path == 'login') {
      return _handleSubmit(request);
    }
    return Response.notFound('Not found');
  }

  Future<Response> _handleSubmit(Request request) async {
    final body = await request.readAsString();
    final form = Uri.splitQueryString(body);
    final code = form['code']?.trim();

    // A 2FA code posted back reuses the credentials from the first attempt;
    // nothing else on this page persists between requests.
    final email = (form['email'] ?? _pendingEmail ?? '').trim();
    final password = form['password'] ?? _pendingPassword ?? '';

    if (email.isEmpty || password.isEmpty) {
      return _htmlResponse(_renderPage(error: 'Inserisci email e password'));
    }

    try {
      await _auth.logIn(
        email: email,
        password: password,
        twoFactorCode: (code != null && code.isNotEmpty) ? code : null,
      );
      _pendingEmail = null;
      _pendingPassword = null;
      _pendingChallenge = null;
      if (!_signedIn.isCompleted) _signedIn.complete();
      return _htmlResponse(_renderSuccess());
    } on RingTwoFactorRequired catch (challenge) {
      _pendingEmail = email;
      _pendingPassword = password;
      _pendingChallenge = challenge;
      return _htmlResponse(_renderPage(challenge: challenge));
    } on RingException catch (error) {
      return _htmlResponse(_renderPage(error: error.message));
    }
  }

  Response _htmlResponse(String html) =>
      Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});

  String _renderPage({String? error, RingTwoFactorRequired? challenge}) {
    final active = challenge ?? _pendingChallenge;
    final showCodeField = active != null;

    return '''
<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Accedi a Fluring</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; background: #0b0b0d; color: #f2f3f5;
         display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 24px; }
  form { width: 100%; max-width: 360px; }
  h1 { font-size: 22px; margin-bottom: 4px; }
  p.hint { color: #9aa0a8; font-size: 14px; margin-top: 0; }
  input { width: 100%; box-sizing: border-box; font-size: 16px; padding: 12px;
          margin-top: 12px; border-radius: 8px; border: 1px solid #333; background: #16161a; color: #f2f3f5; }
  button { width: 100%; font-size: 16px; padding: 14px; margin-top: 16px; border-radius: 8px;
           border: none; background: #1e88e5; color: white; font-weight: 600; }
  .error { color: #ff8080; margin-top: 12px; font-size: 14px; }
</style>
</head>
<body>
<form method="post" action="/login">
  <h1>Fluring</h1>
  <p class="hint">${showCodeField ? _challengeHint(active) : 'Accedi con il tuo account Ring'}</p>
  ${showCodeField ? '''
  <input type="hidden" name="email" value="${_escape(_pendingEmail ?? '')}">
  <input type="hidden" name="password" value="${_escape(_pendingPassword ?? '')}">
  <input name="code" type="text" inputmode="numeric" placeholder="Codice di verifica" autofocus required>
  ''' : '''
  <input name="email" type="email" placeholder="Email" autofocus required>
  <input name="password" type="password" placeholder="Password" required>
  '''}
  <button type="submit">${showCodeField ? 'Conferma' : 'Accedi'}</button>
  ${error != null ? '<p class="error">${_escape(error)}</p>' : ''}
</form>
</body>
</html>
''';
  }

  String _renderSuccess() => '''
<!doctype html>
<html lang="it">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fluring</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; background: #0b0b0d; color: #f2f3f5;
         display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; text-align: center; padding: 24px; }
</style>
</head>
<body><p>Accesso riuscito — puoi tornare alla TV e chiudere questa pagina.</p></body>
</html>
''';

  String _challengeHint(RingTwoFactorRequired challenge) {
    if (challenge.isTotp) return 'Inserisci il codice dalla tua app di autenticazione';
    final phone = challenge.phone;
    return phone == null
        ? 'Inserisci il codice che Ring ti ha inviato'
        : 'Inserisci il codice che Ring ha inviato a $phone';
  }

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// The device's own address on the home network, so the QR code points
  /// somewhere the phone can actually reach — 0.0.0.0 or 127.0.0.1 would not.
  Future<String?> _lanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }
}
