import 'package:flutter/services.dart';

/// Hands a downloaded APK to Android's package installer.
///
/// Installing needs a user gesture and the "install unknown apps" permission,
/// neither of which Flutter exposes, so both go through a method channel to
/// MainActivity.
class Installer {
  const Installer();

  static const _channel = MethodChannel('fluring/installer');

  /// Whether Android currently lets this app request an install.
  Future<bool> canInstall() async {
    final allowed = await _channel.invokeMethod<bool>('canInstall');
    return allowed ?? false;
  }

  /// Opens the system screen where the user grants the install permission.
  Future<void> openPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallPermissionSettings');

  /// Launches the installer for [path]. The user still has to confirm.
  Future<void> install(String path) =>
      _channel.invokeMethod<void>('installApk', {'path': path});
}
