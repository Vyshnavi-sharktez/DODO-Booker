import 'package:flutter/material.dart';

/// Drop-in replacement for [GestureDetector] that adds a hand cursor on
/// web/desktop. Wraps the child in a [MouseRegion] with
/// [SystemMouseCursors.click] when an [onTap] or [onLongPress] handler is set.
class Clickable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior behavior;

  const Clickable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: (onTap != null || onLongPress != null)
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: behavior,
        child: child,
      ),
    );
  }
}
