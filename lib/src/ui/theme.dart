import 'package:flutter/material.dart';

/// A dark theme sized for a living room.
///
/// TVs are viewed from metres away, not centimetres, so type is scaled up and
/// contrast pushed harder than a phone app would need. Corner radii, shadows
/// and gradients are deliberately generous — flat, sharp-edged rectangles
/// read as dated on a big screen in a way they don't on a phone.
ThemeData buildTvTheme() {
  const seed = Color(0xFF3B9EFF);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF121317),
        surfaceContainerHighest: const Color(0xFF1E2027),
      );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF0A0B0D),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.1,
      ),
      titleMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      ),
      bodyMedium: TextStyle(fontSize: 18, letterSpacing: 0.1),
      labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
  );
}

/// Overscan padding.
///
/// Many TVs crop the edges of the picture; keeping content inside this inset
/// stops titles and the outermost tiles from being cut off.
const tvSafeArea = EdgeInsets.symmetric(horizontal: 48, vertical: 32);

/// The rounding used across cards, tiles and buttons. One shared value keeps
/// every surface reading as part of the same design instead of a mix of
/// sharp and rounded rectangles.
const kSurfaceRadius = 20.0;

/// A pill radius for compact controls like header buttons.
const kPillRadius = 100.0;

/// The soft "lifted off the background" shadow every surface uses, focused
/// or not — this is what turns flat color blocks into cards with depth.
List<BoxShadow> kRestShadow = [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.35),
    blurRadius: 16,
    offset: const Offset(0, 6),
  ),
];

/// A gradient fill for primary call-to-action surfaces, built from the
/// theme's accent — a flat single color reads flatter than it needs to on a
/// screen this size.
LinearGradient kAccentGradient(ColorScheme scheme) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.35)!],
);
