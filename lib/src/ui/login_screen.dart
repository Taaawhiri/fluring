import 'package:flutter/material.dart';

import '../ring/ring_auth.dart';
import '../ring/ring_exceptions.dart';
import 'focusable.dart';
import 'theme.dart';

/// Email, password and — when Ring asks — a two-factor code.
///
/// This screen should be seen exactly once per TV: the refresh token saved on
/// success keeps every later launch silent.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.onSignedIn});

  final RingAuth auth;
  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();

  bool _busy = false;
  String? _error;
  RingTwoFactorRequired? _challenge;

  @override
  void initState() {
    super.initState();
    // TextField's autofocus alone often loses the race against this screen's
    // own push transition on Android TV: the platform focus doesn't settle
    // until the animation finishes, so a plain autofocus can land on nothing.
    // Requesting it explicitly after the first frame, once the route has
    // finished animating in, is what actually sticks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ModalRoute.of(context)?.animation?.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _emailFocus.requestFocus();
        }
      });
      // Covers the case where the route is already settled by the first
      // frame (e.g. this screen was not pushed, just built directly).
      if (ModalRoute.of(context)?.animation?.isCompleted ?? true) {
        _emailFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_challenge == null) {
        await widget.auth.logIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await widget.auth.submitTwoFactorCode(
          email: _email.text.trim(),
          password: _password.text,
          code: _code.text,
        );
      }
      if (mounted) widget.onSignedIn();
    } on RingTwoFactorRequired catch (challenge) {
      // Not a failure: Ring wants the code, so swap the form over to it.
      if (mounted) {
        setState(() {
          _challenge = challenge;
          _error = null;
        });
      }
    } on RingException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: tvSafeArea,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Fluring',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  challenge == null
                      ? 'Sign in with your Ring account'
                      : _challengeHint(challenge),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (challenge == null) ...[
                  _field(
                    controller: _email,
                    focusNode: _emailFocus,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    controller: _password,
                    label: 'Password',
                    obscure: true,
                  ),
                ] else
                  _field(
                    controller: _code,
                    focusNode: _codeFocus,
                    label: 'Verification code',
                    autofocus: true,
                    keyboardType: TextInputType.number,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
                TvFocusable(
                  onSelect: _submit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Text(
                              challenge == null ? 'Sign in' : 'Confirm',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
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

  String _challengeHint(RingTwoFactorRequired challenge) {
    if (challenge.isTotp) {
      return 'Enter the code from your authenticator app';
    }
    final phone = challenge.phone;
    return phone == null
        ? 'Enter the verification code Ring sent you'
        : 'Enter the code Ring sent to $phone';
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    FocusNode? focusNode,
    bool obscure = false,
    bool autofocus = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      autofocus: autofocus,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 18),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}
