import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../models/annotation.dart';
import '../models/pdf_annotation_region.dart';
import '../models/pdf_word_selection.dart';
import '../services/pdf_render_scheduler.dart';
import 'dictionary_dialog.dart';
import 'selection_toolbar.dart';

class PdfDictionaryRegion extends StatefulWidget {
  final Object identity;
  final Future<PdfWordSelection?> Function(Offset) selectWord;
  final Widget child;
  final Future<void> Function(String)? defineWord;
  final Future<void> Function(PdfWordSelection selection, bool addNote)?
  onAnnotate;
  final Future<PdfWordSelection?> Function(
    PdfWordSelection selection,
    bool start,
    Offset point,
  )?
  adjustSelection;
  final Future<List<PdfAnnotationRegion>> Function()? loadAnnotations;
  final Future<void> Function(Annotation annotation)? onOpenAnnotation;

  const PdfDictionaryRegion({
    super.key,
    required this.identity,
    required this.selectWord,
    required this.child,
    this.defineWord,
    this.onAnnotate,
    this.adjustSelection,
    this.loadAnnotations,
    this.onOpenAnnotation,
  });

  @override
  State<PdfDictionaryRegion> createState() => _PdfDictionaryRegionState();
}

class _PdfDictionaryRegionState extends State<PdfDictionaryRegion> {
  int _generation = 0;
  bool _busy = false;
  PdfWordSelection? _selection;
  List<PdfAnnotationRegion> _annotations = const [];
  final _overlay = OverlayPortalController();
  final _surfaceKey = GlobalKey();
  int _handleRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadAnnotations();
  }

  @override
  void didUpdateWidget(PdfDictionaryRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _generation++;
      _handleRequest++;
      _busy = false;
      _selection = null;
      _annotations = const [];
      if (_overlay.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _overlay.hide();
        });
      }
      _loadAnnotations();
    }
  }

  Future<void> _loadAnnotations() async {
    final loader = widget.loadAnnotations;
    if (loader == null) return;
    final generation = _generation;
    try {
      final annotations = await loader();
      if (!mounted || generation != _generation) return;
      setState(() => _annotations = annotations);
    } on PdfRenderCancelledException {
      // A page turn or pan/zoom transform superseded this mapping.
    } catch (_) {
      // Annotation decoration is optional; a text-layer/render race must not
      // hide the PDF itself.
    }
  }

  Future<void> _select(Offset point) async {
    if (_busy) return;
    _busy = true;
    final generation = _generation;
    try {
      final selection = await widget.selectWord(point);
      if (!mounted ||
          generation != _generation ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (selection == null) return;
      setState(() => _selection = selection);
      if (widget.onAnnotate != null) {
        _overlay.show();
        return;
      }
      await (widget.defineWord?.call(selection.word) ??
          showDictionaryDefinition(context, selection.word));
    } on PdfRenderCancelledException {
      // Navigation or suspension superseded the selected page.
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not read this PDF’s text layer. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          if (!_overlay.isShowing) _selection = null;
        });
      }
    }
  }

  void _clearSelection() {
    _handleRequest++;
    _overlay.hide();
    if (mounted) setState(() => _selection = null);
  }

  Future<void> _moveHandle(bool start, Offset globalPoint) async {
    final selection = _selection;
    final adjust = widget.adjustSelection;
    final surface =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (selection == null || adjust == null || surface == null) return;
    final request = ++_handleRequest;
    final generation = _generation;
    try {
      final adjusted = await adjust(
        selection,
        start,
        surface.globalToLocal(globalPoint),
      );
      if (!mounted ||
          request != _handleRequest ||
          generation != _generation ||
          adjusted == null) {
        return;
      }
      setState(() => _selection = adjusted);
    } on PdfRenderCancelledException {
      // A navigation change superseded the drag.
    } catch (_) {
      // Keep the last valid selection if text geometry becomes unavailable.
    }
  }

  Future<void> _act(String action) async {
    final selection = _selection;
    if (selection == null) return;
    _clearSelection();
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: selection.word));
      case 'dictionary':
        await (widget.defineWord?.call(selection.word) ??
            showDictionaryDefinition(context, selection.word));
      default:
        await widget.onAnnotate?.call(selection, action == 'note');
    }
  }

  Widget _selectionOverlay(BuildContext context) {
    final selection = _selection;
    if (selection == null || selection.boxes.isEmpty) {
      return const SizedBox.shrink();
    }
    final surface =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    if (surface == null) return const SizedBox.shrink();
    final origin = overlay.globalToLocal(surface.localToGlobal(Offset.zero));
    final first = selection.boxes.first;
    final last = selection.boxes.last;
    final anchorY = origin.dy + last.bottom;
    final firstAnchor = origin + first.bottomLeft;
    final lastAnchor = origin + last.bottomRight;
    final toolbarWidth = surface.size.width.clamp(0.0, overlay.size.width);
    final desiredTop = first.top >= 56 || anchorY + 72 > overlay.size.height
        ? origin.dy + first.top - 56
        : anchorY + 24;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const Key('selection-dismiss'),
            behavior: HitTestBehavior.opaque,
            onTap: _clearSelection,
          ),
        ),
        Positioned(
          left: origin.dx.clamp(0.0, overlay.size.width - toolbarWidth),
          top: desiredTop.clamp(
            0.0,
            (overlay.size.height - 48).clamp(0.0, double.infinity),
          ),
          width: toolbarWidth,
          child: SelectionToolbar(
            onCopy: () => _act('copy'),
            onDictionary: () => _act('dictionary'),
            onAddNote: () => _act('note'),
            onUnderline: () => _act('underline'),
          ),
        ),
        if (widget.adjustSelection != null)
          for (final start in [true, false])
            Positioned(
              left: (start ? firstAnchor.dx - 24 : lastAnchor.dx).clamp(
                0.0,
                (overlay.size.width - 24).clamp(0.0, double.infinity),
              ),
              top: (start ? firstAnchor.dy : lastAnchor.dy).clamp(
                0.0,
                (overlay.size.height - 24).clamp(0.0, double.infinity),
              ),
              child: GestureDetector(
                key: Key(
                  start
                      ? 'pdf-selection-start-handle'
                      : 'pdf-selection-end-handle',
                ),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) =>
                    _moveHandle(start, details.globalPosition),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Align(
                    alignment: start ? Alignment.topRight : Alignment.topLeft,
                    child: Container(width: 8, height: 16, color: Colors.black),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _overlay,
    overlayChildBuilder: _selectionOverlay,
    child: RawGestureDetector(
      key: _surfaceKey,
      behavior: HitTestBehavior.opaque,
      gestures: {
        _SingleFingerLongPress:
            GestureRecognizerFactoryWithHandlers<_SingleFingerLongPress>(
              _SingleFingerLongPress.new,
              (recognizer) =>
                  recognizer.onLongPressStart = (details) =>
                      _select(details.localPosition),
            ),
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: CustomPaint(
              painter: _SelectionPainter(_selection, _annotations),
            ),
          ),
          if (widget.onOpenAnnotation != null)
            for (final region in _annotations)
              for (final (boxIndex, box) in region.boxes.indexed)
                Positioned.fromRect(
                  rect: box,
                  child: GestureDetector(
                    key: ValueKey(
                      'pdf-annotation-${region.annotation.id}-$boxIndex',
                    ),
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        widget.onOpenAnnotation?.call(region.annotation),
                  ),
                ),
        ],
      ),
    ),
  );
}

/// A second finger immediately yields to the existing pinch recognizer rather
/// than delaying its start until movement exceeds the long-press touch slop.
class _SingleFingerLongPress extends LongPressGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    final secondPointer =
        state != GestureRecognizerState.ready &&
        primaryPointer != null &&
        event.pointer != primaryPointer;
    super.addAllowedPointer(event);
    if (secondPointer) resolve(GestureDisposition.rejected);
  }
}

class _SelectionPainter extends CustomPainter {
  final PdfWordSelection? selection;
  final List<PdfAnnotationRegion> annotations;
  _SelectionPainter(this.selection, this.annotations);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final underline = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5;
    for (final region in annotations) {
      for (final box in region.boxes) {
        canvas.drawLine(box.bottomLeft, box.bottomRight, underline);
      }
    }
    final current = selection;
    if (current != null) {
      final paint = Paint()..color = const Color(0x55000000);
      for (final box in current.boxes) {
        canvas.drawRect(box, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      selection != oldDelegate.selection ||
      annotations != oldDelegate.annotations;
}
