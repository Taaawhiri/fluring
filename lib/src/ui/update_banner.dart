import 'package:flutter/material.dart';

import '../update/installer.dart';
import '../update/update_service.dart';
import 'focusable.dart';

/// Offers the newer release at the top of the camera grid.
///
/// Deliberately unobtrusive: updating is never urgent enough to block the
/// cameras behind a dialog, so this is a strip the user can simply ignore.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.service});

  final UpdateService service;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

enum _Stage { idle, downloading, needsPermission, failed }

class _UpdateBannerState extends State<UpdateBanner> {
  static const _installer = Installer();

  AvailableUpdate? _update;
  _Stage _stage = _Stage.idle;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // Never throws by contract; null simply means nothing to offer.
    final update = await widget.service.check();
    if (mounted && update != null) setState(() => _update = update);
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
    if (update == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TvFocusable(
        onSelect: _install,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: scheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(Icons.system_update, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(child: Text(_message(update), style: const TextStyle(fontSize: 19))),
              if (_stage == _Stage.downloading)
                SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _message(AvailableUpdate update) => switch (_stage) {
        _Stage.downloading =>
          'Downloading version ${update.version}… ${(_progress * 100).round()}%',
        _Stage.needsPermission =>
          'Allow Fluring to install apps, then select this again',
        _Stage.failed => 'Update failed — select to try again',
        _Stage.idle => 'Version ${update.version} is available — select to update',
      };
}
