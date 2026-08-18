import 'package:flutter/material.dart';

/// A dark theme sized for a living room.
///
/// TVs are viewed from metres away, not centimetres, so type is scaled up and
/// contrast pushed harder than a phone app would need.
ThemeData buildTvTheme() {
  const seed = Color(0xFF1E88E5);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF0B0B0D),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 34, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
      bodyMedium: TextStyle(fontSize: 18),
      labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
    ),
  );
}

/// Overscan padding.
///
/// Many TVs crop the edges of the picture; keeping content inside this inset
/// stops titles and the outermost tiles from being cut off.
const tvSafeArea = EdgeInsets.symmetric(horizontal: 48, vertical: 32);
