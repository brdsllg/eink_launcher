import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/screen_insets_service.dart';

/// Shrinks the whole app into the readable part of a cracked panel.
///
/// Everything below this widget sees a smaller screen: [MediaQuery.size], the
/// system padding and the keyboard inset are all reduced, so the file browser's
/// equal bands, the reader's pages and dialogs fit inside the good area with no
/// per-screen changes. The blocked strip is painted white.
class ScreenInsetsFrame extends StatefulWidget {
  const ScreenInsetsFrame({required this.child, this.service, super.key});

  final Widget child;

  /// Tests only; defaults to [ScreenInsetsService.instance].
  final ScreenInsetsService? service;

  @override
  State<ScreenInsetsFrame> createState() => _ScreenInsetsFrameState();
}

class _ScreenInsetsFrameState extends State<ScreenInsetsFrame>
    with WidgetsBindingObserver {
  int _rotation = 0;

  ScreenInsetsService get _service =>
      widget.service ?? ScreenInsetsService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshRotation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Fires when the tablet turns (the window size changes).
  @override
  void didChangeMetrics() => unawaited(_refreshRotation());

  Future<void> _refreshRotation() async {
    final rotation = await _service.rotation();
    if (!mounted || rotation == _rotation) return;
    setState(() => _rotation = rotation);
  }

  static EdgeInsets _minus(EdgeInsets value, EdgeInsets inset) {
    return EdgeInsets.fromLTRB(
      math.max(0, value.left - inset.left),
      math.max(0, value.top - inset.top),
      math.max(0, value.right - inset.right),
      math.max(0, value.bottom - inset.bottom),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && widget.service == null) return widget.child;
    return ValueListenableBuilder<ScreenEdgeSettings>(
      valueListenable: _service.settings,
      child: widget.child,
      builder: (context, settings, child) {
        final mediaQuery = MediaQuery.of(context);
        final inset = ScreenInsetsService.insetsFor(
          settings,
          _rotation,
          mediaQuery.devicePixelRatio,
        );
        if (inset == EdgeInsets.zero) return child!;
        final size = Size(
          math.max(0, mediaQuery.size.width - inset.horizontal),
          math.max(0, mediaQuery.size.height - inset.vertical),
        );
        return ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: inset,
            child: MediaQuery(
              data: mediaQuery.copyWith(
                size: size,
                padding: _minus(mediaQuery.padding, inset),
                viewPadding: _minus(mediaQuery.viewPadding, inset),
                viewInsets: _minus(mediaQuery.viewInsets, inset),
              ),
              child: child!,
            ),
          ),
        );
      },
    );
  }
}
