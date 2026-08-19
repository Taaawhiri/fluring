import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// A release newer than what is installed.
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String version;
  final String downloadUrl;
  final int sizeBytes;
}

/// Checks GitHub Releases for a newer APK and downloads it.
///
/// Android will not let an app replace itself silently — only the system
/// installer can, and it always asks the user. So this goes as far as it can:
/// fetch the APK, then hand it to the package installer, which shows a
/// confirmation the user accepts with the remote.
class UpdateService {
  UpdateService({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// Public repository, so the API needs no token. Unauthenticated GitHub
  /// requests are rate-limited by IP, which a once-per-launch check stays well
  /// inside.
  static const _latestReleaseUrl =
      'https://api.github.com/repos/Taaawhiri/fluring/releases/latest';

  /// The release asset is always named this, which is what keeps the
  /// permanent download link working across versions.
  static const _assetName = 'fluring.apk';

  final http.Client _http;

  /// Returns the newer release, or null when already up to date.
  ///
  /// Never throws: a failed update check must not stop the app from showing
  /// cameras, so any error simply means "no update known right now".
  Future<AvailableUpdate?> check() async {
    try {
      final response = await _http
          .get(
            Uri.parse(_latestReleaseUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = body['tag_name'] as String?;
      if (tag == null) return null;

      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      final current = (await PackageInfo.fromPlatform()).version;
      if (!isVersionNewer(latest, current)) return null;

      final assets = body['assets'];
      if (assets is! List) return null;
      final asset = assets
          .whereType<Map<String, dynamic>>()
          .where((a) => a['name'] == _assetName)
          .firstOrNull;
      final url = asset?['browser_download_url'];
      if (url is! String) return null;

      return AvailableUpdate(
        version: latest,
        downloadUrl: url,
        sizeBytes: (asset?['size'] as num?)?.toInt() ?? 0,
      );
    } on Object {
      return null;
    }
  }

  /// Downloads the APK, reporting progress from 0 to 1, and returns its path.
  Future<File> download(
    AvailableUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(update.downloadUrl));
    final response = await _http.send(request);

    if (response.statusCode != 200) {
      throw HttpException('Download failed (HTTP ${response.statusCode})');
    }

    // The cache directory is the one FileProvider is configured to share with
    // the package installer.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/fluring-${update.version}.apk');
    final sink = file.openWrite();

    // Content-Length can be absent behind a redirect; fall back to the size the
    // release metadata reported so the bar still moves.
    final total = response.contentLength ?? update.sizeBytes;
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0, 1));
      }
    } finally {
      await sink.close();
    }

    return file;
  }

  void dispose() => _http.close();
}

/// Whether [candidate] is a later version than [current].
///
/// Compared segment by segment as numbers, so 0.10.0 correctly beats 0.9.0 —
/// a string comparison would get that backwards.
bool isVersionNewer(String candidate, String current) {
  final a = _versionParts(candidate);
  final b = _versionParts(current);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

List<int> _versionParts(String version) {
  // Drop any pre-release or build suffix before comparing.
  final core = version.split(RegExp('[-+]')).first;
  final numbers = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
