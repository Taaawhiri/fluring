import 'dart:collection';

/// A small in-memory log the app can show on screen.
///
/// The point is entirely to avoid needing `adb logcat` to see why a live view
/// failed to connect: WebRTC signalling has several stages that can each fail
/// silently, and a TV has no console to read. Capped so a long session doesn't
/// grow this without bound; only the most recent activity matters for
/// diagnosing "why didn't the video start just now".
class DiagnosticLog {
  DiagnosticLog._();

  static const _maxEntries = 300;

  static final _entries = ListQueue<DiagnosticEntry>(_maxEntries);

  static List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  static void add(String message) {
    _entries.addLast(DiagnosticEntry(DateTime.now(), message));
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
  }

  static void clear() => _entries.clear();
}

class DiagnosticEntry {
  const DiagnosticEntry(this.time, this.message);

  final DateTime time;
  final String message;

  String get formatted {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s  $message';
  }
}
