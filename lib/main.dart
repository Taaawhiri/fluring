import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/platform/device_form_factor.dart';
import 'src/ring/service_locator.dart';
import 'src/ui/camera_grid.dart';
import 'src/ui/login_screen.dart';
import 'src/ui/qr_login_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isTv = await DeviceFormFactor.isTelevision();

  // A TV has no comfortable keyboard and is always mounted landscape; a
  // phone or tablet running the same APK is held upright and expects to
  // stay that way, not get locked into the TV's orientation.
  await SystemChrome.setPreferredOrientations(
    isTv
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(FluringApp(isTv: isTv));
}

class FluringApp extends StatelessWidget {
  const FluringApp({super.key, required this.isTv});

  final bool isTv;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluring',
      debugShowCheckedModeBanner: false,
      theme: buildTvTheme(),
      home: _Root(isTv: isTv),
    );
  }
}

/// Decides between the login screen and the grid.
///
/// The check is a stored refresh token, not a live call: the grid's own
/// requests will surface an expired session, and gating the first frame on a
/// network round-trip would just add a blank screen at every launch.
class _Root extends StatefulWidget {
  const _Root({required this.isTv});

  final bool isTv;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _signedIn;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final hasSession = await services.auth.hasSession;
    if (mounted) setState(() => _signedIn = hasSession);
  }

  Future<void> _signOut() async {
    await services.auth.logOut();
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _signedIn;
    if (signedIn == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!signedIn) {
      // The QR flow exists to dodge typing a password with a D-pad — on a
      // phone or tablet the on-screen keyboard already does that job, so the
      // plain email/password form is both simpler and one less thing that
      // can fail (no local network, no LAN between two devices).
      return widget.isTv
          ? QrLoginScreen(
              auth: services.auth,
              onSignedIn: () => setState(() => _signedIn = true),
            )
          : LoginScreen(
              auth: services.auth,
              onSignedIn: () => setState(() => _signedIn = true),
            );
    }

    return CameraGrid(client: services.client, onSignOut: _signOut);
  }
}
