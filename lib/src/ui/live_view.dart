import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../ring/live_stream.dart';
import '../ring/models.dart';
import '../ring/ring_exceptions.dart';
import '../ring/service_locator.dart';
import 'focusable.dart';
import 'theme.dart';

/// Full-screen live video for one camera.
///
/// The stream is torn down on the way out, including when the user leaves with
/// the Back button, so the camera is never left awake in the background.
class LiveView extends StatefulWidget {
  const LiveView({super.key, required this.camera});

  final RingCamera camera;

  @override
  State<LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<LiveView> {
  RingLiveStream? _stream;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _stream?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _error = null;
      _ready = false;
    });

    // Drop any previous attempt before dialling again, so a retry never leaves
    // two sessions competing for the same camera.
    await _stream?.dispose();
    final stream = RingLiveStream(
      auth: services.auth,
      cameraId: widget.camera.id,
    );
    _stream = stream;

    try {
      await stream.start();
      if (mounted) setState(() => _ready = true);
    } on RingException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // The remote's actual Back button (goBack) must NOT be handled
          // here: Android already routes it through the platform's back
          // channel straight to Navigator.maybePop(), so also catching it as
          // a raw key event pops twice for one press — once back to the
          // grid, once more out of the app entirely. Only Escape (a plain
          // keyboard, for testing off-device) needs a manual handler.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).maybePop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _content(),
            Positioned(
              left: 48,
              top: 32,
              child: Text(
                widget.camera.description,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                ),
              ),
            ),
            if (_ready) _liveBadge(context),
            if (_ready) _closeButton(context),
          ],
        ),
      ),
    );
  }

  /// A tertiary-container badge — the same "asks for attention" color the
  /// battery chip uses when low, reserved for states like this rather than
  /// spent as a second decorative accent.
  Widget _liveBadge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      right: 48,
      top: 32,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(kPillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: scheme.tertiary,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: scheme.tertiary, blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.tertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A visible way to leave the stream, not just the remote's Back button —
  /// which some remotes map inconsistently, and which a first-time viewer
  /// has no reason to expect closes a full-screen video.
  Widget _closeButton(BuildContext context) {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: TvFocusable(
          borderRadius: kShapeLg,
          onSelect: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: kAccentGradient(Theme.of(context).colorScheme),
            ),
            child: const Icon(Icons.close, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21),
            ),
            const SizedBox(height: 24),
            TvFocusable(
              autofocus: true,
              borderRadius: kPillRadius,
              onSelect: _connect,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: kAccentGradient(Theme.of(context).colorScheme),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final stream = _stream;
    if (!_ready || stream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RTCVideoView(
      stream.renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    );
  }
}
