import 'package:flutter/material.dart';

/// An e-ink tap surface that reverses every painted black/white detail while
/// it is held, including text, icons, dividers, and its background.
class InvertingInkWell extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool invertOnPress;
  final Color color;

  const InvertingInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.invertOnPress = true,
    this.color = Colors.white,
  });

  @override
  State<InvertingInkWell> createState() => _InvertingInkWellState();
}

class _InvertingInkWellState extends State<InvertingInkWell> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool pressed) {
    final next = pressed && _enabled && widget.invertOnPress;
    if (_pressed != next) setState(() => _pressed = next);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ColoredBox(color: widget.color, child: widget.child);
    if (_pressed) {
      child = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1,
          0,
          0,
          0,
          255,
          0,
          -1,
          0,
          0,
          255,
          0,
          0,
          -1,
          0,
          255,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: child,
      );
    }
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onHighlightChanged: _setPressed,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: child,
    );
  }
}

/// Adds the same visual feedback inside a control that already owns its tap
/// gesture, such as Flutter's PopupMenuItem.
class InvertingPressListener extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Color color;

  const InvertingPressListener({
    super.key,
    required this.child,
    this.enabled = true,
    this.color = Colors.white,
  });

  @override
  State<InvertingPressListener> createState() => _InvertingPressListenerState();
}

class _InvertingPressListenerState extends State<InvertingPressListener> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    final next = pressed && widget.enabled;
    if (_pressed != next) setState(() => _pressed = next);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      // Keep this wrapper in the tree for both states. Adding it only after
      // pointer-down rebuilds and disposes a descendant GestureDetector before
      // that detector can recognize a physical long-press.
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(
          _pressed
              ? const [
                  -1,
                  0,
                  0,
                  0,
                  255,
                  0,
                  -1,
                  0,
                  0,
                  255,
                  0,
                  0,
                  -1,
                  0,
                  255,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]
              : const [
                  1,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ],
        ),
        child: ColoredBox(color: widget.color, child: widget.child),
      ),
    );
  }
}
