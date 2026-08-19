import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../ring/live_stream.dart';
import '../ring/models.dart';
import '../ring/ring_exceptions.dart';
import '../ring/service_locator.dart';
import 'focusable.dart';

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
          ],
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
              onSelect: _connect,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Text('Retry', style: TextStyle(fontSize: 19)),
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
