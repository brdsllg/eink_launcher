import 'package:flutter/material.dart';

import '../../constants.dart';

enum ReaderTapZone { previous, menu, next }

/// Invisible, e-ink-friendly page-turn controls.
///
/// In normal modes the entire viewport accepts taps and horizontal swipes.
/// In free-zoom mode only narrow edge/centre tap targets are installed and
/// swipe recognition is disabled, leaving the remaining surface available to
/// [InteractiveViewer] for panning and zooming.
class TapZoneLayer extends StatefulWidget {
  final Widget? child;
  final VoidCallback onPrevious;
  final VoidCallback onMenu;
  final VoidCallback onNext;
  final bool zoomMode;

  const TapZoneLayer({
    super.key,
    this.child,
    required this.onPrevious,
    required this.onMenu,
    required this.onNext,
    this.zoomMode = false,
  });

  static ReaderTapZone zoneForDx(
    double dx,
    double width, {
    bool zoomMode = false,
  }) {
    if (width <= 0) return ReaderTapZone.menu;
    final edgeRatio = zoomMode ? kTapZoneZoomEdgeRatio : kTapZoneEdgeWidthRatio;
    final clampedDx = dx.clamp(0.0, width);
    if (clampedDx < width * edgeRatio) return ReaderTapZone.previous;
    if (clampedDx >= width * (1 - edgeRatio)) return ReaderTapZone.next;
    return ReaderTapZone.menu;
  }

  @override
  State<TapZoneLayer> createState() => _TapZoneLayerState();
}

class _TapZoneLayerState extends State<TapZoneLayer> {
  double _dragDistance = 0;

  void _dispatch(ReaderTapZone zone) {
    switch (zone) {
      case ReaderTapZone.previous:
        widget.onPrevious();
      case ReaderTapZone.menu:
        widget.onMenu();
      case ReaderTapZone.next:
        widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (widget.zoomMode) {
          // Keeping the recognizer above [child] in the widget tree (rather
          // than as an overlaid sibling) lets InteractiveViewer also join the
          // gesture arena. A pan rejects this tap recognizer and reaches the
          // PDF; a stationary tap still turns pages or opens the menu.
          return GestureDetector(
            key: const Key('reader-tap-surface'),
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) => _dispatch(
              TapZoneLayer.zoneForDx(
                details.localPosition.dx,
                width,
                zoomMode: true,
              ),
            ),
            child: widget.child ?? const SizedBox.expand(),
          );
        }

        return GestureDetector(
          key: const Key('reader-tap-surface'),
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _dispatch(
            TapZoneLayer.zoneForDx(details.localPosition.dx, width),
          ),
          onHorizontalDragStart: (_) => _dragDistance = 0,
          onHorizontalDragUpdate: (details) {
            _dragDistance += details.primaryDelta ?? 0;
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            final threshold = width * 0.12;
            if (_dragDistance <= -threshold || velocity <= -450) {
              widget.onNext();
            } else if (_dragDistance >= threshold || velocity >= 450) {
              widget.onPrevious();
            }
            _dragDistance = 0;
          },
          child: widget.child ?? const SizedBox.expand(),
        );
      },
    );
  }
}
