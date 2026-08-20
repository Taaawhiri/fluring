import 'dart:async';

import 'package:flutter/material.dart';

import '../update/installer.dart';
import '../update/update_service.dart';
import 'focusable.dart';

/// Offers the newer release at the top of the camera grid.
///
/// Checks silently once at launch — deliberately unobtrusive, since updating
/// is never urgent enough to interrupt someone who just wants to see their
/// cameras. [UpdateBannerState.checkNow] lets something else (the header's
/// "Aggiorna" button) trigger the same check on demand, so finding out
/// whether a build is current doesn't require relaunching the app.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.service});

  final UpdateService service;

  @override
  UpdateBannerState createState() => UpdateBannerState();
}

enum _Stage { idle, checking, upToDate, downloading, needsPermission, failed }

class UpdateBannerState extends State<UpdateBanner> {
  static const _installer = Installer();

  AvailableUpdate? _update;
  _Stage _stage = _Stage.idle;
  double _progress = 0;
  Timer? _autoHide;

  @override
  void initState() {
    super.initState();
    _check(silent: true);
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    super.dispose();
  }

  /// Re-runs the check right now, showing "checking" and then a brief
  /// "up to date" confirmation if nothing changed — the visible feedback a
  /// silent launch-time check doesn't need, but a manual one does.
  Future<void> checkNow() => _check(silent: false);

  Future<void> _check({required bool silent}) async {
    _autoHide?.cancel();
    if (!silent && mounted) setState(() => _stage = _Stage.checking);

    // Never throws by contract; null simply means nothing to offer.
    final update = await widget.service.check();
    if (!mounted) return;

    if (update != null) {
      setState(() {
        _update = update;
        _stage = _Stage.idle;
      });
      return;
    }

    if (silent) return;

    setState(() => _stage = _Stage.upToDate);
    _autoHide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _stage = _Stage.idle);
    });
  }

  Future<void> _install() async {
    final update = _update;
    if (update == null || _stage == _Stage.downloading) return;

    // Ask for the permission before spending bandwidth on a download that
    // could not be installed anyway.
    if (!await _installer.canInstall()) {
      if (mounted) setState(() => _stage = _Stage.needsPermission);
      await _installer.openPermissionSettings();
      return;
    }

    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
    });

    try {
      final file = await widget.service.download(
        update,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      await _installer.install(file.path);
      // The system installer takes over from here; leave the banner showing
      // progress complete rather than guessing whether the user confirmed.
    } on Object {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    final visible =
        update != null ||
        _stage == _Stage.checking ||
        _stage == _Stage.upToDate;
    if (!visible) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final selectable = update != null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.system_update, color: scheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(_message(update), style: const TextStyle(fontSize: 19)),
          ),
          if (_stage == _Stage.downloading)
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      // Only a real, installable update is a target for the D-pad — "checking"
      // and "up to date" are just status, nothing to select.
      child: selectable
          ? TvFocusable(onSelect: _install, child: content)
          : content,
    );
  }

  String _message(AvailableUpdate? update) => switch (_stage) {
    _Stage.checking => 'Controllo aggiornamenti…',
    _Stage.upToDate => 'Hai già la versione più recente',
    _Stage.downloading =>
      'Download versione ${update!.version}… ${(_progress * 100).round()}%',
    _Stage.needsPermission =>
      'Consenti a Fluring di installare app, poi seleziona di nuovo',
    _Stage.failed => 'Aggiornamento fallito — seleziona per riprovare',
    _Stage.idle =>
      update == null
          ? ''
          : 'Versione ${update.version} disponibile — seleziona per aggiornare',
  };
}
