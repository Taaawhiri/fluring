import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ring/models.dart';
import '../ring/ring_client.dart';
import '../ring/ring_exceptions.dart';
import '../update/update_service.dart';
import 'focusable.dart';
import 'live_view.dart';
import 'diagnostics_screen.dart';
import 'update_banner.dart';
import 'theme.dart';

/// How often each tile pulls a new still.
///
/// Slow on purpose: Ring rate-limits snapshots, and a battery camera polled
/// aggressively is a camera that dies in a week.
const _snapshotInterval = Duration(seconds: 30);

/// The home screen: every camera as a tile, navigable with the D-pad.
class CameraGrid extends StatefulWidget {
  const CameraGrid({super.key, required this.client, required this.onSignOut});

  final RingClient client;

  /// Clears the saved session and returns to the login screen. Used both when
  /// Ring rejects the stored token and when the user picks "Esci" themselves —
  /// the two cases end up in the same place, so they share one path.
  final VoidCallback onSignOut;

  @override
  State<CameraGrid> createState() => _CameraGridState();
}

class _CameraGridState extends State<CameraGrid> {
  final _updates = UpdateService();

  List<RingCamera>? _cameras;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final cameras = await widget.client.cameras();
      if (mounted) setState(() => _cameras = cameras);
    } on RingSessionExpired {
      if (mounted) widget.onSignOut();
    } on RingException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: tvSafeArea,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cameras',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                TvFocusable(
                  onSelect: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DiagnosticsScreen(),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bug_report_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Diagnostica', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TvFocusable(
                  onSelect: widget.onSignOut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout, size: 20),
                        SizedBox(width: 8),
                        Text('Esci', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            UpdateBanner(service: _updates),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return _Message(text: error, actionLabel: 'Retry', onAction: _load);
    }

    final cameras = _cameras;
    if (cameras == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cameras.isEmpty) {
      return const _Message(text: 'No cameras on this Ring account');
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // Kept fairly small on purpose: this delegate can only shrink the
        // column count, never split a leftover into an extra one, so on a
        // lower-resolution TV a large value here divides into too few
        // columns and each tile balloons to fill the remainder. A smaller
        // cap keeps that blow-up small across very different screen sizes.
        maxCrossAxisExtent: 340,
        childAspectRatio: 16 / 11,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: cameras.length,
      itemBuilder: (context, index) => _CameraTile(
        client: widget.client,
        camera: cameras[index],
        autofocus: index == 0,
        onSessionExpired: widget.onSignOut,
      ),
    );
  }
}

class _CameraTile extends StatefulWidget {
  const _CameraTile({
    required this.client,
    required this.camera,
    required this.autofocus,
    required this.onSessionExpired,
  });

  final RingClient client;
  final RingCamera camera;
  final bool autofocus;
  final VoidCallback onSessionExpired;

  @override
  State<_CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<_CameraTile> {
  Uint8List? _image;
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_snapshotInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final bytes = await widget.client.snapshot(widget.camera.id);
      // A null answer means Ring has nothing new; keep the frame already shown
      // rather than blanking the tile.
      if (mounted && bytes != null) setState(() => _image = bytes);
    } on RingSessionExpired {
      if (mounted) widget.onSessionExpired();
    } on RingException {
      // Snapshots are best-effort — a failed poll is not worth an error state,
      // the next tick will try again.
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _openLive() async {
    // Pause polling while the live view owns the camera: two concurrent
    // requests make Ring drop the stream.
    _timer?.cancel();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LiveView(camera: widget.camera)),
    );
    if (!mounted) return;
    _timer = Timer.periodic(_snapshotInterval, (_) => _refresh());
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;

    return TvFocusable(
      autofocus: widget.autofocus,
      onSelect: _openLive,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF16161A)),
          if (image != null)
            Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true)
          else
            Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.videocam_off, size: 48),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.camera.isDoorbell
                        ? Icons.doorbell_outlined
                        : Icons.videocam_outlined,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.camera.description,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.camera.batteryLife != null)
                    Text(
                      '${widget.camera.batteryLife}%',
                      style: const TextStyle(fontSize: 17),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(height: 24),
            TvFocusable(
              autofocus: true,
              onSelect: onAction!,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Text(label, style: const TextStyle(fontSize: 19)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
