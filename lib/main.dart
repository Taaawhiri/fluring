import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/ring/service_locator.dart';
import 'src/ui/camera_grid.dart';
import 'src/ui/qr_login_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TVs are landscape-only and have no system chrome worth keeping.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const FluringApp());
}

class FluringApp extends StatelessWidget {
  const FluringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluring',
      debugShowCheckedModeBanner: false,
      theme: buildTvTheme(),
      home: const _Root(),
    );
  }
}

/// Decides between the login screen and the grid.
///
/// The check is a stored refresh token, not a live call: the grid's own
/// requests will surface an expired session, and gating the first frame on a
/// network round-trip would just add a blank screen at every launch.
class _Root extends StatefulWidget {
  const _Root();

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
      return QrLoginScreen(
        auth: services.auth,
        onSignedIn: () => setState(() => _signedIn = true),
      );
    }

    return CameraGrid(client: services.client, onSignOut: _signOut);
  }
}
