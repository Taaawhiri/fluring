import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A tappable surface built for a remote control.
///
/// On a TV there is no pointer, so the focused element is the only thing
/// telling the user where they are: focus gets a bright border and a slight
/// scale-up, both large enough to read across a room. Select and Enter are
/// handled explicitly because Android TV remotes send either one depending on
/// the manufacturer.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    required this.onSelect,
    this.autofocus = false,
    this.borderRadius = 12,
  });

  final Widget child;
  final VoidCallback onSelect;
  final bool autofocus;
  final double borderRadius;

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
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _focused ? scheme.primary : Colors.transparent,
                width: 3,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.45),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : const [],
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
