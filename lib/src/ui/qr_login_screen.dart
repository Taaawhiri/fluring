import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../login_bridge/login_server.dart';
import '../ring/ring_auth.dart';
import 'focusable.dart';
import 'theme.dart';

/// The TV's login screen: a QR code the user scans with their phone, which
/// completes the form there and hands off to the camera grid.
///
/// Typing a Ring password with a D-pad is painful enough that this is the
/// only way in on a TV — there is no on-screen-keyboard fallback here; that
/// form exists, but only for the phone/tablet build (see [LoginScreen]).
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
    setState(() => _error = null);

    final server = LoginServer(auth: widget.auth);
    _server = server;

    final url = await server.start();
    if (!mounted) return;

    if (url == null) {
      setState(
        () => _error = 'Nessuna rete rilevata. Collega la TV al Wi-Fi o al cavo di rete e riprova.',
      );
      return;
    }
    setState(() => _url = url);

    // The page itself completes this once a login on the phone succeeds.
    server.signedIn.then((_) {
      if (mounted) widget.onSignedIn();
    });
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
                if (_error != null) ...[
                  const SizedBox(height: 32),
                  TvFocusable(
                    autofocus: true,
                    borderRadius: kPillRadius,
                    onSelect: _start,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: kAccentGradient(
                          Theme.of(context).colorScheme,
                        ),
                      ),
                      child: const Text(
                        'Riprova',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
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
