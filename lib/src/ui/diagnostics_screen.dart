import 'package:flutter/material.dart';

import '../diagnostics/diagnostic_log.dart';
import 'focusable.dart';
import 'theme.dart';

/// Shows recent activity from [DiagnosticLog] on screen — the whole point is
/// to answer "why didn't the video start" without needing `adb logcat`,
/// which a TV has no easy way to run against.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = DiagnosticLog.entries;

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
                    'Diagnostica',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                TvFocusable(
                  autofocus: true,
                  onSelect: () => Navigator.of(context).maybePop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Text(
                      'Indietro',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Le ultime ${DiagnosticLog.entries.length} righe registrate durante login e connessione video.',
              style: const TextStyle(fontSize: 15, color: Colors.white54),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                        'Nessuna attività registrata ancora.\nApri una camera per popolare il log.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, color: Colors.white54),
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          // Newest first — that is the line someone actually
                          // wants after a fresh failed attempt.
                          final entry = entries[entries.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              entry.formatted,
                              style: const TextStyle(
                                fontSize: 15,
                                fontFamily: 'monospace',
                                color: Colors.white70,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
