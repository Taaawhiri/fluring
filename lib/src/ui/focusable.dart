import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// A tappable surface built for a remote control.
///
/// On a TV there is no pointer, so the focused element is the only thing
/// telling the user where they are: focus gets a bright gradient border, a
/// glow and a slight scale-up, all large enough to read across a room. Every
/// surface also carries a soft shadow even at rest, so the UI reads as a
/// stack of cards rather than flat color rectangles. Select and Enter are
/// handled explicitly because Android TV remotes send either one depending on
/// the manufacturer.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    required this.onSelect,
    this.autofocus = false,
    this.borderRadius = kSurfaceRadius,
    double? focusRadius,
  }) : focusRadius = focusRadius ?? borderRadius;

  final Widget child;
  final VoidCallback onSelect;
  final bool autofocus;

  /// The shape at rest.
  final double borderRadius;

  /// The shape once focused. Left unset, focus is only a border and a glow;
  /// a larger value here makes focus a shape change too — the "morph"
  /// Material You uses so state reads even with color and motion off, and
  /// pill controls (which are already fully round) simply have nowhere
  /// further to go.
  final double focusRadius;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  /// Remotes differ by manufacturer: some send `select`, some `enter`, and
  /// game controllers send A. Accept them all as "activate".
  static final _selectKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (!_selectKeys.contains(event.logicalKey)) {
          return KeyEventResult.ignored;
        }
        widget.onSelect();
        return KeyEventResult.handled;
      },
      // The zoom stays small (4%) and callers that place this inside a tight
      // grid leave a margin around each tile for exactly this — see
      // CameraGrid, which insets each tile so the zoom and its shadow have
      // room to breathe without a focused tile overlapping its neighbour.
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                _focused ? widget.focusRadius : widget.borderRadius,
              ),
              border: Border.all(
                color: _focused ? scheme.primary : Colors.white10,
                width: _focused ? 2.5 : 1,
              ),
              boxShadow: _focused
                  ? [
                      // A tight, low-blur ring reads as a crisp outline; the
                      // wide, heavily blurred glow this replaces looked like
                      // a smudge around the tile rather than a border.
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.55),
                        blurRadius: 6,
                        spreadRadius: 0.5,
                      ),
                      ...kRestShadow,
                    ]
                  : kRestShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
