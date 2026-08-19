import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../login_bridge/login_server.dart';
import '../ring/ring_auth.dart';
import 'focusable.dart';
import 'login_screen.dart';
import 'theme.dart';

/// The TV's half of remote login: shows a QR code, waits for a phone on the
/// same network to complete the form, then hands off to the camera grid.
///
/// Typing a Ring password with a D-pad is painful enough that this is the
/// default entry point; [LoginScreen] — the on-screen-keyboard form — stays
/// reachable underneath for whoever has no second device handy.
class QrLoginScreen extends StatefulWidget {
  const QrLoginScreen({
    super.key,
    required this.auth,
    required this.onSignedIn,
  });

  final RingAuth auth;
  final VoidCallback onSignedIn;

  @override
  State<QrLoginScreen> createState() => _QrLoginScreenState();
}

class _QrLoginScreenState extends State<QrLoginScreen> {
  LoginServer? _server;
  Uri? _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }

  Future<void> _start() async {
    final server = LoginServer(auth: widget.auth);
    _server = server;

    final url = await server.start();
    if (!mounted) return;

    if (url == null) {
      setState(
        () => _error = 'Nessuna rete rilevata. Assicurati che la TV sia connessa al Wi-Fi o al cavo, oppure accedi con la tastiera.',
      );
      return;
    }
    setState(() => _url = url);

    // The page itself completes this once a login on the phone succeeds.
    server.signedIn.then((_) {
      if (mounted) widget.onSignedIn();
    });
  }

  void _useKeyboard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LoginScreen(auth: widget.auth, onSignedIn: widget.onSignedIn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: tvSafeArea,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Fluring',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Inquadra il codice con il telefono per accedere',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _body(),
                const SizedBox(height: 32),
                TvFocusable(
                  autofocus: _url == null,
                  onSelect: _useKeyboard,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Text(
                      'Usa la tastiera invece',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return Text(
        error,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 17,
        ),
        textAlign: TextAlign.center,
      );
    }

    final url = _url;
    if (url == null) {
      return const CircularProgressIndicator();
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          color: Colors.white,
          child: QrImageView(data: url.toString(), size: 220, gapless: false),
        ),
        const SizedBox(height: 16),
        Text(
          url.toString(),
          style: const TextStyle(fontSize: 15, color: Colors.white54),
        ),
        const SizedBox(height: 8),
        const Text(
          'Il telefono deve essere sulla stessa rete Wi-Fi della TV',
          style: TextStyle(fontSize: 14, color: Colors.white38),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        // The certificate is self-signed by necessity — a LAN-only server has
        // no certificate authority to get a trusted one from — so the phone's
        // browser always shows this warning once, and it is expected.
        const Text(
          'Il browser mostrerà un avviso di sicurezza: tocca "Avanzate" → "Procedi comunque"',
          style: TextStyle(fontSize: 13, color: Colors.white38),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
